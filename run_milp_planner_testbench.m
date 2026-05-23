function out = run_milp_planner_testbench(objectiveMode, coupling, candidateIndex, dayIndex, opts)
% RUN_MILP_PLANNER_TESTBENCH
%
% Izolalt MILP planner tesztkornyezet.
%
% Cel:
%   - ugyanazt a cfg/data/context/design/pars/day_cache kornyezetet hasznalja,
%     mint a teljes szimulacio;
%   - lefuttatja a jelenlegi production planner utvonalat;
%   - opcionálisan lefuttat egy modositott planner fuggvenyt;
%   - osszehasonlitja oket mukodesben, idoben es eredmenyekben;
%   - nem modosit DB-t;
%   - nem ment canonical metric cache-t;
%   - nem hiv evaluationt.
%
% Peldak:
%
%   Production DC energy-only teszt:
%       out = run_milp_planner_testbench("energy_only", "dc", 9, 120);
%
%   Production AC energy-only teszt:
%       out = run_milp_planner_testbench("energy_only", "ac", 9, 120);
%
%   Hybrid combined teszt:
%       out = run_milp_planner_testbench("combined", "hybrid", 3, 120);
%
%   Módositott plannerrel:
%       opts = struct();
%       opts.nRepeat = 3;
%       opts.modifiedPlannerFcn = @ems_day_ahead_planner_milp_contract_fast_test;
%       opts.modifiedPlannerSignature = "standard";
%
%       out = run_milp_planner_testbench("combined", "dc", 9, 120, opts);
%
% Opcionalis opts mezok:
%   opts.contract_kW
%   opts.monthPeakSoFar_kW
%   opts.initialSoC
%   opts.initialSoCDc
%   opts.initialSoCAc
%   opts.nRepeat
%   opts.maxSolverTime_s
%   opts.validationTol_kW
%   opts.saveResult
%   opts.makePlots
%   opts.modifiedPlannerFcn
%   opts.modifiedPlannerSignature
%
% modifiedPlannerSignature:
%   "standard"
%       modifiedPlannerFcn(P_load_48h, P_pv_48h, Prices_48h, pars, tariff,
%                          dt_h, contract_state, maxSolverTime_s)
%
%   "dispatcher"
%       modifiedPlannerFcn(P_load_48h, P_pv_48h, Prices_48h, pars, tariff,
%                          dt_h, contract_state, maxSolverTime_s, dispatch_cfg)

    if nargin < 1 || strlength(string(objectiveMode)) == 0
        objectiveMode = "energy_only";
    end

    if nargin < 2 || strlength(string(coupling)) == 0
        coupling = "dc";
    end

    if nargin < 3 || isempty(candidateIndex)
        candidateIndex = 1;
    end

    if nargin < 4 || isempty(dayIndex)
        dayIndex = 1;
    end

    if nargin < 5 || isempty(opts)
        opts = struct();
    end

    objectiveMode = lower(string(objectiveMode));
    coupling = lower(string(coupling));

    if ~(objectiveMode == "peak_only" || objectiveMode == "energy_only" || objectiveMode == "combined")
        error('Invalid objectiveMode: %s', objectiveMode);
    end

    if ~(coupling == "dc" || coupling == "ac" || coupling == "hybrid")
        error('Invalid coupling: %s', coupling);
    end

    if coupling == "hybrid" && objectiveMode ~= "combined"
        error('Hybrid planner is currently implemented only for combined mode.');
    end

    nRepeat = local_get_opt(opts, 'nRepeat', 1);
    validationTol_kW = local_get_opt(opts, 'validationTol_kW', 1e-5);
    saveResult = local_get_opt(opts, 'saveResult', true);
    makePlots = local_get_opt(opts, 'makePlots', true);

    % =====================================================================
    % 1) Ugyanaz a kornyezet, mint a production szimulacioban
    % =====================================================================
    basePath = fileparts(mfilename('fullpath'));

    cfg = create_configurations(basePath);
    cfg.system.bessCoupling = coupling;
    cfg.dispatch.objectiveMode = objectiveMode;

    if coupling == "hybrid"
        cfg = local_apply_hybrid_candidate_settings(cfg);
    end

    cfg.paths.results = fullfile(cfg.paths.results, char(objectiveMode));

    data = build_data(cfg);
    industrialCtx = prepare_industrial_simulation_context(data, cfg);
    DB = init_candidate_database_structures(data, cfg);

    if candidateIndex < 1 || candidateIndex > DB.nCandidates
        error('Invalid candidateIndex. Requested %d, available range is 1...%d.', ...
            candidateIndex, DB.nCandidates);
    end

    if dayIndex < 1 || dayIndex > numel(industrialCtx.day_cache)
        error('Invalid dayIndex. Requested %d, available range is 1...%d.', ...
            dayIndex, numel(industrialCtx.day_cache));
    end

    design = table_row_to_design(DB.candidateTable(candidateIndex, :));
    dc = industrialCtx.day_cache(dayIndex);
    tariff = industrialCtx.tariff;

    pars = local_build_planner_pars_from_design(design, cfg, coupling);

    % =====================================================================
    % 2) SoC es contract allapot
    % =====================================================================
    if coupling == "hybrid"
        pars.SoC_initial_dc = local_get_opt(opts, 'initialSoCDc', 0.5);
        pars.SoC_initial_ac = local_get_opt(opts, 'initialSoCAc', 0.5);
    else
        pars.SoC_initial = local_get_opt(opts, 'initialSoC', 0.5);
    end

    defaultContract_kW = local_default_contract_kW(dc, cfg, objectiveMode);
    contract_kW = local_get_opt(opts, 'contract_kW', defaultContract_kW);
    monthPeakSoFar_kW = local_get_opt(opts, 'monthPeakSoFar_kW', 0);

    contract_state = struct();
    contract_state.P_contract_kW = contract_kW;
    contract_state.P_month_max_so_far_kW = monthPeakSoFar_kW;
    contract_state.current_day_of_month = mod(dc.abs_day - 1, 30) + 1;
    contract_state.P_grid_hard_cap_kW = contract_kW;
    contract_state.P_contract_safety_factor = cfg.dispatch.P_contract_safety_factor;

    if objectiveMode == "energy_only"
        contract_state.P_contract_kW = cfg.dispatch.energyOnlyGridCap_kW;
        contract_state.P_grid_hard_cap_kW = cfg.dispatch.energyOnlyGridCap_kW;
        contract_state.P_contract_safety_factor = 1.0;
        contract_state.P_month_max_so_far_kW = 0;
    end

    dispatch_cfg = struct();
    dispatch_cfg.bessCoupling = coupling;
    dispatch_cfg.objectiveMode = objectiveMode;
    dispatch_cfg.energyOnlyGridCap_kW = cfg.dispatch.energyOnlyGridCap_kW;

    if isfield(cfg.dispatch, 'maxSolverTime_s')
        defaultMaxSolverTime_s = cfg.dispatch.maxSolverTime_s;
    else
        defaultMaxSolverTime_s = cfg.targetStepMin;
    end

    maxSolverTime_s = local_get_opt(opts, 'maxSolverTime_s', defaultMaxSolverTime_s);

    % =====================================================================
    % 3) Production planner futtatasa
    % =====================================================================
    production = local_run_production_planner_repeated( ...
        dc, ...
        pars, ...
        tariff, ...
        contract_state, ...
        maxSolverTime_s, ...
        dispatch_cfg, ...
        nRepeat);

    production.validation = local_validate_plan( ...
        production.plan, ...
        dc, ...
        pars, ...
        coupling, ...
        contract_state, ...
        validationTol_kW);

    % =====================================================================
    % 4) Modositott planner futtatasa, ha megadtuk
    % =====================================================================
    modified = struct();
    hasModifiedPlanner = isfield(opts, 'modifiedPlannerFcn') && ...
                         ~isempty(opts.modifiedPlannerFcn);

    if hasModifiedPlanner

        modifiedSignature = local_get_opt(opts, 'modifiedPlannerSignature', "standard");

        modified = local_run_modified_planner_repeated( ...
            opts.modifiedPlannerFcn, ...
            modifiedSignature, ...
            dc, ...
            pars, ...
            tariff, ...
            contract_state, ...
            maxSolverTime_s, ...
            dispatch_cfg, ...
            nRepeat);

        modified.validation = local_validate_plan( ...
            modified.plan, ...
            dc, ...
            pars, ...
            coupling, ...
            contract_state, ...
            validationTol_kW);

        comparison = local_compare_plans( ...
            production.plan, ...
            modified.plan, ...
            production.runtime_s, ...
            modified.runtime_s);

    else

        comparison = struct();
    end

    % =====================================================================
    % 5) Output
    % =====================================================================
    out = struct();

    out.testInfo = struct();
    out.testInfo.objectiveMode = objectiveMode;
    out.testInfo.coupling = coupling;
    out.testInfo.candidateIndex = candidateIndex;
    out.testInfo.dayIndex = dayIndex;
    out.testInfo.absDay = dc.abs_day;
    out.testInfo.nRepeat = nRepeat;
    out.testInfo.maxSolverTime_s = maxSolverTime_s;
    out.testInfo.hasModifiedPlanner = hasModifiedPlanner;

    out.cfg = cfg;
    out.design = design;
    out.contract_state = contract_state;
    out.pars = pars;

    out.environment = struct();
    out.environment.P_load_48h = dc.P_load_48h(:);
    out.environment.P_pv_48h = dc.P_pv_48h(:);
    out.environment.Prices_48h = dc.Prices_48h;
    out.environment.dt_h = dc.dt_h;

    out.production = production;
    out.modified = modified;
    out.comparison = comparison;

    if hasModifiedPlanner
        out.summaryTable = local_build_summary_table(production, modified, comparison);
    else
        out.summaryTable = local_build_summary_table(production, struct(), comparison);
    end

    if makePlots
        out.figures = local_make_comparison_plots(out);
    else
        out.figures = struct();
    end

    if saveResult
        out.savePath = local_save_test_result(out, cfg);
    else
        out.savePath = "";
    end

    local_print_test_summary(out);
