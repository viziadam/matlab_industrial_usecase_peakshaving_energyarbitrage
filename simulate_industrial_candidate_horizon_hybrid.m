function [running, simSummary, detail] = simulate_industrial_candidate_horizon_hybrid(industrialCtx, design, cfg)
% SIMULATE_INDUSTRIAL_CANDIDATE_HORIZON_HYBRID
% Combined mode hybrid AC+DC BESS candidate simulation.

    if lower(string(cfg.dispatch.objectiveMode)) ~= "combined"
        error('Hybrid simulation is implemented only for combined mode.');
    end

    required = {'E_BESS_dc_kWh','P_BESS_dc_kW','E_BESS_ac_kWh','P_BESS_ac_kW','E_BESS_kWh','P_BESS_kW','P_inv_kW'};
    for i = 1:numel(required)
        if ~isfield(design, required{i})
            error('Missing hybrid design field: design.%s', required{i});
        end
    end

    day_cache = industrialCtx.day_cache;
    tariff = industrialCtx.tariff;
    nT = numel(day_cache(1).P_load_actual);
    running = init_metrics(nT, cfg);

    pars = struct();
    pars.dc = base_battery_pars_nonideal_(design.E_BESS_dc_kWh, design.P_BESS_dc_kW);
    pars.ac = base_battery_pars_nonideal_(design.E_BESS_ac_kWh, design.P_BESS_ac_kW);

    pars.E_cap_nom = design.E_BESS_kWh;
    pars.P_rated = design.P_BESS_kW;
    pars.P_chg_max = design.P_BESS_kW;
    pars.P_dis_max = design.P_BESS_kW;
    pars.SoC_min = min(pars.dc.SoC_min, pars.ac.SoC_min);
    pars.SoC_max = max(pars.dc.SoC_max, pars.ac.SoC_max);
    pars.SoC_init = 0.5;
    pars.P_inv_limit_ac = design.P_inv_kW;

    pars.central_inv_eta_nom = cfg.converter.central_inv.eta_nom;
    pars.central_inv_eff_load_points = cfg.converter.central_inv.load_points;
    pars.central_inv_eff_eta_points = cfg.converter.central_inv.eta_points;
    pars.dcdc_eta_nom = cfg.converter.dcdc.eta_nom;
    pars.dcdc_eff_load_points = cfg.converter.dcdc.load_points;
    pars.dcdc_eff_eta_points = cfg.converter.dcdc.eta_points;
    pars.pcs_eta_nom = cfg.converter.pcsb.eta_nom;
    pars.pcs_eff_load_points = cfg.converter.pcsb.load_points;
    pars.pcs_eff_eta_points = cfg.converter.pcsb.eta_points;

    pars.inv_eta = pars.central_inv_eta_nom;
    pars.eta_c = pars.dcdc_eta_nom;
    pars.eta_d = pars.dcdc_eta_nom;
    pars.degradation_cost_per_kWh = cfg.dispatch.degradation_cost_per_kWh;
    pars.bessCoupling = "hybrid";
    pars.P_contract_safety_factor = cfg.dispatch.P_contract_safety_factor;
    pars.objectiveMode = "combined";
    pars.energyOnlyGridCap_kW = cfg.dispatch.energyOnlyGridCap_kW;

    search_cfg = industrialCtx.search_cfg;
    search_cfg.contract_min_kW = cfg.contractSearch.min_kW;
    search_cfg.contract_max_kW = cfg.contractSearch.max_kW;
    search_cfg.final_interval_kW = cfg.contractSearch.coarse_step_kW;
    search_cfg.fine_step_kW = cfg.contractSearch.fine_step_kW;
    search_cfg.verbose = cfg.sim.verbose;
    search_cfg.system.bessCoupling = "hybrid";
    search_cfg.dispatch.P_contract_safety_factor = cfg.dispatch.P_contract_safety_factor;
    search_cfg.dispatch.target_step_min = cfg.targetStepMin;
    search_cfg.dispatch.objectiveMode = "combined";
    search_cfg.dispatch.energyOnlyGridCap_kW = cfg.dispatch.energyOnlyGridCap_kW;

    tSearch = tic;
    search_result = search_optimal_contract_capacity(day_cache, industrialCtx.rep_set_proxy, industrialCtx.rep_set_valid, pars, tariff, search_cfg);
    contractSearchRuntime_s = toc(tSearch);
    best_contract_kW = search_result.best_contract_kW;

    tFull = tic;
    [running, full_result, detail] = run_full_horizon_for_fixed_contract_hybrid(day_cache, pars, tariff, best_contract_kW, running, cfg, cfg.diagnostics.storeCandidateDetail, industrialCtx.detail_cfg);
    fullHorizonRuntime_s = toc(tFull);

    if isfield(running.summary, 'bestContract_kW'); running.summary.bestContract_kW = best_contract_kW; end
    if isfield(running.summary, 'finalSoC'); running.summary.finalSoC = full_result.finalSoC; end
    if isfield(running.summary, 'finalSoH'); running.summary.finalSoH = full_result.finalSoH; end
    if isfield(running.summary, 'finalSoCDc'); running.summary.finalSoCDc = full_result.finalSoCdc; end
    if isfield(running.summary, 'finalSoCAc'); running.summary.finalSoCAc = full_result.finalSoCac; end
    if isfield(running.summary, 'finalSoHDc'); running.summary.finalSoHDc = full_result.finalSoHdc; end
    if isfield(running.summary, 'finalSoHAc'); running.summary.finalSoHAc = full_result.finalSoHac; end
    if isfield(running.summary, 'contractSearchRuntime_s'); running.summary.contractSearchRuntime_s = contractSearchRuntime_s; end
    if isfield(running.summary, 'fullHorizonRuntime_s'); running.summary.fullHorizonRuntime_s = fullHorizonRuntime_s; end

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
