function [running, result, detail] = run_full_horizon_for_fixed_contract_hybrid( ...
    day_cache, pars_in, tariff_in, contract_kW, running, cfg, store_detail, detail_cfg)
% RUN_FULL_HORIZON_FOR_FIXED_CONTRACT_HYBRID
% Full horizon execution for the hybrid AC+DC BESS topology.
%
% Hybrid-specific implementation notes:
%   - DC BESS and AC BESS are simulated as two separate BESS states.
%   - The legacy AC/DC simulation path is not modified by this function.
%   - The hybrid dayVectors are enriched here so the common cfg.output metric
%     list can be saved exactly like in the existing single-coupling modes.

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

    useFastDayAheadMILP = false;
    if isfield(cfg, 'dispatch') && isfield(cfg.dispatch, 'useFastDayAheadMILP')
        useFastDayAheadMILP = logical(cfg.dispatch.useFastDayAheadMILP);
    end

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
        dispatch_cfg.useFastDayAheadMILP = useFastDayAheadMILP;

        if isfield(cfg.dispatch, 'fastMilpSimultaneousPowerTolerance_kW')
            dispatch_cfg.fastMilpSimultaneousPowerTolerance_kW = cfg.dispatch.fastMilpSimultaneousPowerTolerance_kW;
        end

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

        dayVectors = local_enrich_hybrid_dayvectors(dayVectors, dayRes, dc.dt_h);

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
            day_detail.final_day.soc_start = pars.SoC_initial;
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


function dayVectors = local_enrich_hybrid_dayvectors(dayVectors, dayRes, dt_h)

    N = numel(dayVectors.P_load_kW);

    P_central_loss = local_power(dayRes, 'P_loss_central_inv_kW', N, 0);
    P_dcdc_loss = local_power(dayRes, 'P_loss_dcdc_kW', N, 0);
    P_pcs_loss = local_power(dayRes, 'P_loss_pcsb_inv_kW', N, 0);

    P_inv_ac = local_power(dayRes, 'P_inv_ac_kW', N, 0);
    P_bess_dc = local_power(dayRes, 'P_bess_dc_actual_kW', N, 0);
    P_bess_ac = local_power(dayRes, 'P_bess_ac_actual_kW', N, 0);

    dcChargeMask = P_bess_dc < -1e-9;
    dcDischargeMask = P_bess_dc > 1e-9;
    acChargeMask = P_bess_ac < -1e-9;
    acDischargeMask = P_bess_ac > 1e-9;

    dayVectors.P_loss_central_inv_dc_to_ac_kW = zeros(N, 1);
    dayVectors.P_loss_central_inv_ac_to_dc_kW = zeros(N, 1);
    dayVectors.P_loss_central_inv_dc_to_ac_kW(P_inv_ac > 1e-9) = P_central_loss(P_inv_ac > 1e-9);
    dayVectors.P_loss_central_inv_ac_to_dc_kW(P_inv_ac < -1e-9) = P_central_loss(P_inv_ac < -1e-9);

    dayVectors.P_loss_dcdc_charge_kW = zeros(N, 1);
    dayVectors.P_loss_dcdc_discharge_kW = zeros(N, 1);
    dayVectors.P_loss_dcdc_charge_kW(dcChargeMask) = P_dcdc_loss(dcChargeMask);
    dayVectors.P_loss_dcdc_discharge_kW(dcDischargeMask) = P_dcdc_loss(dcDischargeMask);

    dayVectors.P_loss_pcsb_charge_kW = zeros(N, 1);
    dayVectors.P_loss_pcsb_discharge_kW = zeros(N, 1);
    dayVectors.P_loss_pcsb_charge_kW(acChargeMask) = P_pcs_loss(acChargeMask);
    dayVectors.P_loss_pcsb_discharge_kW(acDischargeMask) = P_pcs_loss(acDischargeMask);

    P_loss_internal_dc = local_power(dayRes, 'P_loss_bess_internal_dc_kW', N, 0);
    P_loss_internal_ac = local_power(dayRes, 'P_loss_bess_internal_ac_kW', N, 0);

    E_stored_dc = local_energy(dayRes, 'E_stored_dc', N, 0);
    E_stored_ac = local_energy(dayRes, 'E_stored_ac', N, 0);
    E_dis_dc = local_energy(dayRes, 'E_discharged_dc', N, 0);
    E_dis_ac = local_energy(dayRes, 'E_discharged_ac', N, 0);

    P_loss_internal_charge_dc = local_split_loss_by_energy(P_loss_internal_dc, E_stored_dc, E_dis_dc);
    P_loss_internal_discharge_dc = local_split_loss_by_energy(P_loss_internal_dc, E_dis_dc, E_stored_dc);
    P_loss_internal_charge_ac = local_split_loss_by_energy(P_loss_internal_ac, E_stored_ac, E_dis_ac);
    P_loss_internal_discharge_ac = local_split_loss_by_energy(P_loss_internal_ac, E_dis_ac, E_stored_ac);

    dayVectors.P_loss_bess_internal_charge_kW = P_loss_internal_charge_dc + P_loss_internal_charge_ac;
    dayVectors.P_loss_bess_internal_discharge_kW = P_loss_internal_discharge_dc + P_loss_internal_discharge_ac;

    dayVectors.P_loss_bess_internal_dc_kW = P_loss_internal_dc;
    dayVectors.P_loss_bess_internal_ac_kW = P_loss_internal_ac;
    dayVectors.P_loss_bess_internal_kW = P_loss_internal_dc + P_loss_internal_ac;

    dayVectors.P_total_converter_loss_kW = ...
        dayVectors.P_loss_central_inv_dc_to_ac_kW + ...
        dayVectors.P_loss_central_inv_ac_to_dc_kW + ...
        dayVectors.P_loss_dcdc_charge_kW + ...
        dayVectors.P_loss_dcdc_discharge_kW + ...
        dayVectors.P_loss_pcsb_charge_kW + ...
        dayVectors.P_loss_pcsb_discharge_kW;

    dayVectors.P_bess_charge_dc_kW = E_stored_dc ./ max(dt_h, eps);
    dayVectors.P_bess_charge_ac_kW = E_stored_ac ./ max(dt_h, eps);
    dayVectors.P_bess_discharge_dc_kW = E_dis_dc ./ max(dt_h, eps);
    dayVectors.P_bess_discharge_ac_kW = E_dis_ac ./ max(dt_h, eps);
end


function P = local_power(S, fieldName, N, defaultValue)

    if isfield(S, fieldName)
        P = S.(fieldName)(:);
    else
        P = defaultValue * ones(N, 1);
    end

    P = local_column_to_length(P, N, fieldName);
end


function E = local_energy(S, fieldName, N, defaultValue)

    if isfield(S, fieldName)
        E = S.(fieldName)(:);
    else
        E = defaultValue * ones(N, 1);
    end

    E = local_column_to_length(E, N, fieldName);
end


function y = local_split_loss_by_energy(P_loss, E_selected, E_other)

    denom = E_selected(:) + E_other(:);
    y = zeros(size(P_loss(:)));
    mask = denom > 1e-12;
    y(mask) = P_loss(mask) .* E_selected(mask) ./ denom(mask);
end


function v = local_column_to_length(x, N, name)

    v = x(:);

    if numel(v) ~= N
        error('Hybrid metric enrichment vector length mismatch for %s. Expected %d, got %d.', ...
            name, N, numel(v));
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