end


% =========================================================================
% PRODUCTION PLANNER
% =========================================================================
function result = local_run_production_planner_repeated( ...
    dc, pars, tariff, contract_state, maxSolverTime_s, dispatch_cfg, nRepeat)

    runtime_s = zeros(nRepeat, 1);
    plan = [];

    for r = 1:nRepeat

        tRun = tic;

        plan = call_day_ahead_planner_by_mode( ...
            dc.P_load_48h, ...
            dc.P_pv_48h, ...
            dc.Prices_48h, ...
            pars, ...
            tariff, ...
            dc.dt_h, ...
            contract_state, ...
            maxSolverTime_s, ...
            dispatch_cfg);

        runtime_s(r) = toc(tRun);
    end

    result = struct();
    result.label = "production";
    result.plan = plan;
    result.runtime_s = runtime_s;
    result.runtime_mean_s = mean(runtime_s);
    result.runtime_min_s = min(runtime_s);
    result.runtime_max_s = max(runtime_s);
    result.runtime_std_s = std(runtime_s);
end


% =========================================================================
% MODIFIED PLANNER
% =========================================================================
function result = local_run_modified_planner_repeated( ...
    modifiedPlannerFcn, modifiedSignature, dc, pars, tariff, contract_state, ...
    maxSolverTime_s, dispatch_cfg, nRepeat)

    modifiedSignature = lower(string(modifiedSignature));

    if ~(modifiedSignature == "standard" || modifiedSignature == "dispatcher")
        error('Invalid modifiedPlannerSignature: %s. Use "standard" or "dispatcher".', ...
            modifiedSignature);
    end

    runtime_s = zeros(nRepeat, 1);
    plan = [];

    for r = 1:nRepeat

        tRun = tic;

        switch modifiedSignature

            case "standard"

                plan = modifiedPlannerFcn( ...
                    dc.P_load_48h, ...
                    dc.P_pv_48h, ...
                    dc.Prices_48h, ...
                    pars, ...
                    tariff, ...
                    dc.dt_h, ...
                    contract_state, ...
                    maxSolverTime_s);

            case "dispatcher"

                plan = modifiedPlannerFcn( ...
                    dc.P_load_48h, ...
                    dc.P_pv_48h, ...
                    dc.Prices_48h, ...
                    pars, ...
                    tariff, ...
                    dc.dt_h, ...
                    contract_state, ...
                    maxSolverTime_s, ...
                    dispatch_cfg);
        end

        runtime_s(r) = toc(tRun);
    end

    result = struct();
    result.label = "modified";
    result.plan = plan;
    result.runtime_s = runtime_s;
    result.runtime_mean_s = mean(runtime_s);
    result.runtime_min_s = min(runtime_s);
    result.runtime_max_s = max(runtime_s);
    result.runtime_std_s = std(runtime_s);
