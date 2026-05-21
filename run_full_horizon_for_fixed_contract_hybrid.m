function [running, result, detail] = run_full_horizon_for_fixed_contract_hybrid( ...
    day_cache, pars_in, tariff_in, contract_kW, running, cfg, store_detail, detail_cfg)
% RUN_FULL_HORIZON_FOR_FIXED_CONTRACT_HYBRID
% Full horizon execution for the hybrid AC+DC BESS topology.

    if nargin < 7
        error('Missing input: store_detail.');
    end

    if nargin < 8
        error('Missing input: detail_cfg.');
    end

    pars = pars_in;
    tariff = tariff_in;
    nDays = numel(day_cache);

    if nDays < 1
        error('day_cache is empty.');
    end

    profile = local_empty_profile();
    tFull = tic;

    init_dc = struct('target_energy_kWh', pars.dc.E_cap_nom, ...
        'max_power_W', pars.dc.P_rated * 1000, ...
        'initial_soc', pars.dc.SoC_init);

    init_ac = struct('target_energy_kWh', pars.ac.E_cap_nom, ...
        'max_power_W', pars.ac.P_rated * 1000, ...
        'initial_soc', pars.ac.SoC_init);

    [pack_info_dc, state_dc] = bess_pack_model(0, 'init', init_dc, day_cache(1).dt_h, []);
    [pack_info_ac, state_ac] = bess_pack_model(0, 'init', init_ac, day_cache(1).dt_h, []);

    pars.dc.E_cap_nom = pack_info_dc.E_installed_kWh;
    pars.ac.E_cap_nom = pack_info_ac.E_installed_kWh;
    pars.E_cap_nom = pars.dc.E_cap_nom + pars.ac.E_cap_nom;
    pars.P_contract_safety_factor = cfg.dispatch.P_contract_safety_factor;

    state_hybrid = struct();
    state_hybrid.dc = state_dc;
    state_hybrid.ac = state_ac;

    monthly_overrun_cost_per_kW = tariff.penalty_rate_huf_per_kW_year / 12;
    current_month_id = [];
    current_month_peak = 0;

    daily_peak_with_bess = zeros(1, nDays);
    daily_peak_no_bess = zeros(1, nDays);
    daily_planned_peak = NaN(1, nDays);
    daily_overrun_cost = zeros(1, nDays);
    daily_contract_cost = zeros(1, nDays);
    daily_energy_cost = zeros(1, nDays);
    daily_deg_cost = zeros(1, nDays);
    daily_total_cost = zeros(1, nDays);
    daily_bess_throughput = zeros(1, nDays);
    daily_ref_contract = contract_kW * ones(1, nDays);

    detail_days = struct('day_index', {}, 'abs_day', {}, 'type', {}, ...
        'overrun_margin_kW', {}, 'peak_kW', {}, 'final_day', {});
    overrun_detail_days = detail_days;
    final_day_detail = [];
    planner_debug = struct([]);

    detail_day_indices = unique(detail_cfg.day_indices(:).');
    detail_day_indices = detail_day_indices(detail_day_indices >= 1 & detail_day_indices <= nDays);

    for kk = 1:nDays

        tDay = tic;
        dc = day_cache(kk);

        month_id = floor((dc.abs_day - 1) / 30) + 1;
        if isempty(current_month_id) || month_id ~= current_month_id
            current_month_id = month_id;
            current_month_peak = 0;
        end

        pars.SoC_initial_dc = state_hybrid.dc.cell_state.SOC;
        pars.SoC_initial_ac = state_hybrid.ac.cell_state.SOC;
        pars.SoC_initial = ((pars.SoC_initial_dc * pars.dc.E_cap_nom) + ...
            (pars.SoC_initial_ac * pars.ac.E_cap_nom)) / max(pars.E_cap_nom, eps);

        contract_state = struct();
        contract_state.P_contract_kW = contract_kW;
        contract_state.P_month_max_so_far_kW = current_month_peak;
        contract_state.current_day_of_month = mod(dc.abs_day - 1, 30) + 1;
        contract_state.P_grid_hard_cap_kW = contract_kW;
        contract_state.P_contract_safety_factor = pars.P_contract_safety_factor;

        dispatch_cfg = struct();
        dispatch_cfg.bessCoupling = "hybrid";
        dispatch_cfg.objectiveMode = "combined";
        dispatch_cfg.energyOnlyGridCap_kW = cfg.dispatch.energyOnlyGridCap_kW;

        tStage = tic;
        plan_full = call_day_ahead_planner_by_mode( ...
            dc.P_load_48h, dc.P_pv_48h, dc.Prices_48h, pars, tariff, ...
            dc.dt_h, contract_state, cfg.targetStepMin, dispatch_cfg);
        profile.milp_s = profile.milp_s + toc(tStage);

        nDay = length(dc.P_load_actual);
        plan_today = local_slice_plan_to_today(plan_full, nDay);

        tStage = tic;
        req = ems_realtime_decision_hybrid(dc.P_pv_dc_actual, dc.P_load_actual, plan_today, pars);
        profile.realtimeControl_s = profile.realtimeControl_s + toc(tStage);

        tStage = tic;
        [dayRes, state_hybrid] = topology_hybrid_coupled(req, dc.P_pv_dc_actual, ...
            dc.P_load_actual, dc.Prices_today, pars, state_hybrid, dc.dt_h);
        profile.topology_s = profile.topology_s + toc(tStage);

        tStage = tic;
        P_grid_import_kW = dayRes.E_grid_import(:) / dc.dt_h;
        actual_peak = max(P_grid_import_kW);

        prev_overrun = max(0, current_month_peak - contract_kW);
        current_month_peak = max(current_month_peak, actual_peak);
        new_overrun = max(0, current_month_peak - contract_kW);
        overrun_increment_cost_actual = monthly_overrun_cost_per_kW * (new_overrun - prev_overrun);

        buy_total = dc.Prices_today.buy_huf(:) + ...
            tariff.distribution_energy_rate_huf_per_kWh + ...
            tariff.transmission_energy_rate_huf_per_kWh;

        C_energy_step_HUF = buy_total(:) .* P_grid_import_kW(:) * dc.dt_h;
        C_energy_no_bess_step_HUF = buy_total(:) .* dc.P_grid_no_bess_day(:) * dc.dt_h;
        C_degradation_step_HUF = pars.degradation_cost_per_kWh * ...
            (dayRes.E_stored(:) + dayRes.E_discharged(:));

        C_overrun_step_HUF = zeros(numel(P_grid_import_kW), 1);
        C_overrun_step_HUF(1) = overrun_increment_cost_actual;

        contract_cost_daily_HUF = (tariff.annual_contracted_power_fee_huf_per_kW * contract_kW + ...
            tariff.annual_base_fee_huf) / tariff.days_in_year;
        C_contract_step_HUF = zeros(numel(P_grid_import_kW), 1);
        C_contract_step_HUF(1) = contract_cost_daily_HUF;

        C_objective_step_HUF = C_energy_step_HUF + C_degradation_step_HUF + ...
            C_overrun_step_HUF + C_contract_step_HUF;

        dayVectors = industrial_dayvectors_from_dispatch_result(dc, dayRes, plan_today, ...
            C_energy_step_HUF, C_energy_no_bess_step_HUF, C_degradation_step_HUF, ...
            C_overrun_step_HUF, C_contract_step_HUF, C_objective_step_HUF);

        running = update_metrics(running, dayVectors, dc.dt_h, cfg);

        daily_peak_with_bess(kk) = actual_peak;
        daily_peak_no_bess(kk) = dc.no_bess_peak;
        daily_planned_peak(kk) = plan_today.P_month_peak_candidate;
        daily_overrun_cost(kk) = overrun_increment_cost_actual;
        daily_energy_cost(kk) = sum(C_energy_step_HUF(:));
        daily_deg_cost(kk) = sum(C_degradation_step_HUF(:));
        daily_contract_cost(kk) = sum(C_contract_step_HUF(:));
        daily_total_cost(kk) = sum(C_objective_step_HUF(:));
        daily_bess_throughput(kk) = sum(dayRes.E_stored(:) + dayRes.E_discharged(:));

        profile.aggregation_s = profile.aggregation_s + toc(tStage);

        if store_detail && (ismember(kk, detail_day_indices) || kk == nDays)
            day_detail = struct();
            day_detail.day_index = kk;
            day_detail.abs_day = dc.abs_day;
            day_detail.type = 'hybrid_detail';
            day_detail.overrun_margin_kW = actual_peak - contract_kW;
            day_detail.peak_kW = actual_peak;
            day_detail.final_day = struct();
            day_detail.final_day.plan = plan_today;
            day_detail.final_day.res = dayRes;
            day_detail.final_day.load = dc.P_load_actual;
            day_detail.final_day.pv = dc.P_pv_dc_actual;
            day_detail.final_day.price = dc.Prices_today;
            day_detail.final_day.soc_start_dc = pars.SoC_initial_dc;
            day_detail.final_day.soc_start_ac = pars.SoC_initial_ac;
            day_detail.final_day.dayVectors = dayVectors;
            detail_days(end+1) = day_detail; %#ok<AGROW>
            if kk == nDays
                final_day_detail = day_detail.final_day;
            end
        end

        profile.dayLoopTotal_s = profile.dayLoopTotal_s + toc(tDay);
    end

    finalSoCdc = state_hybrid.dc.cell_state.SOC;
    finalSoCac = state_hybrid.ac.cell_state.SOC;
    finalSoHdc = state_hybrid.dc.cell_state.Deg.SOH;
    finalSoHac = state_hybrid.ac.cell_state.Deg.SOH;
    finalSoC = ((finalSoCdc * pars.dc.E_cap_nom) + (finalSoCac * pars.ac.E_cap_nom)) / max(pars.E_cap_nom, eps);
    finalSoH = min(finalSoHdc, finalSoHac);

    profile.total_s = toc(tFull);

    result = struct();
    result.contract_kW = contract_kW;
    result.days_axis = [day_cache.abs_day];
    result.planner_debug = planner_debug;
    result.daily_peak_with_bess = daily_peak_with_bess;
    result.daily_peak_no_bess = daily_peak_no_bess;
    result.daily_planned_peak = daily_planned_peak;
    result.daily_overrun_cost = daily_overrun_cost;
    result.daily_energy_cost = daily_energy_cost;
    result.daily_deg_cost = daily_deg_cost;
    result.daily_total_cost = daily_total_cost;
    result.daily_bess_throughput = daily_bess_throughput;
    result.daily_ref_contract = daily_ref_contract;
    result.daily_contract_cost = daily_contract_cost;
    result.finalSoC = finalSoC;
    result.finalSoH = finalSoH;
    result.finalSoCdc = finalSoCdc;
    result.finalSoCac = finalSoCac;
    result.finalSoHdc = finalSoHdc;
    result.finalSoHac = finalSoHac;
    result.total_cost_period_huf = running.scalar.objectiveCost_HUF;
    result.energy_cost_period_huf = running.scalar.energyCost_HUF;
    result.degradation_cost_period_huf = running.scalar.degradationCost_HUF;
    result.overrun_cost_period_huf = running.scalar.overrunCost_HUF;
    result.contract_cost_period_huf = running.scalar.contractCost_HUF;
    result.final_day = final_day_detail;
    result.detail_days = detail_days;
    result.overrun_detail_days = overrun_detail_days;
    result.detail_cfg = detail_cfg;
    result.runtimeProfile = profile;

    detail = struct();
    detail.detail_days = detail_days;
    detail.overrun_detail_days = overrun_detail_days;
    detail.detail_cfg = detail_cfg;
    detail.runtimeProfile = profile;
end


function plan_today = local_slice_plan_to_today(plan_full, nDay)

    plan_today = plan_full;
    fields = fieldnames(plan_full);

    for i = 1:numel(fields)
        f = fields{i};
        v = plan_full.(f);
        if isnumeric(v) || islogical(v)
            if isvector(v) && numel(v) >= nDay
                plan_today.(f) = v(1:nDay);
            end
        end
    end
end


function profile = local_empty_profile()
    profile = struct();
    profile.milp_s = 0;
    profile.realtimeControl_s = 0;
    profile.topology_s = 0;
    profile.aggregation_s = 0;
    profile.dayLoopTotal_s = 0;
    profile.total_s = 0;
end
