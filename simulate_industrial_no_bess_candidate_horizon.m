function [running, simSummary, detail] = simulate_industrial_no_bess_candidate_horizon( ...
    industrialCtx, design, cfg)
% SIMULATE_INDUSTRIAL_NO_BESS_CANDIDATE_HORIZON
%
% No-BESS / PV-only baseline candidate futtatasa.
%
% Fontos:
%   - nincs BESS planner;
%   - nincs BESS topology;
%   - nincs BESS degradacio;
%   - ugyanazt a dayVectors -> update_metrics utvonalat hasznalja,
%     mint a BESS-es szimulacio;
%   - a noBESS referencia lekotott teljesitmenye konfiguraciobol jon:
%       cfg.dispatch.noBessContract_kW

    requiredCtxFields = {'day_cache', 'tariff'};
    for i = 1:numel(requiredCtxFields)
        if ~isfield(industrialCtx, requiredCtxFields{i})
            error('Missing industrialCtx field: industrialCtx.%s', requiredCtxFields{i});
        end
    end

    if ~isfield(cfg, 'dispatch') || ~isfield(cfg.dispatch, 'noBessContract_kW')
        error('Missing cfg.dispatch.noBessContract_kW.');
    end

    day_cache = industrialCtx.day_cache;
    tariff = industrialCtx.tariff;

    nT = numel(day_cache(1).P_load_actual);

    running = init_metrics(nT, cfg);

    % =====================================================================
    % 1) No-BESS fixed contract
    % =====================================================================
    tSearch = tic;

    best_contract_kW = cfg.dispatch.noBessContract_kW;

    costParts = local_evaluate_no_bess_contract( ...
        day_cache, ...
        tariff, ...
        best_contract_kW);

    noBessSearch = struct();
    noBessSearch.contract_kW = best_contract_kW;
    noBessSearch.energy_cost_huf = costParts.energy_cost_huf;
    noBessSearch.contract_cost_huf = costParts.contract_cost_huf;
    noBessSearch.overrun_cost_huf = costParts.overrun_cost_huf;
    noBessSearch.total_cost_huf = costParts.total_cost_huf;
    noBessSearch.mode = "fixed_configured_no_bess_contract";

    contractSearchRuntime_s = toc(tSearch);

    % =====================================================================
    % 2) Full horizon no-BESS futas a konfiguralt contracttal
    % =====================================================================
    tFull = tic;

    [running, full_result, detail] = local_run_no_bess_full_horizon( ...
        day_cache, ...
        tariff, ...
        best_contract_kW, ...
        running, ...
        cfg);

    fullHorizonRuntime_s = toc(tFull);

    % =====================================================================
    % 3) Summary metrikak kitoltese
    % =====================================================================
    summarySource = struct();

    summarySource.bestContract_kW = best_contract_kW;

    summarySource.finalSoC = NaN;
    summarySource.finalSoH = NaN;
    summarySource.finalSoH_pct = NaN;

    summarySource.finalSoCDc = NaN;
    summarySource.finalSoCAc = NaN;
    summarySource.finalSoHDc = NaN;
    summarySource.finalSoHAc = NaN;

    summarySource.finalCycleDegradationFD = 0;
    summarySource.finalCalendarDegradationFD = 0;
    summarySource.finalTotalDegradationFD = 0;

    summarySource.finalCycleDegradationPct = 0;
    summarySource.finalCalendarDegradationPct = 0;

    summarySource.finalCycleDegradationFDDc = 0;
    summarySource.finalCalendarDegradationFDDc = 0;
    summarySource.finalTotalDegradationFDDc = 0;

    summarySource.finalCycleDegradationPctDc = 0;
    summarySource.finalCalendarDegradationPctDc = 0;

    summarySource.finalCycleDegradationFDAc = 0;
    summarySource.finalCalendarDegradationFDAc = 0;
    summarySource.finalTotalDegradationFDAc = 0;

    summarySource.finalCycleDegradationPctAc = 0;
    summarySource.finalCalendarDegradationPctAc = 0;

    summarySource.contractSearchRuntime_s = contractSearchRuntime_s;
    summarySource.fullHorizonRuntime_s = fullHorizonRuntime_s;

    if isfield(cfg.output, 'summaryMetrics')

        for i = 1:numel(cfg.output.summaryMetrics)

            metricName = char(cfg.output.summaryMetrics(i).name);
            sourceName = char(cfg.output.summaryMetrics(i).source);

            if ~isfield(summarySource, sourceName)
                error('cfg.output.summaryMetrics requested missing source field: %s', sourceName);
            end

            running.summary.(metricName) = summarySource.(sourceName);
        end
    end

    % =====================================================================
    % 4) Output
    % =====================================================================
    search_result = struct();
    search_result.best_contract_kW = best_contract_kW;
    search_result.no_bess_search = noBessSearch;

    simSummary = struct();

    simSummary.design = design;
    simSummary.pars = struct();
    simSummary.tariff = tariff;

    simSummary.bestContract_kW = best_contract_kW;
    simSummary.search_result = search_result;
    simSummary.full_result = full_result;

    simSummary.contractSearchRuntime_s = contractSearchRuntime_s;
    simSummary.fullHorizonRuntime_s = fullHorizonRuntime_s;