end


% =========================================================================
% CONFIG HELPERS
% =========================================================================
function cfg = local_apply_hybrid_candidate_settings(cfg)

    if ~isfield(cfg, 'candidates')
        cfg.candidates = struct();
    end

    if ~isfield(cfg.candidates, 'hybrid')
        cfg.candidates.hybrid = struct();
    end

    if ~isfield(cfg.candidates.hybrid, 'BESS_PV_ratio_vec') || ...
       isempty(cfg.candidates.hybrid.BESS_PV_ratio_vec)

        cfg.candidates.hybrid.BESS_PV_ratio_vec = [0.8 1.0 1.5 2.0];
    end

    cfg.candidates.designFields = { ...
        'BESS_PV_ratio', ...
        'BESS_PV_ratio_dc', ...
        'BESS_PV_ratio_ac', ...
        'BESS_PV_ratio_total', ...
        'P_PV_A_kW', ...
        'P_PV_B_kW', ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'E_BESS_dc_kWh', ...
        'P_BESS_dc_kW', ...
        'E_BESS_ac_kWh', ...
        'P_BESS_ac_kW'};
end


function pars = local_build_planner_pars_from_design(design, cfg, coupling)

    switch lower(string(coupling))

        case {"dc", "ac"}

            requiredDesignFields = { ...
                'E_BESS_kWh', ...
                'P_BESS_kW', ...
                'P_inv_kW', ...
                'BESS_PV_ratio'};

            for i = 1:numel(requiredDesignFields)
                if ~isfield(design, requiredDesignFields{i})
                    error('Missing design field: design.%s', requiredDesignFields{i});
                end
            end

            if design.E_BESS_kWh <= 0 || design.P_BESS_kW <= 0 || design.BESS_PV_ratio <= 0
                error('MILP testbench requires a BESS candidate. Candidate has zero BESS size.');
            end

            pars = base_battery_pars_nonideal_( ...
                design.E_BESS_kWh, ...
                design.P_BESS_kW);

            pars.P_inv_limit_ac = design.P_inv_kW;

            pars.central_inv_eta_nom = cfg.converter.central_inv.eta_nom;
            pars.central_inv_eff_load_points = cfg.converter.central_inv.load_points;
            pars.central_inv_eff_eta_points  = cfg.converter.central_inv.eta_points;

            pars.dcdc_eta_nom = cfg.converter.dcdc.eta_nom;
            pars.dcdc_eff_load_points = cfg.converter.dcdc.load_points;
            pars.dcdc_eff_eta_points  = cfg.converter.dcdc.eta_points;

            pars.pcs_eta_nom = cfg.converter.pcsb.eta_nom;
            pars.pcs_eff_load_points = cfg.converter.pcsb.load_points;
            pars.pcs_eff_eta_points  = cfg.converter.pcsb.eta_points;

            pars.inv_eta = pars.central_inv_eta_nom;
            pars.eta_c = pars.dcdc_eta_nom;
            pars.eta_d = pars.dcdc_eta_nom;

            pars.degradation_cost_per_kWh = cfg.dispatch.degradation_cost_per_kWh;
            pars.bessCoupling = lower(string(coupling));
            pars.P_contract_safety_factor = cfg.dispatch.P_contract_safety_factor;
            pars.objectiveMode = lower(string(cfg.dispatch.objectiveMode));
            pars.energyOnlyGridCap_kW = cfg.dispatch.energyOnlyGridCap_kW;

        case "hybrid"

            requiredDesignFields = { ...
                'E_BESS_dc_kWh', ...
                'P_BESS_dc_kW', ...
                'E_BESS_ac_kWh', ...
                'P_BESS_ac_kW', ...
                'E_BESS_kWh', ...
                'P_BESS_kW', ...
                'P_inv_kW'};

            for i = 1:numel(requiredDesignFields)
                if ~isfield(design, requiredDesignFields{i})
                    error('Missing hybrid design field: design.%s', requiredDesignFields{i});
                end
            end

            if design.E_BESS_dc_kWh <= 0 || design.P_BESS_dc_kW <= 0 || ...
               design.E_BESS_ac_kWh <= 0 || design.P_BESS_ac_kW <= 0

                error('Hybrid MILP testbench requires nonzero AC and DC BESS sizes.');
            end

            pars = struct();

            pars.dc = base_battery_pars_nonideal_( ...
                design.E_BESS_dc_kWh, ...
                design.P_BESS_dc_kW);

            pars.ac = base_battery_pars_nonideal_( ...
                design.E_BESS_ac_kWh, ...
                design.P_BESS_ac_kW);

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

        otherwise

            error('Invalid coupling: %s', coupling);
    end
