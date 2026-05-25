function result = simulate_contract_month_for_capacity( ...
    day_cache, month_day_indices, pars_in, tariff, contract_kW, search_cfg, store_detail)
% SIMULATE_CONTRACT_MONTH_FOR_CAPACITY
%
% Egy adott P_contract jelolt havi koltseget szamolja ki.
%
% Ha barmelyik napi MILP infeasible vagy exitflag <= 0,
% akkor a teljes contract jelolt koltsege inf lesz.

    pars = pars_in;

    coupling = lower(string(search_cfg.system.bessCoupling));
    target_step_min = search_cfg.dispatch.target_step_min;
    contract_safety_factor = search_cfg.dispatch.P_contract_safety_factor;

    month_day_indices = sort(month_day_indices(:).');
    nDays = numel(month_day_indices);

    init_params = struct( ...
        'target_energy_kWh', pars.E_cap_nom, ...
        'max_power_W', pars.P_rated * 1000, ...
        'initial_soc', pars.SoC_init);

    [pack_info, state_bess] = bess_pack_model( ...
        0, ...
        'init', ...
        init_params, ...
        day_cache(month_day_indices(1)).dt_h, ...
        []);

    pars.E_cap_nom = pack_info.E_installed_kWh;
    pars.P_contract_safety_factor = contract_safety_factor;

    monthly_overrun_cost_per_kW = ...
        tariff.penalty_rate_huf_per_kW_year / tariff.months_in_year;

    monthly_contract_fee_HUF = ...
        (tariff.annual_contracted_power_fee_huf_per_kW * contract_kW + ...
         tariff.annual_base_fee_huf) / tariff.months_in_year;

    daily_peak_no_bess = zeros(1, nDays);
    daily_peak_with_bess = zeros(1, nDays);
    daily_planned_peak = zeros(1, nDays);

    daily_energy_cost = zeros(1, nDays);
    daily_deg_cost = zeros(1, nDays);
    daily_overrun_cost = zeros(1, nDays);
    daily_contract_cost = zeros(1, nDays);
    daily_total_cost = zeros(1, nDays);

    daily_bess_throughput = zeros(1, nDays);
    daily_ref_contract = contract_kW * ones(1, nDays);

    current_month_peak = 0;

    final_day_detail = [];
    detail_days = struct( ...
        'day_index', {}, ...
        'abs_day', {}, ...
        'type', {}, ...
        'overrun_margin_kW', {}, ...
        'peak_kW', {}, ...
        'final_day', {});

    for kk = 1:nDays

        day_idx = month_day_indices(kk);
        dc = day_cache(day_idx);

        nStep = numel(dc.P_load_actual);

        contract_state = struct();
        contract_state.P_contract_kW = contract_kW;
        contract_state.P_month_max_so_far_kW = current_month_peak;
        contract_state.current_day_of_month = kk;
        contract_state.P_grid_hard_cap_kW = contract_kW;
        contract_state.P_contract_safety_factor = contract_safety_factor;

        pars.SoC_initial = state_bess.cell_state.SOC;

        try
            [plan_full, plan_today, dayRes, state_bess] = local_run_dispatch_day( ...
                coupling, ...
                dc, ...
                pars, ...
                tariff, ...
                contract_state, ...
                state_bess, ...
                target_step_min);
        catch ME
            result = local_infeasible_contract_month_result( ...
                contract_kW, ...
                coupling, ...
                month_day_indices, ...
                day_cache, ...
                nDays, ...
                sprintf('Contract month simulation failed at day %d: %s', kk, ME.message));
            return;
        end

        if ~local_plan_is_valid(plan_full)
            result = local_infeasible_contract_month_result( ...
                contract_kW, ...
                coupling, ...
                month_day_indices, ...
                day_cache, ...
                nDays, ...
                sprintf('MILP infeasible or invalid at day %d', kk));
            return;
        end

        if ~isfield(dayRes, 'E_grid_import')
            result = local_infeasible_contract_month_result( ...
                contract_kW, ...
                coupling, ...
                month_day_indices, ...
                day_cache, ...
                nDays, ...
                sprintf('Topology result missing E_grid_import at day %d', kk));
            return;
        end

        P_grid_import_kW = dayRes.E_grid_import(:) / dc.dt_h;

        actual_peak = max(P_grid_import_kW);

        prev_overrun_kW = max(0, current_month_peak - contract_kW);
        current_month_peak = max(current_month_peak, actual_peak);
        new_overrun_kW = max(0, current_month_peak - contract_kW);

        overrun_increment_cost_HUF = ...
            monthly_overrun_cost_per_kW * (new_overrun_kW - prev_overrun_kW);

        buy_total_HUF_per_kWh = ...
            dc.Prices_today.buy_huf(:) + ...
            tariff.distribution_energy_rate_huf_per_kWh + ...
            tariff.transmission_energy_rate_huf_per_kWh;

        C_energy_step_HUF = ...
            buy_total_HUF_per_kWh(:) .* P_grid_import_kW(:) * dc.dt_h;

        C_energy_no_bess_step_HUF = ...
            buy_total_HUF_per_kWh(:) .* dc.P_grid_no_bess_day(:) * dc.dt_h;

        C_degradation_step_HUF = ...
            pars.degradation_cost_per_kWh * ...
            (dayRes.E_stored(:) + dayRes.E_discharged(:));

        C_overrun_step_HUF = zeros(nStep, 1);
        C_overrun_step_HUF(1) = overrun_increment_cost_HUF;

        C_contract_step_HUF = zeros(nStep, 1);
        C_contract_step_HUF(1) = monthly_contract_fee_HUF / nDays;

        C_objective_step_HUF = ...
            C_energy_step_HUF + ...
            C_degradation_step_HUF + ...
            C_overrun_step_HUF + ...
            C_contract_step_HUF;

        dayVectors = industrial_dayvectors_from_dispatch_result( ...
            dc, ...
            dayRes, ...
            plan_today, ...
            C_energy_step_HUF, ...
            C_energy_no_bess_step_HUF, ...
            C_degradation_step_HUF, ...
            C_overrun_step_HUF, ...
            C_contract_step_HUF, ...
            C_objective_step_HUF); %#ok<NASGU>

        daily_peak_no_bess(kk) = dc.no_bess_peak;
        daily_peak_with_bess(kk) = actual_peak;
        daily_planned_peak(kk) = max(plan_today.P_grid_plan(:));

        daily_energy_cost(kk) = sum(C_energy_step_HUF);
        daily_deg_cost(kk) = sum(C_degradation_step_HUF);
        daily_overrun_cost(kk) = sum(C_overrun_step_HUF);
        daily_contract_cost(kk) = sum(C_contract_step_HUF);
        daily_total_cost(kk) = sum(C_objective_step_HUF);

        daily_bess_throughput(kk) = ...
            sum(dayRes.E_stored(:) + dayRes.E_discharged(:));

        if store_detail && kk == nDays

            final_day_detail = struct();
            final_day_detail.plan = plan_today;
            final_day_detail.plan_full = plan_full;
            final_day_detail.res = dayRes;
            final_day_detail.load = dc.P_load_actual;
            final_day_detail.pv = dc.P_pv_dc_actual;
            final_day_detail.price = dc.Prices_today;
            final_day_detail.soc_start = pars.SoC_initial;
            final_day_detail.dayVectors = dayVectors;

            day_detail = struct();
            day_detail.day_index = day_idx;
            day_detail.abs_day = dc.abs_day;
            day_detail.type = 'final_day';
            day_detail.overrun_margin_kW = actual_peak - contract_kW;
            day_detail.peak_kW = actual_peak;
            day_detail.final_day = final_day_detail;

            detail_days(end + 1) = day_detail; %#ok<AGROW>
        end
    end

    result = struct();

    result.contract_kW = contract_kW;
    result.coupling = char(coupling);
    result.month_day_indices = month_day_indices;
    result.days_axis = [day_cache(month_day_indices).abs_day];

    result.energy_cost_period_huf = sum(daily_energy_cost);
    result.degradation_cost_period_huf = sum(daily_deg_cost);
    result.overrun_cost_period_huf = sum(daily_overrun_cost);
    result.contract_cost_period_huf = sum(daily_contract_cost);

    result.total_cost_period_huf = ...
        result.energy_cost_period_huf + ...
        result.degradation_cost_period_huf + ...
        result.overrun_cost_period_huf + ...
        result.contract_cost_period_huf;

    result.period_days = nDays;
    result.period_peak_with_bess_kW = max(daily_peak_with_bess);
    result.period_overrun_kW = ...
        max(0, result.period_peak_with_bess_kW - contract_kW);

    result.daily_peak_no_bess = daily_peak_no_bess;
    result.daily_peak_with_bess = daily_peak_with_bess;
    result.daily_planned_peak = daily_planned_peak;

    result.daily_energy_cost = daily_energy_cost;
    result.daily_deg_cost = daily_deg_cost;
    result.daily_overrun_cost = daily_overrun_cost;
    result.daily_contract_cost = daily_contract_cost;
    result.daily_total_cost = daily_total_cost;

    result.daily_bess_throughput = daily_bess_throughput;
    result.daily_ref_contract = daily_ref_contract;

    result.finalSoC = state_bess.cell_state.SOC;
    result.finalSoH = state_bess.cell_state.Deg.SOH;

    result.final_day = final_day_detail;
    result.detail_days = detail_days;
    result.is_feasible = true;
    result.infeasible_reason = "";
end


function [plan_full, plan_today, dayRes, state_bess] = local_run_dispatch_day( ...
    coupling, dc, pars, tariff, contract_state, state_bess, target_step_min)

    dispatch_cfg = struct();
    dispatch_cfg.bessCoupling = coupling;
    dispatch_cfg.objectiveMode = "combined";
    dispatch_cfg.useFastDayAheadMILP = search_cfg.dispatch.useFastDayAheadMILP;

    if isfield(pars, 'energyOnlyGridCap_kW')
        dispatch_cfg.energyOnlyGridCap_kW = pars.energyOnlyGridCap_kW;
    else
        dispatch_cfg.energyOnlyGridCap_kW = 1e6;
    end

    plan_full = call_day_ahead_planner_by_mode( ...
        dc.P_load_48h, ...
        dc.P_pv_48h, ...
        dc.Prices_48h, ...
        pars, ...
        tariff, ...
        dc.dt_h, ...
        contract_state, ...
        target_step_min, ...
        dispatch_cfg);

    if ~local_plan_is_valid(plan_full)
        error('Day-ahead MILP returned infeasible/invalid plan.');
    end

    plan_today = local_slice_plan_to_today( ...
        plan_full, ...
        numel(dc.P_load_actual));

    switch coupling

        case "dc"

            P_bess_req_kW = ems_realtime_decision_dc( ...
                dc.P_pv_dc_actual, ...
                dc.P_load_actual, ...
                plan_today, ...
                pars);

            [dayRes, state_bess] = topology_dc_coupled( ...
                P_bess_req_kW, ...
                dc.P_pv_dc_actual, ...
                dc.P_load_actual, ...
                dc.Prices_today, ...
                pars, ...
                state_bess, ...
                dc.dt_h);

        case "ac"

            P_bess_req_kW = ems_realtime_decision_ac( ...
                dc.P_pv_dc_actual, ...
                dc.P_load_actual, ...
                plan_today, ...
                pars);

            [dayRes, state_bess] = topology_ac_coupled( ...
                P_bess_req_kW, ...
                dc.P_pv_dc_actual, ...
                dc.P_load_actual, ...
                dc.Prices_today, ...
                pars, ...
                state_bess, ...
                dc.dt_h);

        otherwise

            error('Invalid BESS coupling mode: %s', coupling);
    end
end


function tf = local_plan_is_valid(plan)

    tf = true;

    if ~isstruct(plan)
        tf = false;
        return;
    end

    if isfield(plan, 'is_feasible') && ~plan.is_feasible
        tf = false;
        return;
    end

    if isfield(plan, 'exitflag') && plan.exitflag <= 0
        tf = false;
        return;
    end

    if isfield(plan, 'objective_value') && ~isfinite(plan.objective_value)
        tf = false;
        return;
    end

    requiredPlanFields = { ...
        'trade_buy_mask', ...
        'trade_sell_mask', ...
        'P_ch_plan', ...
        'P_dis_plan', ...
        'P_grid_plan', ...
        'P_curt_plan', ...
        'SoC_plan'};

    for i = 1:numel(requiredPlanFields)
        if ~isfield(plan, requiredPlanFields{i})
            tf = false;
            return;
        end
    end
end


function result = local_infeasible_contract_month_result( ...
    contract_kW, coupling, month_day_indices, day_cache, nDays, reason)

    result = struct();

    result.contract_kW = contract_kW;
    result.coupling = char(coupling);
    result.month_day_indices = month_day_indices;
    result.days_axis = [day_cache(month_day_indices).abs_day];

    result.energy_cost_period_huf = inf;
    result.degradation_cost_period_huf = inf;
    result.overrun_cost_period_huf = inf;
    result.contract_cost_period_huf = inf;
    result.total_cost_period_huf = inf;

    result.period_days = nDays;
    result.period_peak_with_bess_kW = inf;
    result.period_overrun_kW = inf;

    result.daily_peak_no_bess = NaN(1, nDays);
    result.daily_peak_with_bess = NaN(1, nDays);
    result.daily_planned_peak = NaN(1, nDays);

    result.daily_energy_cost = NaN(1, nDays);
    result.daily_deg_cost = NaN(1, nDays);
    result.daily_overrun_cost = NaN(1, nDays);
    result.daily_contract_cost = NaN(1, nDays);
    result.daily_total_cost = NaN(1, nDays);

    result.daily_bess_throughput = NaN(1, nDays);
    result.daily_ref_contract = contract_kW * ones(1, nDays);

    result.finalSoC = NaN;
    result.finalSoH = NaN;
    result.final_day = [];
    result.detail_days = struct([]);

    result.is_feasible = false;
    result.infeasible_reason = string(reason);
end


function plan_today = local_slice_plan_to_today(plan_full, nDay)

    plan_today = plan_full;

    plan_today.trade_buy_mask = plan_full.trade_buy_mask(1:nDay);
    plan_today.trade_sell_mask = plan_full.trade_sell_mask(1:nDay);

    plan_today.P_ch_plan = plan_full.P_ch_plan(1:nDay);
    plan_today.P_dis_plan = plan_full.P_dis_plan(1:nDay);
    plan_today.P_grid_plan = plan_full.P_grid_plan(1:nDay);
    plan_today.P_curt_plan = plan_full.P_curt_plan(1:nDay);
    plan_today.SoC_plan = plan_full.SoC_plan(1:nDay);

    optionalFields = { ...
        'P_gload_plan', ...
        'P_gbatt_plan', ...
        'P_pvload_plan', ...
        'P_pvbatt_plan', ...
        'P_bload_plan', ...
        'P_spill_plan', ...
        'P_over_plan', ...
        'P_over_step_plan', ...
        'P_pv_ac_plan'};

    for i = 1:numel(optionalFields)
        f = optionalFields{i};
        if isfield(plan_full, f)
            plan_today.(f) = plan_full.(f)(1:nDay);
        end
    end
end