end


function costParts = local_evaluate_no_bess_contract(day_cache, tariff, contract_kW)

    nDays = numel(day_cache);

    monthly_overrun_cost_per_kW = tariff.penalty_rate_huf_per_kW_year / 12;

    current_month_id = [];
    current_month_peak = 0;

    energy_cost = 0;
    overrun_cost = 0;

    for kk = 1:nDays

        dc = day_cache(kk);

        month_id = local_get_month_id_from_abs_day_4y(dc.abs_day);

        if isempty(current_month_id) || month_id ~= current_month_id
            current_month_id = month_id;
            current_month_peak = 0;
        end

        P_grid_import_kW = dc.P_grid_no_bess_day(:);

        buy_today = dc.Prices_today.buy_huf(:);

        buy_total = buy_today + ...
            tariff.distribution_energy_rate_huf_per_kWh + ...
            tariff.transmission_energy_rate_huf_per_kWh;

        energy_cost = energy_cost + ...
            sum(buy_total(:) .* P_grid_import_kW(:)) * dc.dt_h;

        actual_peak = max(P_grid_import_kW);

        prev_overrun = max(0, current_month_peak - contract_kW);
        current_month_peak = max(current_month_peak, actual_peak);
        new_overrun = max(0, current_month_peak - contract_kW);

        overrun_cost = overrun_cost + ...
            monthly_overrun_cost_per_kW * (new_overrun - prev_overrun);
    end

    contract_cost = (nDays / tariff.days_in_year) * ...
        (tariff.annual_contracted_power_fee_huf_per_kW * contract_kW + ...
         tariff.annual_base_fee_huf);

    costParts = struct();
    costParts.energy_cost_huf = energy_cost;
    costParts.contract_cost_huf = contract_cost;
    costParts.overrun_cost_huf = overrun_cost;
    costParts.total_cost_huf = energy_cost + contract_cost + overrun_cost;
end