end


function contract_kW = local_default_contract_kW(dc, cfg, objectiveMode)

    objectiveMode = lower(string(objectiveMode));

    if objectiveMode == "energy_only"
        contract_kW = cfg.dispatch.energyOnlyGridCap_kW;
        return;
    end

    if isfield(cfg, 'dispatch') && isfield(cfg.dispatch, 'noBessContract_kW')
        contract_kW = cfg.dispatch.noBessContract_kW;
        return;
    end

    if isfield(cfg, 'dispatch') && isfield(cfg.dispatch, 'P_contract_safety_factor')
        safety = cfg.dispatch.P_contract_safety_factor;
    else
        safety = 0.90;
    end

    contract_kW = max(dc.P_grid_no_bess_day(:)) / max(safety, eps);
end


% =========================================================================
% VALIDATION
% =========================================================================
function validation = local_validate_plan(plan, dc, pars, coupling, contract_state, tol)

    coupling = lower(string(coupling));

    Pload = dc.P_load_48h(:);
    Ppvdc = dc.P_pv_48h(:);
    N = numel(Pload);

    validation = struct();
    validation.isFeasible = false;
    validation.messages = strings(0, 1);

    validation.exitflag = local_get_plan_field(plan, 'exitflag', NaN);
    validation.objectiveValue = local_get_plan_field(plan, 'objective_value', NaN);

    if ~isfield(plan, 'is_feasible') || ~plan.is_feasible
        validation.messages(end+1, 1) = "Planner returned infeasible plan.";
        return;
    end

    requiredPlanFields = { ...
        'P_grid_plan', ...
        'P_ch_plan', ...
        'P_dis_plan', ...
        'P_curt_plan', ...
        'SoC_plan'};

    for i = 1:numel(requiredPlanFields)

        if ~isfield(plan, requiredPlanFields{i})
            validation.messages(end+1, 1) = ...
                "Missing plan field: " + string(requiredPlanFields{i});
        end
    end

    if ~isempty(validation.messages)
        return;
    end

    if numel(plan.P_grid_plan) ~= N
        validation.messages(end+1, 1) = "Plan length does not match 48h forecast length.";
        return;
    end

    gridLimit = contract_state.P_contract_safety_factor * contract_state.P_contract_kW;

    if isfield(plan, 'P_grid_limit')
        gridLimit = plan.P_grid_limit;
    end

    validation.maxGridLimitViolation_kW = max(plan.P_grid_plan(:) - gridLimit);
    validation.maxSimultaneousChargeDischarge_kW = max(min( ...
        max(plan.P_ch_plan(:), 0), ...
        max(plan.P_dis_plan(:), 0)));

    validation.maxSocViolation = local_soc_violation(plan.SoC_plan(:), pars, coupling);

    switch coupling

        case "dc"

            requiredDcFields = { ...
                'P_gload_plan', ...
                'P_pvload_plan', ...
                'P_bload_plan', ...
                'P_pvbatt_plan', ...
                'P_spill_plan'};

            local_require_plan_fields(plan, requiredDcFields);

            validation.maxLoadBalanceResidual_kW = local_max_abs( ...
                plan.P_gload_plan(:) + ...
                plan.P_pvload_plan(:) + ...
                plan.P_bload_plan(:) - ...
                Pload(:));

            validation.maxPvBalanceResidual_kW = local_max_abs( ...
                plan.P_pvload_plan(:) ./ max(pars.inv_eta, eps) + ...
                plan.P_pvbatt_plan(:) + ...
                plan.P_spill_plan(:) - ...
                Ppvdc(:));

        case "ac"

            requiredAcFields = { ...
                'P_gload_plan', ...
                'P_pvload_plan', ...
                'P_bload_plan', ...
                'P_pvbatt_plan', ...
                'P_spill_plan', ...
                'P_pv_ac_plan'};

            local_require_plan_fields(plan, requiredAcFields);

            PpvAc = plan.P_pv_ac_plan(:);

            validation.maxLoadBalanceResidual_kW = local_max_abs( ...
                plan.P_gload_plan(:) + ...
                plan.P_pvload_plan(:) + ...
                plan.P_bload_plan(:) - ...
                Pload(:));

            validation.maxPvBalanceResidual_kW = local_max_abs( ...
                plan.P_pvload_plan(:) + ...
                plan.P_pvbatt_plan(:) + ...
                plan.P_spill_plan(:) - ...
                PpvAc(:));

        case "hybrid"

            requiredHybridFields = { ...
                'P_gload_plan', ...
                'P_gbatt_dc_plan', ...
                'P_gbatt_ac_plan', ...
                'P_pvload_plan', ...
                'P_pvbatt_dc_plan', ...
                'P_pvbatt_ac_plan', ...
                'P_bload_dc_plan', ...
                'P_bload_ac_plan', ...
                'P_spill_plan', ...
                'P_ch_dc_plan', ...
                'P_dis_dc_plan', ...
                'P_ch_ac_plan', ...
                'P_dis_ac_plan'};

            local_require_plan_fields(plan, requiredHybridFields);

            etaInv = max(pars.central_inv_eta_nom, eps);

            validation.maxLoadBalanceResidual_kW = local_max_abs( ...
                plan.P_gload_plan(:) + ...
                plan.P_pvload_plan(:) + ...
                plan.P_bload_dc_plan(:) + ...
                plan.P_bload_ac_plan(:) - ...
                Pload(:));

            validation.maxPvBalanceResidual_kW = local_max_abs( ...
                (plan.P_pvload_plan(:) + plan.P_pvbatt_ac_plan(:)) ./ etaInv + ...
                plan.P_pvbatt_dc_plan(:) + ...
                plan.P_spill_plan(:) - ...
                Ppvdc(:));

            validation.maxGridCompositionResidual_kW = local_max_abs( ...
                plan.P_grid_plan(:) - ...
                plan.P_gload_plan(:) - ...
                plan.P_gbatt_dc_plan(:) - ...
                plan.P_gbatt_ac_plan(:));

            validation.maxSimultaneousDcChargeDischarge_kW = max(min( ...
                max(plan.P_ch_dc_plan(:), 0), ...
                max(plan.P_dis_dc_plan(:), 0)));

            validation.maxSimultaneousAcChargeDischarge_kW = max(min( ...
                max(plan.P_ch_ac_plan(:), 0), ...
                max(plan.P_dis_ac_plan(:), 0)));
    end

    validation.passGridLimit = validation.maxGridLimitViolation_kW <= tol;
    validation.passSimultaneousChargeDischarge = ...
        validation.maxSimultaneousChargeDischarge_kW <= tol;
    validation.passSocBounds = validation.maxSocViolation <= tol;
    validation.passLoadBalance = validation.maxLoadBalanceResidual_kW <= tol;
    validation.passPvBalance = validation.maxPvBalanceResidual_kW <= tol;

    validation.isFeasible = ...
        validation.passGridLimit && ...
        validation.passSimultaneousChargeDischarge && ...
        validation.passSocBounds && ...
        validation.passLoadBalance && ...
        validation.passPvBalance;

    if validation.isFeasible
        validation.messages(end+1, 1) = "Validation passed.";
    else
        validation.messages(end+1, 1) = "Validation failed.";
    end
