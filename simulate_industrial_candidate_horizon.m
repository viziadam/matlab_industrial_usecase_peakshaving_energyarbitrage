function [running, simSummary, detail] = simulate_industrial_candidate_horizon( ...
    industrialCtx, design, cfg)
% SIMULATE_INDUSTRIAL_CANDIDATE_HORIZON
%
% Egy candidate teljes idohorizontos szimulacioja.
% A szimulacio fizikai dontesi logikajat nem modositja, csak a harom
% teljesitmenyatalakito modell parametereit adja at konzekvensen:
%   central_inv : kozponti PV inverter / kozos DC-AC inverter
%   dcdc        : DC-csatolt BESS DC-DC konverter
%   pcsb        : AC-csatolt BESS PCS inverter

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

    if ~isfield(cfg, 'converter') || ...
       ~isfield(cfg.converter, 'central_inv') || ...
       ~isfield(cfg.converter, 'dcdc') || ...
       ~isfield(cfg.converter, 'pcsb')
        error('Missing cfg.converter central_inv/dcdc/pcsb definitions.');
    end

    pars.P_inv_limit_ac = design.P_inv_kW;

    % =====================================================================
    % Power converter efficiency parameters
    % =====================================================================
    % Harom eszkoz, egyseges teljesitmenyfuggo hatasfokmodellel.

    pars.central_inv_eta_nom = cfg.converter.central_inv.eta_nom;
    pars.central_inv_eff_load_points = cfg.converter.central_inv.load_points;
    pars.central_inv_eff_eta_points  = cfg.converter.central_inv.eta_points;

    pars.dcdc_eta_nom = cfg.converter.dcdc.eta_nom;
    pars.dcdc_eff_load_points = cfg.converter.dcdc.load_points;
    pars.dcdc_eff_eta_points  = cfg.converter.dcdc.eta_points;

    pars.pcs_eta_nom = cfg.converter.pcsb.eta_nom;
    pars.pcs_eff_load_points = cfg.converter.pcsb.load_points;
    pars.pcs_eff_eta_points  = cfg.converter.pcsb.eta_points;

    % Regi fallback mezok. Ezek csak kompatibilitas miatt maradnak.
    pars.inv_eta = pars.central_inv_eta_nom;
    pars.eta_c = pars.dcdc_eta_nom;
    pars.eta_d = pars.dcdc_eta_nom;

    pars.degradation_cost_per_kWh = cfg.dispatch.degradation_cost_per_kWh;
    pars.bessCoupling = lower(string(cfg.system.bessCoupling));
    pars.P_contract_safety_factor = cfg.dispatch.P_contract_safety_factor;

    pars.objectiveMode = lower(string(cfg.dispatch.objectiveMode));
    pars.energyOnlyGridCap_kW = cfg.dispatch.energyOnlyGridCap_kW;

    if cfg.sim.verbose
        fprintf('\n--- CANDIDATE PARAMETER DEBUG ---\n');
        fprintf('design.E_BESS_kWh     = %.3f\n', design.E_BESS_kWh);
        fprintf('design.P_BESS_kW      = %.3f\n', design.P_BESS_kW);
        fprintf('design.P_inv_kW       = %.3f\n', design.P_inv_kW);
        fprintf('pars.E_cap_nom        = %.3f\n', pars.E_cap_nom);
        fprintf('pars.P_rated          = %.3f\n', pars.P_rated);
        fprintf('pars.P_inv_limit_ac   = %.3f\n', pars.P_inv_limit_ac);
        fprintf('central_inv eta nom   = %.4f\n', pars.central_inv_eta_nom);
        fprintf('dcdc eta nom          = %.4f\n', pars.dcdc_eta_nom);
        fprintf('pcsb eta nom          = %.4f\n', pars.pcs_eta_nom);
        fprintf('degradation cost      = %.3f HUF/kWh\n', pars.degradation_cost_per_kWh);
        fprintf('SoC range             = %.3f ... %.3f\n', pars.SoC_min, pars.SoC_max);
        fprintf('SoC init              = %.3f\n', pars.SoC_init);
        fprintf('Coupling              = %s\n', string(pars.bessCoupling));
        fprintf('---------------------------------\n');
    end

    % =====================================================================
    % 2) Contract search
    % =====================================================================
    objectiveMode = lower(string(cfg.dispatch.objectiveMode));

    switch objectiveMode
        case "energy_only"

            best_contract_kW = cfg.dispatch.energyOnlyGridCap_kW;

            search_result = struct();
            search_result.best_contract_kW = best_contract_kW;
            search_result.mode = "energy_only_no_contract_search";

            contractSearchRuntime_s = 0;

        otherwise

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
    end

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
    summarySource.finalSoH_pct = 100 * full_result.finalSoH;

    summarySource.finalSoCDc = NaN;
    summarySource.finalSoCAc = NaN;
    summarySource.finalSoHDc = NaN;
    summarySource.finalSoHAc = NaN;

    if isfield(full_result, 'finalSoCDc')
        summarySource.finalSoCDc = full_result.finalSoCDc;
    end

    if isfield(full_result, 'finalSoCAc')
        summarySource.finalSoCAc = full_result.finalSoCAc;
    end

    if isfield(full_result, 'finalSoHDc')
        summarySource.finalSoHDc = full_result.finalSoHDc;
    end

    if isfield(full_result, 'finalSoHAc')
        summarySource.finalSoHAc = full_result.finalSoHAc;
    end

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
    if isfield(full_result, 'runtimeProfile')
        simSummary.fullHorizonProfile = full_result.runtimeProfile;
    else
        simSummary.fullHorizonProfile = struct();
    end
end


function search_cfg = local_build_contract_search_cfg(search_cfg_in, cfg)
% LOCAL_BUILD_CONTRACT_SEARCH_CFG

    search_cfg = search_cfg_in;

    search_cfg.contract_min_kW = cfg.contractSearch.min_kW;
    search_cfg.contract_max_kW = cfg.contractSearch.max_kW;

    search_cfg.final_interval_kW = cfg.contractSearch.coarse_step_kW;
    search_cfg.fine_step_kW = cfg.contractSearch.fine_step_kW;
    search_cfg.verbose = cfg.sim.verbose;

    search_cfg.system = struct();
    search_cfg.system.bessCoupling = cfg.system.bessCoupling;

    search_cfg.dispatch = struct();
    search_cfg.dispatch.P_contract_safety_factor = ...
        cfg.dispatch.P_contract_safety_factor;

    search_cfg.dispatch.target_step_min = cfg.targetStepMin;

    search_cfg.dispatch.objectiveMode = cfg.dispatch.objectiveMode;
    search_cfg.dispatch.energyOnlyGridCap_kW = cfg.dispatch.energyOnlyGridCap_kW;
    search_cfg.E_cap_factor = cfg.contractSearch.E_cap_factor;
end
