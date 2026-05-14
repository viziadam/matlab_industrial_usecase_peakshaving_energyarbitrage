function [running, simSummary, detail] = simulate_industrial_no_bess_candidate_horizon( ...
    industrialCtx, design, cfg)
% SIMULATE_INDUSTRIAL_NO_BESS_CANDIDATE_HORIZON
%
% No-BESS / PV-only baseline candidate futtatása.
%
% Fontos:
%   - nincs BESS planner;
%   - nincs BESS topology;
%   - nincs BESS degradáció;
%   - ugyanazt a dayVectors -> update_metrics útvonalat használja,
%     mint a BESS-es szimuláció;
%   - contract optimalizálás továbbra is van, csak BESS nélküli grid
%     import alapján.

    requiredCtxFields = {'day_cache', 'tariff'};
    for i = 1:numel(requiredCtxFields)
        if ~isfield(industrialCtx, requiredCtxFields{i})
            error('Hiányzó industrialCtx mező: industrialCtx.%s', requiredCtxFields{i});
        end
    end

    if ~isfield(cfg, 'contractSearch')
        error('Hiányzó cfg mező: cfg.contractSearch');
    end

    if ~isfield(cfg.contractSearch, 'min_kW')
        error('Hiányzó cfg.contractSearch.min_kW');
    end

    if ~isfield(cfg.contractSearch, 'max_kW')
        error('Hiányzó cfg.contractSearch.max_kW');
    end

    if ~isfield(cfg.contractSearch, 'fine_step_kW')
        error('Hiányzó cfg.contractSearch.fine_step_kW');
    end

    day_cache = industrialCtx.day_cache;
    tariff = industrialCtx.tariff;

    nDays = numel(day_cache);
    nT = numel(day_cache(1).P_load_actual);

    running = init_metrics(nT, cfg);

    % =====================================================================
    % 1) No-BESS contract keresés
    % =====================================================================
    tSearch = tic;

    contractCandidates = ...
        cfg.contractSearch.min_kW : ...
        cfg.contractSearch.fine_step_kW : ...
        cfg.contractSearch.max_kW;

    if isempty(contractCandidates)
        error('Üres no-BESS contract keresési tartomány.');
    end

    noBessSearch = struct();
    noBessSearch.contract_kW = contractCandidates(:);
    noBessSearch.total_cost_huf = NaN(numel(contractCandidates), 1);
    noBessSearch.energy_cost_huf = NaN(numel(contractCandidates), 1);
    noBessSearch.contract_cost_huf = NaN(numel(contractCandidates), 1);
    noBessSearch.overrun_cost_huf = NaN(numel(contractCandidates), 1);

    for i = 1:numel(contractCandidates)

        c_kW = contractCandidates(i);

        costParts = local_evaluate_no_bess_contract( ...
            day_cache, ...
            tariff, ...
            c_kW);

        noBessSearch.energy_cost_huf(i) = costParts.energy_cost_huf;
        noBessSearch.contract_cost_huf(i) = costParts.contract_cost_huf;
        noBessSearch.overrun_cost_huf(i) = costParts.overrun_cost_huf;
        noBessSearch.total_cost_huf(i) = costParts.total_cost_huf;
    end

    [~, bestIdx] = min(noBessSearch.total_cost_huf);
    best_contract_kW = noBessSearch.contract_kW(bestIdx);

    contractSearchRuntime_s = toc(tSearch);

    % =====================================================================
    % 2) Full horizon no-BESS futás a legjobb contracttal
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
    % 3) Summary metrikák kitöltése
    % =====================================================================
    summarySource = struct();

    summarySource.bestContract_kW = best_contract_kW;
    summarySource.finalSoC = NaN;
    summarySource.finalSoH = NaN;
    summarySource.contractSearchRuntime_s = contractSearchRuntime_s;
    summarySource.fullHorizonRuntime_s = fullHorizonRuntime_s;

    if isfield(cfg.output, 'summaryMetrics')

        for i = 1:numel(cfg.output.summaryMetrics)

            metricName = char(cfg.output.summaryMetrics(i).name);
            sourceName = char(cfg.output.summaryMetrics(i).source);

            if ~isfield(summarySource, sourceName)
                error('cfg.output.summaryMetrics nem létező source mezőt kér: %s', sourceName);
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

        dayRes = struct();
        dayRes.E_grid_import = P_grid_import_kW(:) * dc.dt_h;
        dayRes.E_stored = zeros(N, 1);
        dayRes.E_discharged = zeros(N, 1);
        dayRes.P_curtailment_kW = zeros(N, 1);
        dayRes.SoC = NaN(N, 1);

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