end


function local_require_plan_fields(plan, requiredFields)

    for i = 1:numel(requiredFields)

        if ~isfield(plan, requiredFields{i})
            error('Plan is missing required field: %s', requiredFields{i});
        end
    end
end


function v = local_soc_violation(SoC, pars, coupling)

    coupling = lower(string(coupling));

    switch coupling

        case "hybrid"
            socMin = min(pars.dc.SoC_min, pars.ac.SoC_min);
            socMax = max(pars.dc.SoC_max, pars.ac.SoC_max);

        otherwise
            socMin = pars.SoC_min;
            socMax = pars.SoC_max;
    end

    vLow = max(socMin - SoC(:));
    vHigh = max(SoC(:) - socMax);

    v = max([vLow, vHigh, 0]);
end


% =========================================================================
% COMPARISON
% =========================================================================
function comparison = local_compare_plans(planRef, planMod, runtimeRef_s, runtimeMod_s)

    comparison = struct();

    comparison.runtimeProductionMean_s = mean(runtimeRef_s);
    comparison.runtimeModifiedMean_s = mean(runtimeMod_s);

    comparison.runtimeSpeedupFactor = ...
        comparison.runtimeProductionMean_s ./ ...
        max(comparison.runtimeModifiedMean_s, eps);

    comparison.runtimeReduction_pct = ...
        100 * (comparison.runtimeProductionMean_s - comparison.runtimeModifiedMean_s) ./ ...
        max(comparison.runtimeProductionMean_s, eps);

    if isfield(planRef, 'objective_value') && isfield(planMod, 'objective_value')
        comparison.objectiveProduction = planRef.objective_value;
        comparison.objectiveModified = planMod.objective_value;
        comparison.objectiveDiff = planMod.objective_value - planRef.objective_value;
        comparison.objectiveRelDiff_pct = 100 * comparison.objectiveDiff ./ ...
            max(abs(planRef.objective_value), eps);
    end

    fieldsToCompare = { ...
        'P_grid_plan', ...
        'P_ch_plan', ...
        'P_dis_plan', ...
        'P_curt_plan', ...
        'SoC_plan', ...
        'P_gload_plan', ...
        'P_gbatt_plan', ...
        'P_pvload_plan', ...
        'P_pvbatt_plan', ...
        'P_bload_plan', ...
        'P_spill_plan', ...
        'P_ch_dc_plan', ...
        'P_dis_dc_plan', ...
        'P_ch_ac_plan', ...
        'P_dis_ac_plan'};

    for i = 1:numel(fieldsToCompare)

        fieldName = fieldsToCompare{i};

        if isfield(planRef, fieldName) && isfield(planMod, fieldName)

            a = planRef.(fieldName)(:);
            b = planMod.(fieldName)(:);

            if numel(a) == numel(b)

                comparison.("maxAbsDiff_" + fieldName) = max(abs(a - b));
                comparison.("meanAbsDiff_" + fieldName) = mean(abs(a - b));
                comparison.("sumDiff_" + fieldName) = sum(b - a);
            end
        end
    end