function [running, result, detail] = local_run_no_bess_full_horizon( ...
    day_cache, tariff, contract_kW, running, cfg)

    nDays = numel(day_cache);

    monthly_overrun_cost_per_kW = tariff.penalty_rate_huf_per_kW_year / 12;

    current_month_id = [];
    current_month_peak = 0;

    daily_peak_with_bess = zeros(1, nDays);
    daily_peak_no_bess = zeros(1, nDays);
    daily_planned_peak = zeros(1, nDays);
    daily_overrun_cost = zeros(1, nDays);

    daily_contract_cost = zeros(1, nDays);

    daily_energy_cost = zeros(1, nDays);
    daily_deg_cost = zeros(1, nDays);
    daily_total_cost = zeros(1, nDays);
    daily_bess_throughput = zeros(1, nDays);
    daily_ref_contract = contract_kW * ones(1, nDays);

    final_day_detail = [];

    for kk = 1:nDays

        dc = day_cache(kk);

        month_id = local_get_month_id_from_abs_day_4y(dc.abs_day);

        if isempty(current_month_id) || month_id ~= current_month_id
            current_month_id = month_id;
            current_month_peak = 0;
        end

        P_grid_import_kW = dc.P_grid_no_bess_day(:);
        N = numel(P_grid_import_kW);

        actual_peak = max(P_grid_import_kW);

        prev_overrun = max(0, current_month_peak - contract_kW);
        current_month_peak = max(current_month_peak, actual_peak);
        new_overrun = max(0, current_month_peak - contract_kW);

        overrun_increment_cost_actual = ...
            monthly_overrun_cost_per_kW * (new_overrun - prev_overrun);

        buy_today = dc.Prices_today.buy_huf(:);

        buy_total = buy_today + ...
            tariff.distribution_energy_rate_huf_per_kWh + ...
            tariff.transmission_energy_rate_huf_per_kWh;

        C_energy_step_HUF = buy_total(:) .* P_grid_import_kW(:) * dc.dt_h;
        C_energy_no_bess_step_HUF = C_energy_step_HUF;

        C_degradation_step_HUF = zeros(N, 1);

        C_overrun_step_HUF = zeros(N, 1);
        C_overrun_step_HUF(1) = overrun_increment_cost_actual;

        contract_cost_daily_HUF = ...
            (tariff.annual_contracted_power_fee_huf_per_kW * contract_kW + ...
             tariff.annual_base_fee_huf) / tariff.days_in_year;

        C_contract_step_HUF = zeros(N, 1);
        C_contract_step_HUF(1) = contract_cost_daily_HUF;

        C_objective_step_HUF = ...
            C_energy_step_HUF + ...
            C_degradation_step_HUF + ...
            C_overrun_step_HUF + ...
            C_contract_step_HUF;

        P_pv_ac_kW = max(dc.P_load_actual(:) - P_grid_import_kW(:), 0);

        dayRes = struct();
        dayRes.E_grid_import = P_grid_import_kW(:) * dc.dt_h;
        dayRes.E_stored = zeros(N, 1);
        dayRes.E_discharged = zeros(N, 1);
        dayRes.P_curtailment_kW = zeros(N, 1);
        dayRes.SoC = NaN(N, 1);

        dayRes.P_pv_ac_kW = P_pv_ac_kW(:);
        dayRes.P_grid_import_kW = P_grid_import_kW(:);
        dayRes.P_grid_export_kW = zeros(N, 1);
        dayRes.P_grid_net_kW = P_grid_import_kW(:);
        dayRes.P_bess_actual_kW = zeros(N, 1);
        dayRes.P_spill_kW = zeros(N, 1);

        dayRes.E_loss_inv = zeros(N, 1);
        dayRes.E_loss_dcdc = zeros(N, 1);
        dayRes.E_loss_joule = zeros(N, 1);
        dayRes.E_curtailment = zeros(N, 1);

        plan_today = struct();
        plan_today.P_grid_plan = P_grid_import_kW(:);
        plan_today.P_ch_plan = zeros(N, 1);
        plan_today.P_dis_plan = zeros(N, 1);
        plan_today.P_curt_plan = zeros(N, 1);
        plan_today.SoC_plan = NaN(N, 1);
        plan_today.P_month_peak_candidate = actual_peak;

        dayVectors = industrial_dayvectors_from_dispatch_result( ...
            dc, ...
            dayRes, ...
            plan_today, ...
            C_energy_step_HUF, ...
            C_energy_no_bess_step_HUF, ...
            C_degradation_step_HUF, ...
            C_overrun_step_HUF, ...
            C_contract_step_HUF, ...
            C_objective_step_HUF);

        running = update_metrics( ...
            running, ...
            dayVectors, ...
            dc.dt_h, ...
            cfg);

        daily_peak_with_bess(kk) = actual_peak;
        daily_peak_no_bess(kk) = dc.no_bess_peak;
        daily_planned_peak(kk) = actual_peak;
        daily_overrun_cost(kk) = overrun_increment_cost_actual;

        daily_energy_cost(kk) = sum(C_energy_step_HUF(:));
        daily_deg_cost(kk) = 0;
        daily_contract_cost(kk) = sum(C_contract_step_HUF(:));
        daily_total_cost(kk) = sum(C_objective_step_HUF(:));
        daily_bess_throughput(kk) = 0;

        if kk == nDays
            final_day_detail = struct();
            final_day_detail.plan = plan_today;
            final_day_detail.res = dayRes;
            final_day_detail.load = dc.P_load_actual;
            final_day_detail.pv = dc.P_pv_dc_actual;
            final_day_detail.price = dc.Prices_today;
            final_day_detail.soc_start = NaN;
            final_day_detail.dayVectors = dayVectors;
        end
    end

    result = struct();

    result.contract_kW = contract_kW;
    result.days_axis = [day_cache.abs_day];

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

    result.finalSoC = NaN;
    result.finalSoH = NaN;

    result.total_cost_period_huf = running.scalar.objectiveCost_HUF;
    result.energy_cost_period_huf = running.scalar.energyCost_HUF;
    result.degradation_cost_period_huf = running.scalar.degradationCost_HUF;
    result.overrun_cost_period_huf = running.scalar.overrunCost_HUF;
    result.contract_cost_period_huf = running.scalar.contractCost_HUF;

    result.final_day = final_day_detail;

    result.detail_days = struct([]);
    result.overrun_detail_days = struct([]);
    result.detail_cfg = struct();

    detail = struct();
    detail.detail_days = result.detail_days;
    detail.overrun_detail_days = result.overrun_detail_days;
    detail.detail_cfg = result.detail_cfg;
end


function month_id = local_get_month_id_from_abs_day_4y(abs_day)
    month_id = floor((abs_day - 1) / 30) + 1;
end
