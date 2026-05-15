% function [running, simSummary, detail] = simulate_industrial_candidate_horizon( ...
%     industrialCtx, design, cfg)
% % SIMULATE_INDUSTRIAL_CANDIDATE_HORIZON
% %
% % Egy candidate teljes időhorizontos szimulációja.
% %
% % A coupling switch a run_full_horizon_for_fixed_contract belsejében van.
% % Itt csak:
% %   - BESS paraméterezés
% %   - contract search
% %   - full horizon futás
% %   - summary metrikák cfg alapján
% 
%     requiredCtxFields = { ...
%         'day_cache', ...
%         'rep_set_proxy', ...
%         'rep_set_valid', ...
%         'tariff', ...
%         'search_cfg', ...
%         'detail_cfg'};
% 
%     for i = 1:numel(requiredCtxFields)
%         if ~isfield(industrialCtx, requiredCtxFields{i})
%             error('Hiányzó industrialCtx mező: industrialCtx.%s', requiredCtxFields{i});
%         end
%     end
% 
%     requiredDesignFields = { ...
%         'E_BESS_kWh', ...
%         'P_BESS_kW', ...
%         'P_inv_kW'};
% 
%     for i = 1:numel(requiredDesignFields)
%         if ~isfield(design, requiredDesignFields{i})
%             error('Hiányzó design mező: design.%s', requiredDesignFields{i});
%         end
%     end
% 
%     if ~isfield(cfg, 'dispatch')
%         error('Hiányzó cfg mező: cfg.dispatch');
%     end
% 
%     if ~isfield(cfg.dispatch, 'degradation_cost_per_kWh')
%         error('Hiányzó cfg mező: cfg.dispatch.degradation_cost_per_kWh');
%     end
% 
%     if ~isfield(cfg.dispatch, 'P_grid_hard_cap_kW')
%         error('Hiányzó cfg mező: cfg.dispatch.P_grid_hard_cap_kW');
%     end
% 
%     day_cache = industrialCtx.day_cache;
%     tariff = industrialCtx.tariff;
% 
%     nT = numel(day_cache(1).P_load_actual);
% 
%     running = init_metrics(nT, cfg);
% 
%     isNoBessCandidate = ...
%         design.E_BESS_kWh <= 0 || ...
%         design.P_BESS_kW <= 0 || ...
%         design.BESS_PV_ratio <= 0;
% 
%     if isNoBessCandidate
% 
%         [running, simSummary, detail] = simulate_industrial_no_bess_candidate_horizon( ...
%             industrialCtx, ...
%             design, ...
%             cfg);
% 
%         return;
%     end
% 
%     % =====================================================================
%     % 1) BESS paraméterek
%     % =====================================================================
%     pars = base_battery_pars_nonideal_( ...
%         design.E_BESS_kWh, ...
%         design.P_BESS_kW);
% 
%     requiredParsFields = { ...
%         'E_cap_nom', ...
%         'P_rated'};
% 
%     for i = 1:numel(requiredParsFields)
%         if ~isfield(pars, requiredParsFields{i})
%             error('A base_battery_pars_nonideal_ kimenete nem tartalmazza: pars.%s', requiredParsFields{i});
%         end
%     end
% 
%     pars.P_inv_limit_ac = design.P_inv_kW;
%     pars.degradation_cost_per_kWh = cfg.dispatch.degradation_cost_per_kWh;
% 
%     pars.bessCoupling = lower(string(cfg.system.bessCoupling));
% 
%     % if ~isfield(cfg.dispatch, 'P_grid_hard_cap_kW')
%     %     error('Hiányzó cfg.dispatch.P_grid_hard_cap_kW.');
%     % end
%     % 
%     % pars.P_grid_hard_cap_kW = cfg.dispatch.P_grid_hard_cap_kW;
% 
%     if ~isfield(cfg.dispatch, 'P_contract_safety_factor')
%         error('Hiányzó cfg.dispatch.P_contract_safety_factor.');
%     end
% 
%     pars.P_contract_safety_factor = cfg.dispatch.P_contract_safety_factor;
% 
%     fprintf('\n--- CANDIDATE PARAMETER DEBUG ---\n');
%     fprintf('design.E_BESS_kWh       = %.3f\n', design.E_BESS_kWh);
%     fprintf('design.P_BESS_kW        = %.3f\n', design.P_BESS_kW);
%     fprintf('design.P_inv_kW         = %.3f\n', design.P_inv_kW);
%     fprintf('pars.E_cap_nom          = %.3f\n', pars.E_cap_nom);
%     fprintf('pars.P_rated            = %.3f\n', pars.P_rated);
%     fprintf('pars.P_inv_limit_ac     = %.3f\n', pars.P_inv_limit_ac);
%     fprintf('pars.deg_cost_HUF/kWh   = %.3f\n', pars.degradation_cost_per_kWh);
%     fprintf('pars.SoC_min           = %.3f\n', pars.SoC_min);
%     fprintf('pars.SoC_max           = %.3f\n', pars.SoC_max);
%     fprintf('pars.SoC_init          = %.3f\n', pars.SoC_init);
% 
%     if isfield(cfg.dispatch, 'P_grid_hard_cap_kW')
%         fprintf('cfg.dispatch.P_grid_hard_cap_kW = %.3f\n', cfg.dispatch.P_grid_hard_cap_kW);
%     end
% 
%     fprintf('---------------------------------\n');
% 
%     % =====================================================================
%     % 2) Contract search
%     % =====================================================================
%     tSearch = tic;
% 
%     search_result = search_optimal_contract_capacity( ...
%         day_cache, ...
%         industrialCtx.rep_set_proxy, ...
%         industrialCtx.rep_set_valid, ...
%         pars, ...
%         tariff, ...
%         industrialCtx.search_cfg);
% 
%     contractSearchRuntime_s = toc(tSearch);
% 
%     if ~isfield(search_result, 'best_contract_kW')
%         error('A search_optimal_contract_capacity kimenete nem tartalmazza: search_result.best_contract_kW');
%     end
% 
%     best_contract_kW = search_result.best_contract_kW;
% 
%     % =====================================================================
%     % 3) Full horizon
%     % =====================================================================
%     if ~isfield(cfg, 'diagnostics') || ...
%        ~isfield(cfg.diagnostics, 'storeCandidateDetail')
%         error('Hiányzó cfg mező: cfg.diagnostics.storeCandidateDetail');
%     end
% 
%     store_detail = cfg.diagnostics.storeCandidateDetail;
% 
%     tFull = tic;
% 
%     [running, full_result, detail] = run_full_horizon_for_fixed_contract( ...
%         day_cache, ...
%         pars, ...
%         tariff, ...
%         best_contract_kW, ...
%         running, ...
%         cfg, ...
%         store_detail, ...
%         industrialCtx.detail_cfg);
% 
%     fullHorizonRuntime_s = toc(tFull);
% 
%     % =====================================================================
%     % 4) Summary source
%     % =====================================================================
%     summarySource = struct();
% 
%     summarySource.bestContract_kW = best_contract_kW;
%     summarySource.finalSoC = full_result.finalSoC;
%     summarySource.finalSoH = full_result.finalSoH;
%     summarySource.contractSearchRuntime_s = contractSearchRuntime_s;
%     summarySource.fullHorizonRuntime_s = fullHorizonRuntime_s;
% 
%     if isfield(cfg.output, 'summaryMetrics')
% 
%         for i = 1:numel(cfg.output.summaryMetrics)
% 
%             metricName = char(cfg.output.summaryMetrics(i).name);
%             sourceName = char(cfg.output.summaryMetrics(i).source);
% 
%             if ~isfield(summarySource, sourceName)
%                 error('cfg.output.summaryMetrics kért egy nem létező summary source mezőt: %s', sourceName);
%             end
% 
%             if ~isfield(running.summary, metricName)
%                 error('running.summary nem tartalmazza ezt a metrikát: %s', metricName);
%             end
% 
%             running.summary.(metricName) = summarySource.(sourceName);
%         end
%     end
% 
%     % =====================================================================
%     % 5) Output
%     % =====================================================================
%     simSummary = struct();
% 
%     simSummary.design = design;
%     simSummary.pars = pars;
%     simSummary.tariff = tariff;
% 
%     simSummary.bestContract_kW = best_contract_kW;
%     simSummary.search_result = search_result;
%     simSummary.full_result = full_result;
% 
%     simSummary.contractSearchRuntime_s = contractSearchRuntime_s;
%     simSummary.fullHorizonRuntime_s = fullHorizonRuntime_s;
% end