end


function T = local_build_summary_table(production, modified, comparison)

    planner = strings(0, 1);
    feasible = false(0, 1);
    runtimeMean_s = zeros(0, 1);
    runtimeMin_s = zeros(0, 1);
    runtimeMax_s = zeros(0, 1);
    objectiveValue = zeros(0, 1);
    maxGridViolation_kW = zeros(0, 1);
    maxSimultaneousChargeDischarge_kW = zeros(0, 1);
    maxLoadBalanceResidual_kW = zeros(0, 1);
    maxPvBalanceResidual_kW = zeros(0, 1);

    planner(end+1, 1) = "production";
    feasible(end+1, 1) = production.validation.isFeasible;
    runtimeMean_s(end+1, 1) = production.runtime_mean_s;
    runtimeMin_s(end+1, 1) = production.runtime_min_s;
    runtimeMax_s(end+1, 1) = production.runtime_max_s;
    objectiveValue(end+1, 1) = local_get_plan_field(production.plan, 'objective_value', NaN);
    maxGridViolation_kW(end+1, 1) = local_get_struct_field(production.validation, 'maxGridLimitViolation_kW', NaN);
    maxSimultaneousChargeDischarge_kW(end+1, 1) = local_get_struct_field(production.validation, 'maxSimultaneousChargeDischarge_kW', NaN);
    maxLoadBalanceResidual_kW(end+1, 1) = local_get_struct_field(production.validation, 'maxLoadBalanceResidual_kW', NaN);
    maxPvBalanceResidual_kW(end+1, 1) = local_get_struct_field(production.validation, 'maxPvBalanceResidual_kW', NaN);

    if isfield(modified, 'plan')

        planner(end+1, 1) = "modified";
        feasible(end+1, 1) = modified.validation.isFeasible;
        runtimeMean_s(end+1, 1) = modified.runtime_mean_s;
        runtimeMin_s(end+1, 1) = modified.runtime_min_s;
        runtimeMax_s(end+1, 1) = modified.runtime_max_s;
        objectiveValue(end+1, 1) = local_get_plan_field(modified.plan, 'objective_value', NaN);
        maxGridViolation_kW(end+1, 1) = local_get_struct_field(modified.validation, 'maxGridLimitViolation_kW', NaN);
        maxSimultaneousChargeDischarge_kW(end+1, 1) = local_get_struct_field(modified.validation, 'maxSimultaneousChargeDischarge_kW', NaN);
        maxLoadBalanceResidual_kW(end+1, 1) = local_get_struct_field(modified.validation, 'maxLoadBalanceResidual_kW', NaN);
        maxPvBalanceResidual_kW(end+1, 1) = local_get_struct_field(modified.validation, 'maxPvBalanceResidual_kW', NaN);
    end

    T = table( ...
        planner, ...
        feasible, ...
        runtimeMean_s, ...
        runtimeMin_s, ...
        runtimeMax_s, ...
        objectiveValue, ...
        maxGridViolation_kW, ...
        maxSimultaneousChargeDischarge_kW, ...
        maxLoadBalanceResidual_kW, ...
        maxPvBalanceResidual_kW);

    if isfield(comparison, 'runtimeSpeedupFactor')
        T.runtimeSpeedupComparedToProduction = NaN(height(T), 1);

        modIdx = T.planner == "modified";
        T.runtimeSpeedupComparedToProduction(modIdx) = comparison.runtimeSpeedupFactor;
    end
