function result = simulate_contract_month_for_capacity_hybrid( ...
    day_cache, month_day_indices, pars_in, tariff, contract_kW, search_cfg, store_detail)
% SIMULATE_CONTRACT_MONTH_FOR_CAPACITY_HYBRID
% Representative-month contract evaluation for hybrid AC+DC BESS.

    %#ok<INUSD>

    pars = pars_in;
    target_step_min = search_cfg.dispatch.target_step_min;
    contract_safety_factor = search_cfg.dispatch.P_contract_safety_factor;

    month_day_indices = sort(month_day_indices(:).');
    nDays = numel(month_day_indices);

    if nDays < 1
        error('Hybrid contract month evaluator received an empty month.');
    end

    monthsInYear = 12;
    if isfield(tariff, 'months_in_year')
        monthsInYear = tariff.months_in_year;
    end

    init_dc = struct( ...
        'target_energy_kWh', pars.dc.E_cap_nom, ...
        'max_power_W', pars.dc.P_rated * 1000, ...
        'initial_soc', pars.dc.SoC_init);

    init_ac = struct( ...
        'target_energy_kWh', pars.ac.E_cap_nom, ...
        'max_power_W', pars.ac.P_rated * 1000, ...
        'initial_soc', pars.ac.SoC_init);

    [pack_info_dc, state_dc] = bess_pack_model(0, 'init', init_dc, day_cache(month_day_indices(1)).dt_h, []);
    [pack_info_ac, state_ac] = bess_pack_model(0, 'init', init_ac, day_cache(month_day_indices(1)).dt_h, []);

    pars.dc.E_cap_nom = pack_info_dc.E_installed_kWh;
    pars.ac.E_cap_nom = pack_info_ac.E_installed_kWh;

    pars.dc.SoC_technical_min = pack_info_dc.SoC_technical_min;
    pars.ac.SoC_technical_min = pack_info_ac.SoC_technical_min;

    pars.E_cap_nom = pars.dc.E_cap_nom + pars.ac.E_cap_nom;
    pars.P_contract_safety_factor = contract_safety_factor;

    state_hybrid = struct();
    state_hybrid.dc = state_dc;
    state_hybrid.ac = state_ac;

    monthly_overrun_cost_per_kW = tariff.penalty_rate_huf_per_kW_year / monthsInYear;
    monthly_contract_fee_HUF = ...
        (tariff.annual_contracted_power_fee_huf_per_kW * contract_kW + ...
         tariff.annual_base_fee_huf) / monthsInYear;

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
    detail_days = struct('day_index', {}, 'abs_day', {}, 'type', {}, ...
        'overrun_margin_kW', {}, 'peak_kW', {}, 'final_day', {});

    for kk = 1:nDays

        day_idx = month_day_indices(kk);
        dc = day_cache(day_idx);
        nStep = numel(dc.P_load_actual);

        pars.SoC_initial_dc = state_hybrid.dc.cell_state.SOC;
        pars.SoC_initial_ac = state_hybrid.ac.cell_state.SOC;
        pars.SoC_initial = ...
            (pars.SoC_initial_dc * pars.dc.E_cap_nom + pars.SoC_initial_ac * pars.ac.E_cap_nom) ./ ...
            max(pars.E_cap_nom, eps);

        contract_state = struct();
        contract_state.P_contract_kW = contract_kW;
        contract_state.P_month_max_so_far_kW = current_month_peak;
        contract_state.current_day_of_month = kk;
        contract_state.P_grid_hard_cap_kW = contract_kW;
        contract_state.P_contract_safety_factor = contract_safety_factor;

        dispatch_cfg = struct();
        dispatch_cfg.bessCoupling = "hybrid";
        dispatch_cfg.objectiveMode = "combined";

        if isfield(search_cfg.dispatch, 'energyOnlyGridCap_kW')
            dispatch_cfg.energyOnlyGridCap_kW = search_cfg.dispatch.energyOnlyGridCap_kW;
        else
            dispatch_cfg.energyOnlyGridCap_kW = 1e6;
        end

        try
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
                result = local_infeasible_contract_month_result(contract_kW, month_day_indices, day_cache, nDays, 'Hybrid MILP infeasible.');
                return;
            end

            plan_today = local_slice_plan_to_today(plan_full, nStep);

            req = ems_realtime_decision_hybrid( ...
                dc.P_pv_dc_actual, ...
                dc.P_load_actual, ...
                plan_today, ...
                pars);

            [dayRes, state_hybrid] = topology_hybrid_coupled( ...
                req, ...
                dc.P_pv_dc_actual, ...
                dc.P_load_actual, ...
                dc.Prices_today, ...
                pars, ...
                state_hybrid, ...
                dc.dt_h);

        catch ME
            fprintf('Hybrid contract search failed at contract %.0f kW: %s\n', ...
            contract_kW, ME.message);

            result = local_infeasible_contract_month_result( ...
                contract_kW, month_day_indices, day_cache, nDays, ME.message);
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

        C_energy_step_HUF = buy_total_HUF_per_kWh(:) .* P_grid_import_kW(:) * dc.dt_h;
        C_degradation_step_HUF = pars.degradation_cost_per_kWh * ...
            (dayRes.E_stored(:) + dayRes.E_discharged(:));

        C_overrun_step_HUF = zeros(nStep, 1);
        C_overrun_step_HUF(1) = overrun_increment_cost_HUF;

        C_contract_step_HUF = zeros(nStep, 1);
        C_contract_step_HUF(1) = monthly_contract_fee_HUF / nDays;

        C_objective_step_HUF = ...
            C_energy_step_HUF + C_degradation_step_HUF + C_overrun_step_HUF + C_contract_step_HUF;

        daily_peak_no_bess(kk) = dc.no_bess_peak;
        daily_peak_with_bess(kk) = actual_peak;
        daily_planned_peak(kk) = max(plan_today.P_grid_plan(:));
        daily_energy_cost(kk) = sum(C_energy_step_HUF);
        daily_deg_cost(kk) = sum(C_degradation_step_HUF);
        daily_overrun_cost(kk) = sum(C_overrun_step_HUF);
        daily_contract_cost(kk) = sum(C_contract_step_HUF);
        daily_total_cost(kk) = sum(C_objective_step_HUF);
        daily_bess_throughput(kk) = sum(dayRes.E_stored(:) + dayRes.E_discharged(:));

        if store_detail && kk == nDays
            final_day_detail = struct();
            final_day_detail.plan = plan_today;
            final_day_detail.plan_full = plan_full;
            final_day_detail.res = dayRes;
            final_day_detail.load = dc.P_load_actual;
            final_day_detail.pv = dc.P_pv_dc_actual;
            final_day_detail.price = dc.Prices_today;
            final_day_detail.soc_start_dc = pars.SoC_initial_dc;
            final_day_detail.soc_start_ac = pars.SoC_initial_ac;

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
    result.coupling = 'hybrid';
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
    result.period_overrun_kW = max(0, result.period_peak_with_bess_kW - contract_kW);

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

    result.finalSoCdc = state_hybrid.dc.cell_state.SOC;
    result.finalSoCac = state_hybrid.ac.cell_state.SOC;
    result.finalSoHdc = state_hybrid.dc.cell_state.Deg.SOH;
    result.finalSoHac = state_hybrid.ac.cell_state.Deg.SOH;
    result.finalSoC = ...
        (result.finalSoCdc * pars.dc.E_cap_nom + result.finalSoCac * pars.ac.E_cap_nom) ./ ...
        max(pars.E_cap_nom, eps);
    result.finalSoH = min(result.finalSoHdc, result.finalSoHac);

    result.final_day = final_day_detail;
    result.detail_days = detail_days;
    result.is_feasible = true;
    result.infeasible_reason = "";
end


function tf = local_plan_is_valid(plan)

    tf = isstruct(plan);

    if ~tf
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

    required = {'P_grid_plan', 'P_ch_plan', 'P_dis_plan', 'P_curt_plan', 'SoC_plan'};

    for i = 1:numel(required)
        if ~isfield(plan, required{i})
            tf = false;
            return;
        end
    end
end


function plan_today = local_slice_plan_to_today(plan_full, nDay)

    plan_today = plan_full;
    fields = fieldnames(plan_full);

    for i = 1:numel(fields)
        f = fields{i};
        v = plan_full.(f);

        if (isnumeric(v) || islogical(v)) && isvector(v) && numel(v) >= nDay
            plan_today.(f) = v(1:nDay);
        end
    end
end


function result = local_infeasible_contract_month_result(contract_kW, month_day_indices, day_cache, nDays, reason)

    result = struct();
    result.contract_kW = contract_kW;
    result.coupling = 'hybrid';
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