function [running, simSummary, detail] = simulate_industrial_candidate_horizon( ...
    industrialCtx, design, cfg)
% SIMULATE_INDUSTRIAL_CANDIDATE_HORIZON
%
% Egy candidate teljes idohorizontos szimulacioja.
%
% Modositott logika:
%   - BESS parameter generalas,
%   - explicit contract search konfiguracio osszerakasa,
%   - reprezentans havi, topology-alapu contract search,
%   - teljes horizon futas az optimalis contracttal,
%   - summary metrikak kitoltese cfg.output.summaryMetrics alapjan.

    requiredCtxFields = { ...
        'day_cache', ...
        'rep_set_proxy', ...
        'rep_set_valid', ...
        'tariff', ...
        'search_cfg', ...
        'detail_cfg'};

    for i = 1:numel(requiredCtxFields)

        fieldName = requiredCtxFields{i};

        if ~isfield(industrialCtx, fieldName)
            error('Missing industrialCtx field: industrialCtx.%s', fieldName);
        end
    end

    requiredDesignFields = { ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'P_inv_kW', ...
        'BESS_PV_ratio'};

    for i = 1:numel(requiredDesignFields)

        fieldName = requiredDesignFields{i};

        if ~isfield(design, fieldName)
            error('Missing design field: design.%s', fieldName);
        end
    end

    day_cache = industrialCtx.day_cache;
    tariff = industrialCtx.tariff;

    nT = numel(day_cache(1).P_load_actual);

    running = init_metrics(nT, cfg);

    isNoBessCandidate = ...
        design.E_BESS_kWh <= 0 || ...
        design.P_BESS_kW <= 0 || ...
        design.BESS_PV_ratio <= 0;

    if isNoBessCandidate

        [running, simSummary, detail] = simulate_industrial_no_bess_candidate_horizon( ...
            industrialCtx, ...
            design, ...
            cfg);

        return;
    end

    % =====================================================================
    % 1) BESS parameters
    % =====================================================================
    pars = base_battery_pars_nonideal_( ...
        design.E_BESS_kWh, ...
        design.P_BESS_kW);

    requiredParsFields = { ...
        'E_cap_nom', ...
        'P_rated', ...
        'SoC_min', ...
        'SoC_max', ...
        'SoC_init'};

    for i = 1:numel(requiredParsFields)

        fieldName = requiredParsFields{i};

        if ~isfield(pars, fieldName)
            error('base_battery_pars_nonideal_ output missing pars.%s', fieldName);
        end
    end

    pars.P_inv_limit_ac = design.P_inv_kW;
    pars.degradation_cost_per_kWh = cfg.dispatch.degradation_cost_per_kWh;
    pars.bessCoupling = lower(string(cfg.system.bessCoupling));
    pars.P_contract_safety_factor = cfg.dispatch.P_contract_safety_factor;

    if cfg.sim.verbose
        fprintf('\n--- CANDIDATE PARAMETER DEBUG ---\n');
        fprintf('design.E_BESS_kWh     = %.3f\n', design.E_BESS_kWh);
        fprintf('design.P_BESS_kW      = %.3f\n', design.P_BESS_kW);
        fprintf('design.P_inv_kW       = %.3f\n', design.P_inv_kW);
        fprintf('pars.E_cap_nom        = %.3f\n', pars.E_cap_nom);
        fprintf('pars.P_rated          = %.3f\n', pars.P_rated);
        fprintf('pars.P_inv_limit_ac   = %.3f\n', pars.P_inv_limit_ac);
        fprintf('degradation cost      = %.3f HUF/kWh\n', pars.degradation_cost_per_kWh);
        fprintf('SoC range             = %.3f ... %.3f\n', pars.SoC_min, pars.SoC_max);
        fprintf('SoC init              = %.3f\n', pars.SoC_init);
        fprintf('Coupling              = %s\n', string(pars.bessCoupling));
        fprintf('---------------------------------\n');
    end

    % =====================================================================
    % 2) Contract search
    % =====================================================================
    search_cfg = local_build_contract_search_cfg(industrialCtx.search_cfg, cfg);

    tSearch = tic;

    search_result = search_optimal_contract_capacity( ...
        day_cache, ...
        industrialCtx.rep_set_proxy, ...
        industrialCtx.rep_set_valid, ...
        pars, ...
        tariff, ...
        search_cfg);

    contractSearchRuntime_s = toc(tSearch);

    best_contract_kW = search_result.best_contract_kW;

    % =====================================================================
    % 3) Full horizon simulation
    % =====================================================================
    store_detail = cfg.diagnostics.storeCandidateDetail;

    tFull = tic;

    [running, full_result, detail] = run_full_horizon_for_fixed_contract( ...
        day_cache, ...
        pars, ...
        tariff, ...
        best_contract_kW, ...
        running, ...
        cfg, ...
        store_detail, ...
        industrialCtx.detail_cfg);

    fullHorizonRuntime_s = toc(tFull);

    % =====================================================================
    % 4) Summary metrics
    % =====================================================================
    summarySource = struct();

    summarySource.bestContract_kW = best_contract_kW;
    summarySource.finalSoC = full_result.finalSoC;
    summarySource.finalSoH = full_result.finalSoH;
    summarySource.contractSearchRuntime_s = contractSearchRuntime_s;
    summarySource.fullHorizonRuntime_s = fullHorizonRuntime_s;

    if isfield(cfg.output, 'summaryMetrics')

        for i = 1:numel(cfg.output.summaryMetrics)

            metricName = char(cfg.output.summaryMetrics(i).name);
            sourceName = char(cfg.output.summaryMetrics(i).source);

            if ~isfield(summarySource, sourceName)
                error('Missing summary source field: %s', sourceName);
            end

            if ~isfield(running.summary, metricName)
                error('running.summary missing metric: %s', metricName);
            end

            running.summary.(metricName) = summarySource.(sourceName);
        end
    end

    % =====================================================================
    % 5) Output
    % =====================================================================
    simSummary = struct();

    simSummary.design = design;
    simSummary.pars = pars;
    simSummary.tariff = tariff;

    simSummary.bestContract_kW = best_contract_kW;
    simSummary.search_result = search_result;
    simSummary.full_result = full_result;

    simSummary.contractSearchRuntime_s = contractSearchRuntime_s;
    simSummary.fullHorizonRuntime_s = fullHorizonRuntime_s;
end


function search_cfg = local_build_contract_search_cfg(search_cfg_in, cfg)
% LOCAL_BUILD_CONTRACT_SEARCH_CFG
%
% A contract search explicit konfiguracioja.
%
% Itt szandekosan nincs alaperték-potlas. Minden mezot a kozponti cfg-bol
% veszunk at, hogy hiany eseten a hiba latszodjon.

    search_cfg = search_cfg_in;

    search_cfg.contract_min_kW = cfg.contractSearch.min_kW;
    search_cfg.contract_max_kW = cfg.contractSearch.max_kW;

    % A kereso addig felezi az intervallumot, amig az intervallum a
    % durva keresesi lepes merete ala nem er.
    search_cfg.final_interval_kW = cfg.contractSearch.coarse_step_kW;

    search_cfg.fine_step_kW = cfg.contractSearch.fine_step_kW;
    search_cfg.verbose = cfg.sim.verbose;

    search_cfg.system = struct();
    search_cfg.system.bessCoupling = cfg.system.bessCoupling;

    search_cfg.dispatch = struct();
    search_cfg.dispatch.P_contract_safety_factor = ...
        cfg.dispatch.P_contract_safety_factor;

    search_cfg.dispatch.target_step_min = cfg.targetStepMin;
end