end


% =========================================================================
% PLOTS
% =========================================================================
function figures = local_make_comparison_plots(out)

    figures = struct();

    if ~isfield(out.modified, 'plan')
        return;
    end

    planRef = out.production.plan;
    planMod = out.modified.plan;

    figures.powerComparison = figure('Name', 'MILP planner power comparison');

    t = (1:numel(planRef.P_grid_plan)).';

    subplot(3, 1, 1);
    plot(t, planRef.P_grid_plan(:), '-o');
    hold on;
    plot(t, planMod.P_grid_plan(:), '-x');
    hold off;
    grid on;
    ylabel('Pgrid [kW]');
    title('Grid import plan');
    legend({'Production', 'Modified'}, 'Location', 'best');

    subplot(3, 1, 2);
    plot(t, planRef.P_ch_plan(:), '-o');
    hold on;
    plot(t, planMod.P_ch_plan(:), '-x');
    hold off;
    grid on;
    ylabel('Pcharge [kW]');
    title('BESS charge plan');
    legend({'Production', 'Modified'}, 'Location', 'best');

    subplot(3, 1, 3);
    plot(t, planRef.P_dis_plan(:), '-o');
    hold on;
    plot(t, planMod.P_dis_plan(:), '-x');
    hold off;
    grid on;
    ylabel('Pdischarge [kW]');
    xlabel('Time step');
    title('BESS discharge plan');
    legend({'Production', 'Modified'}, 'Location', 'best');

    figures.socComparison = figure('Name', 'MILP planner SoC comparison');

    plot(t, planRef.SoC_plan(:), '-o');
    hold on;
    plot(t, planMod.SoC_plan(:), '-x');
    hold off;
    grid on;
    ylabel('SoC [-]');
    xlabel('Time step');
    title('SoC plan');
    legend({'Production', 'Modified'}, 'Location', 'best');
end


% =========================================================================
% SAVE / PRINT
% =========================================================================
function savePath = local_save_test_result(out, cfg)

    testDir = fullfile(cfg.paths.results, 'milp_testbench');

    if ~exist(testDir, 'dir')
        mkdir(testDir);
    end

    stamp = datestr(now, 'yyyymmdd_HHMMSS');

    saveName = sprintf( ...
        'milp_test_%s_%s_c%d_d%d_%s.mat', ...
        char(out.testInfo.objectiveMode), ...
        char(out.testInfo.coupling), ...
        out.testInfo.candidateIndex, ...
        out.testInfo.dayIndex, ...
        stamp);

    savePath = fullfile(testDir, saveName);

    save(savePath, 'out', '-v7.3');
end


function local_print_test_summary(out)

    fprintf('\n====================================================\n');
    fprintf('MILP planner testbench result\n');
    fprintf('Mode       : %s\n', string(out.testInfo.objectiveMode));
    fprintf('Coupling   : %s\n', string(out.testInfo.coupling));
    fprintf('Candidate  : %d\n', out.testInfo.candidateIndex);
    fprintf('Day index  : %d\n', out.testInfo.dayIndex);
    fprintf('Abs day    : %d\n', out.testInfo.absDay);
    fprintf('----------------------------------------------------\n');
    fprintf('Production runtime mean: %.4f s\n', out.production.runtime_mean_s);
    fprintf('Production valid       : %d\n', out.production.validation.isFeasible);

    if isfield(out.modified, 'plan')
        fprintf('Modified runtime mean  : %.4f s\n', out.modified.runtime_mean_s);
        fprintf('Modified valid         : %d\n', out.modified.validation.isFeasible);
        fprintf('Speedup factor         : %.3f x\n', out.comparison.runtimeSpeedupFactor);
        fprintf('Runtime reduction      : %.2f %%\n', out.comparison.runtimeReduction_pct);

        if isfield(out.comparison, 'objectiveDiff')
            fprintf('Objective diff         : %.8f\n', out.comparison.objectiveDiff);
            fprintf('Objective rel. diff    : %.8f %%\n', out.comparison.objectiveRelDiff_pct);
        end

        if isfield(out.comparison, 'maxAbsDiff_P_grid_plan')
            fprintf('Max diff P_grid_plan   : %.8f kW\n', out.comparison.maxAbsDiff_P_grid_plan);
        end

        if isfield(out.comparison, 'maxAbsDiff_P_ch_plan')
            fprintf('Max diff P_ch_plan     : %.8f kW\n', out.comparison.maxAbsDiff_P_ch_plan);
        end

        if isfield(out.comparison, 'maxAbsDiff_P_dis_plan')
            fprintf('Max diff P_dis_plan    : %.8f kW\n', out.comparison.maxAbsDiff_P_dis_plan);
        end

        if isfield(out.comparison, 'maxAbsDiff_SoC_plan')
            fprintf('Max diff SoC_plan      : %.8f\n', out.comparison.maxAbsDiff_SoC_plan);
        end
    end

    if strlength(string(out.savePath)) > 0
        fprintf('Saved to: %s\n', out.savePath);
    end

    fprintf('====================================================\n');
end


% =========================================================================
% GENERAL HELPERS
% =========================================================================
function value = local_get_opt(opts, fieldName, defaultValue)

    if isfield(opts, fieldName) && ~isempty(opts.(fieldName))
        value = opts.(fieldName);
    else
        value = defaultValue;
    end
end


function value = local_get_plan_field(plan, fieldName, defaultValue)

    if isfield(plan, fieldName)
        value = plan.(fieldName);
    else
        value = defaultValue;
    end
end


function value = local_get_struct_field(S, fieldName, defaultValue)

    if isfield(S, fieldName)
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end


function y = local_max_abs(x)

    x = x(:);

    if isempty(x)
        y = NaN;
    else
        y = max(abs(x));
    end
end