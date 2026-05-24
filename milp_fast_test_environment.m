function out = milp_fast_test_environment(cfgBase, objectiveMode, couplingList, candidateList, dayList, opts)
% MILP_FAST_TEST_ENVIRONMENT
%
% Production MILP es fast MILP osszehasonlitasa AC/DC topologiara.
%
% Ez a fuggveny:
%   - egyszer betolti a data/context-et,
%   - couplingonkent letrehozza a candidate DB-t,
%   - minden candidate/day esetre lefuttatja:
%       production MILP
%       fast MILP
%   - osszehasonlitja:
%       runtime
%       feasibility
%       objective
%       P_grid, P_ch, P_dis, SoC elteresek
%
% Nem modositja a production szimulaciot.
% Nem ment canonical candidate metric cache-t.

    if nargin < 1 || isempty(cfgBase)
        basePath = fileparts(mfilename('fullpath'));
        cfgBase = create_configurations(basePath);
    end

    if nargin < 2 || strlength(string(objectiveMode)) == 0
        objectiveMode = "energy_only";
    end

    if nargin < 3 || isempty(couplingList)
        couplingList = ["dc", "ac"];
    end

    if nargin < 4
        candidateList = [];
    end

    if nargin < 5 || isempty(dayList)
        dayList = 1:30;
    end

    if nargin < 6 || isempty(opts)
        opts = struct();
    end

    objectiveMode = lower(string(objectiveMode));
    couplingList = lower(string(couplingList));
    dayList = dayList(:).';

    opts = local_set_default(opts, 'nRepeat', 1);
    opts = local_set_default(opts, 'makePlots', true);
    opts = local_set_default(opts, 'saveResult', true);
    opts = local_set_default(opts, 'validationTol_kW', 1e-5);
    opts = local_set_default(opts, 'lpSimultaneousPowerTolerance_kW', 1e-5);

    opts = local_set_default(opts, 'runTopologyExecution', true);
    opts = local_set_default(opts, 'plotWorstN', 2);
    opts = local_set_default(opts, 'plotOnlyWorstCases', true);

    opts = local_set_default(opts, 'objectiveRelTol_pct', 1e-6);
    opts = local_set_default(opts, 'objectiveAbsTol_HUF', 1e-3);
    opts = local_set_default(opts, 'trajectoryPowerTol_kW', 1e-5);
    opts = local_set_default(opts, 'trajectorySocTol', 1e-7);

    cfgBase.dispatch.objectiveMode = objectiveMode;

    if isfield(cfgBase, 'paths') && isfield(cfgBase.paths, 'results')
        [~, lastFolder] = fileparts(cfgBase.paths.results);

        if ~strcmpi(lastFolder, char(objectiveMode))
            cfgBase.paths.results = fullfile(cfgBase.paths.results, char(objectiveMode));
        end
    end

    fprintf('\nPreparing common data/context once...\n');

    data = build_data(cfgBase);
    industrialCtx = prepare_industrial_simulation_context(data, cfgBase);

    nDaysAvailable = numel(industrialCtx.day_cache);

    if any(dayList < 1) || any(dayList > nDaysAvailable)
        error('dayList contains invalid values. Available range: 1...%d', nDaysAvailable);
    end

    rows = cell(0, 1);
    details = cell(0, 1);
    rowCounter = 0;

    for cc = 1:numel(couplingList)

        coupling = couplingList(cc);

        if ~(coupling == "dc" || coupling == "ac")
            error('Only "dc" and "ac" are supported in this test environment.');
        end

        cfg = cfgBase;
        cfg.system.bessCoupling = coupling;
        cfg.dispatch.objectiveMode = objectiveMode;

        DB = init_candidate_database_structures(data, cfg);

        if isempty(candidateList)
            candidateListLocal = local_select_default_candidate(DB);
        else
            candidateListLocal = candidateList(:).';
        end

        for ci = 1:numel(candidateListLocal)

            candidateIndex = candidateListLocal(ci);

            if candidateIndex < 1 || candidateIndex > DB.nCandidates
                error('Invalid candidateIndex=%d for coupling=%s. Available: 1...%d', ...
                    candidateIndex, coupling, DB.nCandidates);
            end

            design = local_table_row_to_design(DB.candidateTable(candidateIndex, :));
            pars = local_build_planner_pars_from_design(design, cfg, coupling);
            pars.lpSimultaneousPowerTolerance_kW = opts.lpSimultaneousPowerTolerance_kW;

            for di = 1:numel(dayList)

                dayIndex = dayList(di);
                dayData = industrialCtx.day_cache(dayIndex);

                fprintf('\n----------------------------------------------------\n');
                fprintf('Coupling: %s | Candidate: %d | Day: %d\n', ...
                    coupling, candidateIndex, dayIndex);
                fprintf('----------------------------------------------------\n');

                contract_state = local_build_contract_state(dayData, cfg, objectiveMode);
                dispatch_cfg = local_build_dispatch_cfg(cfg, coupling, objectiveMode);

                maxSolverTime_s = local_get_max_solver_time(cfg, opts);

                production = local_run_production_planner( ...
                    dayData, pars, industrialCtx.tariff, contract_state, ...
                    maxSolverTime_s, dispatch_cfg, opts.nRepeat);

                production.validation = local_validate_plan( ...
                    production.plan, dayData, pars, coupling, ...
                    contract_state, opts.validationTol_kW);

                fast = local_run_fast_planner( ...
                    coupling, objectiveMode, dayData, pars, industrialCtx.tariff, ...
                    contract_state, maxSolverTime_s, dispatch_cfg, opts.nRepeat);

                fast.validation = local_validate_plan( ...
                    fast.plan, dayData, pars, coupling, ...
                    contract_state, opts.validationTol_kW);

                comparison = local_compare_plans( ...
                    production.plan, fast.plan, ...
                    production.runtime_s, fast.runtime_s);
                topologyComparison = struct();

                if opts.runTopologyExecution

                    topoProduction = local_execute_plan_through_topology( ...
                        production.plan, ...
                        dayData, ...
                        pars, ...
                        industrialCtx.tariff, ...
                        coupling);

                    topoFast = local_execute_plan_through_topology( ...
                        fast.plan, ...
                        dayData, ...
                        pars, ...
                        industrialCtx.tariff, ...
                        coupling);

                    topologyComparison = local_compare_topology_execution( ...
                        topoProduction, ...
                        topoFast, ...
                        production.plan, ...
                        fast.plan);
                else
                    topoProduction = struct();
                    topoFast = struct();
                end

                rowCounter = rowCounter + 1;

                rows{rowCounter, 1} = local_build_summary_row( ...
                    objectiveMode, coupling, candidateIndex, dayIndex, ...
                    dayData.abs_day, production, fast, comparison, ...
                    topologyComparison, opts);

                details{rowCounter, 1} = struct( ...
                    'objectiveMode', objectiveMode, ...
                    'coupling', coupling, ...
                    'candidateIndex', candidateIndex, ...
                    'dayIndex', dayIndex, ...
                    'absDay', dayData.abs_day, ...
                    'design', design, ...
                    'contract_state', contract_state, ...
                    'production', production, ...
                    'fast', fast, ...
                    'comparison', comparison, ...
                    'topoProduction', topoProduction, ...
                    'topoFast', topoFast, ...
                    'topologyComparison', topologyComparison);

                local_print_case_result(rows{rowCounter, 1});
            end
        end
    end

    summaryTable = vertcat(rows{:});

    out = struct();
    out.objectiveMode = objectiveMode;
    out.couplingList = couplingList;
    out.candidateList = candidateList;
    out.dayList = dayList;
    out.summaryTable = summaryTable;
    out.details = details;
    out.statistics = local_build_statistics(summaryTable);

    if opts.makePlots
        out.figures = local_make_plots(summaryTable, details, opts);
    else
        out.figures = struct();
    end

    if opts.saveResult
        [matPath, csvPath] = local_save_result(out, cfgBase, objectiveMode);
        out.savePath = matPath;
        out.csvPath = csvPath;
    else
        out.savePath = "";
        out.csvPath = "";
    end

    local_print_final_summary(out);
end


% =========================================================================
% RUNNERS
% =========================================================================
function result = local_run_production_planner(dayData, pars, tariff, contract_state, maxSolverTime_s, dispatch_cfg, nRepeat)

    runtime_s = zeros(nRepeat, 1);
    plan = [];

    for r = 1:nRepeat
        tRun = tic;

        plan = call_day_ahead_planner_by_mode( ...
            dayData.P_load_48h, ...
            dayData.P_pv_48h, ...
            dayData.Prices_48h, ...
            pars, ...
            tariff, ...
            dayData.dt_h, ...
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
end


function result = local_run_fast_planner(coupling, objectiveMode, dayData, pars, tariff, contract_state, maxSolverTime_s, dispatch_cfg, nRepeat)

    runtime_s = zeros(nRepeat, 1);
    plan = [];

    for r = 1:nRepeat
        tRun = tic;

        plan = local_call_fast_planner_by_mode( ...
            coupling, ...
            objectiveMode, ...
            dayData.P_load_48h, ...
            dayData.P_pv_48h, ...
            dayData.Prices_48h, ...
            pars, ...
            tariff, ...
            dayData.dt_h, ...
            contract_state, ...
            maxSolverTime_s, ...
            dispatch_cfg);

        runtime_s(r) = toc(tRun);
    end

    result = struct();
    result.label = "fast";
    result.plan = plan;
    result.runtime_s = runtime_s;
    result.runtime_mean_s = mean(runtime_s);
    result.runtime_min_s = min(runtime_s);
    result.runtime_max_s = max(runtime_s);
end


function plan = local_call_fast_planner_by_mode( ...
    coupling, objectiveMode, P_load_48h, P_pv_48h, Prices_48h, pars, tariff, ...
    dt_h, contract_state, maxSolverTime_s, dispatch_cfg)

    coupling = lower(string(coupling));
    objectiveMode = lower(string(objectiveMode));

    switch coupling

        case "dc"

            switch objectiveMode

                case "peak_only"

                    Prices_peak = Prices_48h;
                    Prices_peak.buy_huf = zeros(size(Prices_48h.buy_huf));

                    tariff_peak = tariff;
                    tariff_peak.distribution_energy_rate_huf_per_kWh = 0.0;
                    tariff_peak.transmission_energy_rate_huf_per_kWh = 0.0;
                    tariff_peak.curtailment_penalty_huf_per_kWh = 0.0;
                    tariff_peak.noncheap_charge_penalty_huf_per_kWh = 0.0;
                    tariff_peak.within_contract_peak_weight_huf_per_kW_month = 0.0;

                    plan = ems_day_ahead_planner_milp_contract_fast_dc_test( ...
                        P_load_48h, P_pv_48h, Prices_peak, pars, tariff_peak, ...
                        dt_h, contract_state, maxSolverTime_s);

                    plan.objective_mode = "peak_only";
                    plan.coupling = "dc";

                case "energy_only"

                    contract_state_energy = contract_state;
                    contract_state_energy.P_contract_kW = dispatch_cfg.energyOnlyGridCap_kW;
                    contract_state_energy.P_grid_hard_cap_kW = dispatch_cfg.energyOnlyGridCap_kW;
                    contract_state_energy.P_contract_safety_factor = 1.0;
                    contract_state_energy.P_month_max_so_far_kW = 0;

                    tariff_energy = tariff;
                    tariff_energy.penalty_rate_huf_per_kW_year = 0.0;
                    tariff_energy.within_contract_peak_weight_huf_per_kW_month = 0.0;

                    plan = ems_day_ahead_planner_milp_contract_fast_dc_test( ...
                        P_load_48h, P_pv_48h, Prices_48h, pars, tariff_energy, ...
                        dt_h, contract_state_energy, maxSolverTime_s);

                    plan.objective_mode = "energy_only";
                    plan.coupling = "dc";

                case "combined"

                    plan = ems_day_ahead_planner_milp_contract_fast_dc_test( ...
                        P_load_48h, P_pv_48h, Prices_48h, pars, tariff, ...
                        dt_h, contract_state, maxSolverTime_s);

                    plan.objective_mode = "combined";
                    plan.coupling = "dc";

                otherwise
                    error('Unknown objectiveMode for fast DC planner: %s', objectiveMode);
            end

        case "ac"

            switch objectiveMode

                case "peak_only"

                    Prices_peak = Prices_48h;
                    Prices_peak.buy_huf = zeros(size(Prices_48h.buy_huf));

                    tariff_peak = tariff;
                    tariff_peak.distribution_energy_rate_huf_per_kWh = 0.0;
                    tariff_peak.transmission_energy_rate_huf_per_kWh = 0.0;
                    tariff_peak.curtailment_penalty_huf_per_kWh = 0.0;
                    tariff_peak.noncheap_charge_penalty_huf_per_kWh = 0.0;
                    tariff_peak.within_contract_peak_weight_huf_per_kW_month = 0.0;

                    pars_peak = pars;
                    pars_peak.force_hard_grid_cap = true;

                    plan = ems_day_ahead_planner_milp_contract_fast_ac_test( ...
                        P_load_48h, P_pv_48h, Prices_peak, pars_peak, tariff_peak, ...
                        dt_h, contract_state, maxSolverTime_s);

                    plan.objective_mode = "peak_only";
                    plan.coupling = "ac";

                case "energy_only"

                    contract_state_energy = contract_state;
                    contract_state_energy.P_contract_kW = dispatch_cfg.energyOnlyGridCap_kW;
                    contract_state_energy.P_grid_hard_cap_kW = dispatch_cfg.energyOnlyGridCap_kW;
                    contract_state_energy.P_contract_safety_factor = 1.0;
                    contract_state_energy.P_month_max_so_far_kW = 0;

                    tariff_energy = tariff;
                    tariff_energy.penalty_rate_huf_per_kW_year = 0.0;
                    tariff_energy.within_contract_peak_weight_huf_per_kW_month = 0.0;

                    pars_energy = pars;
                    pars_energy.force_hard_grid_cap = false;

                    plan = ems_day_ahead_planner_milp_contract_fast_ac_test( ...
                        P_load_48h, P_pv_48h, Prices_48h, pars_energy, tariff_energy, ...
                        dt_h, contract_state_energy, maxSolverTime_s);

                    plan.objective_mode = "energy_only";
                    plan.coupling = "ac";

                case "combined"

                    plan = ems_day_ahead_planner_milp_contract_fast_ac_test( ...
                        P_load_48h, P_pv_48h, Prices_48h, pars, tariff, ...
                        dt_h, contract_state, maxSolverTime_s);

                    plan.objective_mode = "combined";
                    plan.coupling = "ac";

                otherwise
                    error('Unknown objectiveMode for fast AC planner: %s', objectiveMode);
            end

        otherwise
            error('Unsupported coupling for fast planner: %s', coupling);
    end
end


% =========================================================================
% CFG / DESIGN HELPERS
% =========================================================================
function candidateIndex = local_select_default_candidate(DB)

    T = DB.candidateTable;

    if ismember('E_BESS_kWh', T.Properties.VariableNames) && ...
       ismember('P_BESS_kW', T.Properties.VariableNames)

        idx = find(T.E_BESS_kWh > 0 & T.P_BESS_kW > 0, 1, 'first');
    else
        idx = 1;
    end

    if isempty(idx)
        error('No nonzero BESS candidate found.');
    end

    candidateIndex = idx;
end


function pars = local_build_planner_pars_from_design(design, cfg, coupling)

    requiredFields = {'E_BESS_kWh', 'P_BESS_kW', 'P_inv_kW'};

    for i = 1:numel(requiredFields)
        if ~isfield(design, requiredFields{i})
            error('Missing design field: %s', requiredFields{i});
        end
    end

    if design.E_BESS_kWh <= 0 || design.P_BESS_kW <= 0
        error('This MILP test requires a nonzero BESS candidate.');
    end

    pars = base_battery_pars_nonideal_( ...
        design.E_BESS_kWh, ...
        design.P_BESS_kW);

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
    pars.bessCoupling = lower(string(coupling));
    pars.objectiveMode = lower(string(cfg.dispatch.objectiveMode));
    pars.energyOnlyGridCap_kW = cfg.dispatch.energyOnlyGridCap_kW;

    pars.SoC_initial = 0.5;
end


function contract_state = local_build_contract_state(dayData, cfg, objectiveMode)

    objectiveMode = lower(string(objectiveMode));

    if objectiveMode == "energy_only"
        Pcontract = cfg.dispatch.energyOnlyGridCap_kW;
        safety = 1.0;
        monthPeak = 0;
    else
        safety = cfg.dispatch.P_contract_safety_factor;

        if isfield(cfg.dispatch, 'noBessContract_kW')
            Pcontract = cfg.dispatch.noBessContract_kW;
        elseif isfield(dayData, 'P_grid_no_bess_day')
            Pcontract = max(dayData.P_grid_no_bess_day(:)) / max(safety, eps);
        else
            Pcontract = max(dayData.P_load_48h(:)) / max(safety, eps);
        end

        monthPeak = 0;
    end

    contract_state = struct();
    contract_state.P_contract_kW = Pcontract;
    contract_state.P_month_max_so_far_kW = monthPeak;
    contract_state.current_day_of_month = mod(dayData.abs_day - 1, 30) + 1;
    contract_state.P_grid_hard_cap_kW = Pcontract;
    contract_state.P_contract_safety_factor = safety;
end


function dispatch_cfg = local_build_dispatch_cfg(cfg, coupling, objectiveMode)

    dispatch_cfg = struct();
    dispatch_cfg.bessCoupling = lower(string(coupling));
    dispatch_cfg.objectiveMode = lower(string(objectiveMode));
    dispatch_cfg.energyOnlyGridCap_kW = cfg.dispatch.energyOnlyGridCap_kW;
end


function maxSolverTime_s = local_get_max_solver_time(cfg, opts)

    if isfield(opts, 'maxSolverTime_s') && ~isempty(opts.maxSolverTime_s)
        maxSolverTime_s = opts.maxSolverTime_s;
    elseif isfield(cfg.dispatch, 'maxSolverTime_s')
        maxSolverTime_s = cfg.dispatch.maxSolverTime_s;
    else
        maxSolverTime_s = cfg.targetStepMin;
    end
end


% =========================================================================
% VALIDATION
% =========================================================================
function validation = local_validate_plan(plan, dayData, pars, coupling, contract_state, tol)

    coupling = lower(string(coupling));

    validation = struct();
    validation.isFeasible = false;
    validation.messages = strings(0, 1);

    if ~isfield(plan, 'is_feasible') || ~plan.is_feasible
        validation.messages(end+1, 1) = "Plan is infeasible.";
        return;
    end

    requiredBase = {'P_grid_plan', 'P_ch_plan', 'P_dis_plan', 'P_curt_plan', 'SoC_plan'};

    for i = 1:numel(requiredBase)
        if ~isfield(plan, requiredBase{i})
            validation.messages(end+1, 1) = "Missing plan field: " + string(requiredBase{i});
        end
    end

    if ~isempty(validation.messages)
        return;
    end

    Pload = dayData.P_load_48h(:);
    Ppvdc = dayData.P_pv_48h(:);

    gridLimit = contract_state.P_contract_safety_factor * contract_state.P_contract_kW;

    if isfield(plan, 'P_grid_limit')
        gridLimit = plan.P_grid_limit;
    end

    validation.maxGridLimitViolation_kW = max(plan.P_grid_plan(:) - gridLimit);
    validation.maxSimultaneousChargeDischarge_kW = max(min( ...
        max(plan.P_ch_plan(:), 0), ...
        max(plan.P_dis_plan(:), 0)));

    validation.maxSocViolation = max([ ...
        max(pars.SoC_min - plan.SoC_plan(:)), ...
        max(plan.SoC_plan(:) - pars.SoC_max), ...
        0]);

    switch coupling
        case "dc"
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
            validation.maxLoadBalanceResidual_kW = local_max_abs( ...
                plan.P_gload_plan(:) + ...
                plan.P_pvload_plan(:) + ...
                plan.P_bload_plan(:) - ...
                Pload(:));

            validation.maxPvBalanceResidual_kW = local_max_abs( ...
                plan.P_pvload_plan(:) + ...
                plan.P_pvbatt_plan(:) + ...
                plan.P_spill_plan(:) - ...
                plan.P_pv_ac_plan(:));
    end

    validation.passGridLimit = validation.maxGridLimitViolation_kW <= tol;
    validation.passSimultaneous = validation.maxSimultaneousChargeDischarge_kW <= tol;
    validation.passSoc = validation.maxSocViolation <= tol;
    validation.passLoadBalance = validation.maxLoadBalanceResidual_kW <= tol;
    validation.passPvBalance = validation.maxPvBalanceResidual_kW <= tol;

    validation.isFeasible = ...
        validation.passGridLimit && ...
        validation.passSimultaneous && ...
        validation.passSoc && ...
        validation.passLoadBalance && ...
        validation.passPvBalance;
end


% =========================================================================
% COMPARISON / SUMMARY
% =========================================================================
function comparison = local_compare_plans(prodPlan, fastPlan, prodRuntime_s, fastRuntime_s)

    comparison = struct();

    comparison.productionRuntimeMean_s = mean(prodRuntime_s);
    comparison.fastRuntimeMean_s = mean(fastRuntime_s);

    comparison.runtimeSpeedupFactor = ...
        comparison.productionRuntimeMean_s / max(comparison.fastRuntimeMean_s, eps);

    comparison.runtimeReduction_pct = ...
        100 * (comparison.productionRuntimeMean_s - comparison.fastRuntimeMean_s) / ...
        max(comparison.productionRuntimeMean_s, eps);

    comparison.productionObjective = local_get_field(prodPlan, 'objective_value', NaN);
    comparison.fastObjective = local_get_field(fastPlan, 'objective_value', NaN);

    comparison.objectiveDiff = ...
        comparison.fastObjective - comparison.productionObjective;

    comparison.objectiveRelDiff_pct = ...
        100 * comparison.objectiveDiff / max(abs(comparison.productionObjective), eps);

    fields = { ...
        'P_grid_plan', ...
        'P_ch_plan', ...
        'P_dis_plan', ...
        'P_curt_plan', ...
        'SoC_plan'};

    if isfield(prodPlan, 'P_grid_plan')
        nFull = numel(prodPlan.P_grid_plan(:));
        nApplied = floor(nFull / 2);
    else
        nApplied = NaN;
    end

    comparison.nAppliedSteps = nApplied;

    for i = 1:numel(fields)

        f = fields{i};

        if isfield(prodPlan, f) && isfield(fastPlan, f)

            a = prodPlan.(f)(:);
            b = fastPlan.(f)(:);

            if numel(a) == numel(b)

                comparison.(['maxAbsDiff_', f]) = max(abs(a - b));
                comparison.(['meanAbsDiff_', f]) = mean(abs(a - b));
                comparison.(['sumDiff_', f]) = sum(b - a);

                if isfinite(nApplied) && nApplied >= 1 && numel(a) >= nApplied
                    comparison.(['maxAbsDiffApplied_', f]) = ...
                        max(abs(a(1:nApplied) - b(1:nApplied)));

                    comparison.(['meanAbsDiffApplied_', f]) = ...
                        mean(abs(a(1:nApplied) - b(1:nApplied)));

                    comparison.(['sumDiffApplied_', f]) = ...
                        sum(b(1:nApplied) - a(1:nApplied));
                else
                    comparison.(['maxAbsDiffApplied_', f]) = NaN;
                    comparison.(['meanAbsDiffApplied_', f]) = NaN;
                    comparison.(['sumDiffApplied_', f]) = NaN;
                end

            else

                comparison.(['maxAbsDiff_', f]) = NaN;
                comparison.(['meanAbsDiff_', f]) = NaN;
                comparison.(['sumDiff_', f]) = NaN;

                comparison.(['maxAbsDiffApplied_', f]) = NaN;
                comparison.(['meanAbsDiffApplied_', f]) = NaN;
                comparison.(['sumDiffApplied_', f]) = NaN;
            end
        end
    end
end


function T = local_build_summary_row( ...
    objectiveMode, coupling, candidateIndex, dayIndex, absDay, ...
    production, fast, comparison, topologyComparison, opts)

    fastSolver = "";

    if isfield(fast.plan, 'fastSolver')
        fastSolver = string(fast.plan.fastSolver);
    end

    fastLpAccepted = false;

    if isfield(fast.plan, 'fastLpAccepted')
        fastLpAccepted = fast.plan.fastLpAccepted;
    end

    % ---------------------------------------------------------------------
    % Topology comparison values are read first into scalar variables.
    % This avoids using non-existing table variables later.
    % ---------------------------------------------------------------------
    prodPlanVsTopoGridMaxAbsDiff_kW = ...
        local_get_field(topologyComparison, 'prodPlanVsTopoGridMaxAbsDiff_kW', NaN);

    fastPlanVsTopoGridMaxAbsDiff_kW = ...
        local_get_field(topologyComparison, 'fastPlanVsTopoGridMaxAbsDiff_kW', NaN);

    prodPlanVsTopoSoCMaxAbsDiff = ...
        local_get_field(topologyComparison, 'prodPlanVsTopoSoCMaxAbsDiff', NaN);

    fastPlanVsTopoSoCMaxAbsDiff = ...
        local_get_field(topologyComparison, 'fastPlanVsTopoSoCMaxAbsDiff', NaN);

    fastTopoVsProdGridMaxAbsDiff_kW = ...
        local_get_field(topologyComparison, 'fastTopoVsProdGridMaxAbsDiff_kW', NaN);

    fastTopoVsProdSoCMaxAbsDiff = ...
        local_get_field(topologyComparison, 'fastTopoVsProdSoCMaxAbsDiff', NaN);

    fastTopoVsProdBessReqMaxAbsDiff_kW = ...
        local_get_field(topologyComparison, 'fastTopoVsProdBessReqMaxAbsDiff_kW', NaN);

    % ---------------------------------------------------------------------
    % Base table
    % ---------------------------------------------------------------------
    T = table();

    T.objectiveMode = string(objectiveMode);
    T.coupling = string(coupling);
    T.candidateIndex = candidateIndex;
    T.dayIndex = dayIndex;
    T.absDay = absDay;

    T.productionValid = production.validation.isFeasible;
    T.fastValid = fast.validation.isFeasible;

    T.productionRuntimeMean_s = production.runtime_mean_s;
    T.fastRuntimeMean_s = fast.runtime_mean_s;
    T.runtimeSpeedupFactor = comparison.runtimeSpeedupFactor;
    T.runtimeReduction_pct = comparison.runtimeReduction_pct;

    T.productionObjective = comparison.productionObjective;
    T.fastObjective = comparison.fastObjective;
    T.objectiveDiff = comparison.objectiveDiff;
    T.objectiveRelDiff_pct = comparison.objectiveRelDiff_pct;

    T.nAppliedSteps = local_get_field(comparison, 'nAppliedSteps', NaN);

    % ---------------------------------------------------------------------
    % Full 48h plan differences
    % ---------------------------------------------------------------------
    T.maxAbsDiff_P_grid_plan = ...
        local_get_field(comparison, 'maxAbsDiff_P_grid_plan', NaN);

    T.maxAbsDiff_P_ch_plan = ...
        local_get_field(comparison, 'maxAbsDiff_P_ch_plan', NaN);

    T.maxAbsDiff_P_dis_plan = ...
        local_get_field(comparison, 'maxAbsDiff_P_dis_plan', NaN);

    T.maxAbsDiff_P_curt_plan = ...
        local_get_field(comparison, 'maxAbsDiff_P_curt_plan', NaN);

    T.maxAbsDiff_SoC_plan = ...
        local_get_field(comparison, 'maxAbsDiff_SoC_plan', NaN);

    % ---------------------------------------------------------------------
    % Applied 24h plan differences
    % ---------------------------------------------------------------------
    T.maxAbsDiffApplied_P_grid_plan = ...
        local_get_field(comparison, 'maxAbsDiffApplied_P_grid_plan', NaN);

    T.maxAbsDiffApplied_P_ch_plan = ...
        local_get_field(comparison, 'maxAbsDiffApplied_P_ch_plan', NaN);

    T.maxAbsDiffApplied_P_dis_plan = ...
        local_get_field(comparison, 'maxAbsDiffApplied_P_dis_plan', NaN);

    T.maxAbsDiffApplied_P_curt_plan = ...
        local_get_field(comparison, 'maxAbsDiffApplied_P_curt_plan', NaN);

    T.maxAbsDiffApplied_SoC_plan = ...
        local_get_field(comparison, 'maxAbsDiffApplied_SoC_plan', NaN);

    % ---------------------------------------------------------------------
    % Validation residuals
    % ---------------------------------------------------------------------
    T.productionMaxSimultaneous_kW = ...
        local_get_field(production.validation, 'maxSimultaneousChargeDischarge_kW', NaN);

    T.fastMaxSimultaneous_kW = ...
        local_get_field(fast.validation, 'maxSimultaneousChargeDischarge_kW', NaN);

    T.productionLoadBalanceResidual_kW = ...
        local_get_field(production.validation, 'maxLoadBalanceResidual_kW', NaN);

    T.fastLoadBalanceResidual_kW = ...
        local_get_field(fast.validation, 'maxLoadBalanceResidual_kW', NaN);

    T.productionPvBalanceResidual_kW = ...
        local_get_field(production.validation, 'maxPvBalanceResidual_kW', NaN);

    T.fastPvBalanceResidual_kW = ...
        local_get_field(fast.validation, 'maxPvBalanceResidual_kW', NaN);

    % ---------------------------------------------------------------------
    % Topology execution comparison
    % ---------------------------------------------------------------------
    T.prodPlanVsTopoGridMaxAbsDiff_kW = prodPlanVsTopoGridMaxAbsDiff_kW;
    T.fastPlanVsTopoGridMaxAbsDiff_kW = fastPlanVsTopoGridMaxAbsDiff_kW;

    T.prodPlanVsTopoSoCMaxAbsDiff = prodPlanVsTopoSoCMaxAbsDiff;
    T.fastPlanVsTopoSoCMaxAbsDiff = fastPlanVsTopoSoCMaxAbsDiff;

    T.fastTopoVsProdGridMaxAbsDiff_kW = fastTopoVsProdGridMaxAbsDiff_kW;
    T.fastTopoVsProdSoCMaxAbsDiff = fastTopoVsProdSoCMaxAbsDiff;
    T.fastTopoVsProdBessReqMaxAbsDiff_kW = fastTopoVsProdBessReqMaxAbsDiff_kW;

    % ---------------------------------------------------------------------
    % Solver information
    % ---------------------------------------------------------------------
    T.fastSolver = fastSolver;
    T.fastLpAccepted = fastLpAccepted;

    % ---------------------------------------------------------------------
    % Acceptance logic
    % ---------------------------------------------------------------------
    T.isFeasibleBoth = T.productionValid && T.fastValid;

    T.isObjectiveEquivalent = ...
        T.isFeasibleBoth && ...
        (abs(T.objectiveDiff) <= opts.objectiveAbsTol_HUF || ...
         abs(T.objectiveRelDiff_pct) <= opts.objectiveRelTol_pct);

    T.isFullTrajectoryIdentical = ...
        T.isObjectiveEquivalent && ...
        T.maxAbsDiff_P_grid_plan <= opts.trajectoryPowerTol_kW && ...
        T.maxAbsDiff_P_ch_plan <= opts.trajectoryPowerTol_kW && ...
        T.maxAbsDiff_P_dis_plan <= opts.trajectoryPowerTol_kW && ...
        T.maxAbsDiff_P_curt_plan <= opts.trajectoryPowerTol_kW && ...
        T.maxAbsDiff_SoC_plan <= opts.trajectorySocTol;

    T.isAppliedTrajectoryIdentical = ...
        T.isObjectiveEquivalent && ...
        T.maxAbsDiffApplied_P_grid_plan <= opts.trajectoryPowerTol_kW && ...
        T.maxAbsDiffApplied_P_ch_plan <= opts.trajectoryPowerTol_kW && ...
        T.maxAbsDiffApplied_P_dis_plan <= opts.trajectoryPowerTol_kW && ...
        T.maxAbsDiffApplied_P_curt_plan <= opts.trajectoryPowerTol_kW && ...
        T.maxAbsDiffApplied_SoC_plan <= opts.trajectorySocTol;

    T.isTopologyEquivalent = ...
        T.isObjectiveEquivalent && ...
        ~isnan(T.fastTopoVsProdGridMaxAbsDiff_kW) && ...
        ~isnan(T.fastTopoVsProdSoCMaxAbsDiff) && ...
        T.fastTopoVsProdGridMaxAbsDiff_kW <= opts.trajectoryPowerTol_kW && ...
        T.fastTopoVsProdSoCMaxAbsDiff <= opts.trajectorySocTol;

    T.isSafeDropInReplacement = ...
        T.isObjectiveEquivalent && ...
        T.isAppliedTrajectoryIdentical;

    T.isAlternativeOptimalPlan = ...
        T.isObjectiveEquivalent && ...
        ~T.isAppliedTrajectoryIdentical;

    % Backward compatible strict acceptance:
    % true only if the fast plan can directly replace the production plan.
    T.isAcceptable = T.isSafeDropInReplacement;
end


function stats = local_build_statistics(T)

    stats = struct();

    stats.nRows = height(T);

    stats.nFeasibleBoth = sum(T.isFeasibleBoth);
    stats.nObjectiveEquivalent = sum(T.isObjectiveEquivalent);

    stats.nFullTrajectoryIdentical = sum(T.isFullTrajectoryIdentical);
    stats.nAppliedTrajectoryIdentical = sum(T.isAppliedTrajectoryIdentical);

    stats.nSafeDropInReplacement = sum(T.isSafeDropInReplacement);
    stats.nAlternativeOptimalPlan = sum(T.isAlternativeOptimalPlan);

    stats.nAcceptable = sum(T.isAcceptable);

    stats.nFastLpAccepted = sum(T.fastLpAccepted);
    stats.nFallback = sum(T.fastSolver == "milp_fallback_current_production");

    stats.meanSpeedup = mean(T.runtimeSpeedupFactor, 'omitnan');
    stats.meanSpeedupDc = mean(T.runtimeSpeedupFactor(T.coupling == "dc"), 'omitnan');
    stats.meanSpeedupAc = mean(T.runtimeSpeedupFactor(T.coupling == "ac"), 'omitnan');

    stats.maxObjectiveRelDiff_pct = max(abs(T.objectiveRelDiff_pct), [], 'omitnan');

    stats.maxGridDiff_kW = max(T.maxAbsDiff_P_grid_plan, [], 'omitnan');
    stats.maxChargeDiff_kW = max(T.maxAbsDiff_P_ch_plan, [], 'omitnan');
    stats.maxDischargeDiff_kW = max(T.maxAbsDiff_P_dis_plan, [], 'omitnan');
    stats.maxSoCDiff = max(T.maxAbsDiff_SoC_plan, [], 'omitnan');

    stats.maxAppliedGridDiff_kW = max(T.maxAbsDiffApplied_P_grid_plan, [], 'omitnan');
    stats.maxAppliedChargeDiff_kW = max(T.maxAbsDiffApplied_P_ch_plan, [], 'omitnan');
    stats.maxAppliedDischargeDiff_kW = max(T.maxAbsDiffApplied_P_dis_plan, [], 'omitnan');
    stats.maxAppliedSoCDiff = max(T.maxAbsDiffApplied_SoC_plan, [], 'omitnan');
    if ismember('isTopologyEquivalent', T.Properties.VariableNames)
        stats.nTopologyEquivalent = sum(T.isTopologyEquivalent);
    end

    if ismember('fastTopoVsProdGridMaxAbsDiff_kW', T.Properties.VariableNames)
        stats.maxTopologyGridDiff_kW = max(T.fastTopoVsProdGridMaxAbsDiff_kW, [], 'omitnan');
        stats.maxTopologyBessReqDiff_kW = max(T.fastTopoVsProdBessReqMaxAbsDiff_kW, [], 'omitnan');
        stats.maxTopologySoCDiff = max(T.fastTopoVsProdSoCMaxAbsDiff, [], 'omitnan');
    end
end

function [matPath, csvPath] = local_save_result(out, cfg, objectiveMode)

    resultDir = fullfile(cfg.paths.results, 'milp_fast_test');

    if ~exist(resultDir, 'dir')
        mkdir(resultDir);
    end

    stamp = datestr(now, 'yyyymmdd_HHMMSS');

    matPath = fullfile(resultDir, sprintf('milp_fast_test_%s_%s.mat', char(objectiveMode), stamp));
    csvPath = fullfile(resultDir, sprintf('milp_fast_test_%s_%s.csv', char(objectiveMode), stamp));

    save(matPath, 'out', '-v7.3');
    writetable(out.summaryTable, csvPath);
end


function local_print_case_result(T)

    fprintf('Production valid: %d | Fast valid: %d\n', ...
        T.productionValid, T.fastValid);

    fprintf('Objective equivalent: %d | Drop-in replacement: %d | Alternative optimum: %d\n', ...
        T.isObjectiveEquivalent, ...
        T.isSafeDropInReplacement, ...
        T.isAlternativeOptimalPlan);

    fprintf('Runtime production: %.4f s | fast: %.4f s | speedup: %.3f x\n', ...
        T.productionRuntimeMean_s, T.fastRuntimeMean_s, T.runtimeSpeedupFactor);

    fprintf('Objective rel diff: %.8f %% | Solver: %s\n', ...
        T.objectiveRelDiff_pct, T.fastSolver);

    fprintf('Applied 24h max diffs: Pgrid %.6f kW | Pch %.6f kW | Pdis %.6f kW | SoC %.8f\n', ...
        T.maxAbsDiffApplied_P_grid_plan, ...
        T.maxAbsDiffApplied_P_ch_plan, ...
        T.maxAbsDiffApplied_P_dis_plan, ...
        T.maxAbsDiffApplied_SoC_plan);
end


function local_print_final_summary(out)

    s = out.statistics;

    fprintf('\n====================================================\n');
    fprintf('Fast MILP AC/DC test finished\n');
    fprintf('Rows                         : %d\n', s.nRows);
    fprintf('Feasible both                : %d / %d\n', s.nFeasibleBoth, s.nRows);
    fprintf('Objective equivalent          : %d / %d\n', s.nObjectiveEquivalent, s.nRows);
    fprintf('Applied trajectory identical  : %d / %d\n', s.nAppliedTrajectoryIdentical, s.nRows);
    fprintf('Full trajectory identical     : %d / %d\n', s.nFullTrajectoryIdentical, s.nRows);
    fprintf('Safe drop-in replacement      : %d / %d\n', s.nSafeDropInReplacement, s.nRows);
    fprintf('Alternative optimal plan      : %d / %d\n', s.nAlternativeOptimalPlan, s.nRows);
    fprintf('LP accepted rows              : %d / %d\n', s.nFastLpAccepted, s.nRows);
    fprintf('Fallback rows                 : %d / %d\n', s.nFallback, s.nRows);
    fprintf('----------------------------------------------------\n');
    fprintf('Mean speedup                  : %.3f x\n', s.meanSpeedup);
    fprintf('Mean speedup DC               : %.3f x\n', s.meanSpeedupDc);
    fprintf('Mean speedup AC               : %.3f x\n', s.meanSpeedupAc);
    fprintf('Max obj diff                  : %.8f %%\n', s.maxObjectiveRelDiff_pct);
    fprintf('----------------------------------------------------\n');
    fprintf('Max full Pgrid diff           : %.8f kW\n', s.maxGridDiff_kW);
    fprintf('Max full Pcharge diff         : %.8f kW\n', s.maxChargeDiff_kW);
    fprintf('Max full Pdis diff            : %.8f kW\n', s.maxDischargeDiff_kW);
    fprintf('Max full SoC diff             : %.10f\n', s.maxSoCDiff);
    fprintf('----------------------------------------------------\n');
    fprintf('Max applied Pgrid diff        : %.8f kW\n', s.maxAppliedGridDiff_kW);
    fprintf('Max applied Pcharge diff      : %.8f kW\n', s.maxAppliedChargeDiff_kW);
    fprintf('Max applied Pdis diff         : %.8f kW\n', s.maxAppliedDischargeDiff_kW);
    fprintf('Max applied SoC diff          : %.10f\n', s.maxAppliedSoCDiff);

    if isfield(out, 'savePath') && strlength(string(out.savePath)) > 0
        fprintf('Saved MAT: %s\n', out.savePath);
        fprintf('Saved CSV: %s\n', out.csvPath);
    end

    if isfield(s, 'nTopologyEquivalent')
        fprintf('Topology equivalent          : %d / %d\n', ...
            s.nTopologyEquivalent, s.nRows);
    end

    if isfield(s, 'maxTopologyGridDiff_kW')
        fprintf('Max topology Pgrid diff      : %.8f kW\n', s.maxTopologyGridDiff_kW);
        fprintf('Max topology BESS req diff   : %.8f kW\n', s.maxTopologyBessReqDiff_kW);
        fprintf('Max topology SoC diff        : %.10f\n', s.maxTopologySoCDiff);
    end

    fprintf('====================================================\n');
end


% =========================================================================
% SMALL HELPERS
% =========================================================================
function opts = local_set_default(opts, fieldName, defaultValue)

    if ~isfield(opts, fieldName) || isempty(opts.(fieldName))
        opts.(fieldName) = defaultValue;
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


function value = local_get_field(S, fieldName, defaultValue)

    if isstruct(S) && isfield(S, fieldName)
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function design = local_table_row_to_design(row)
% LOCAL_TABLE_ROW_TO_DESIGN
%
% Candidate table egy sorabol egyszeru design struct-ot keszit.
% Azert kell itt kulon, mert a production table_row_to_design jelenleg
% lokalis fuggveny a simulate_candidates_database.m fajlban, ezert innen
% nem lathato.

    design = struct();
    varNames = row.Properties.VariableNames;

    for k = 1:numel(varNames)

        name = varNames{k};
        value = row.(name);

        if istable(value)
            continue;
        end

        if iscell(value)
            value = value{1};
        elseif isstring(value)
            value = value(1);
        elseif isnumeric(value) || islogical(value)
            value = value(1);
        end

        design.(name) = value;
    end

    requiredFields = { ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'E_BESS_kWh', ...
        'P_BESS_kW'};

    for k = 1:numel(requiredFields)

        fieldName = requiredFields{k};

        if ~isfield(design, fieldName)
            error('Design structure missing field: %s', fieldName);
        end
    end
end

function topo = local_execute_plan_through_topology(planFull, dayData, pars, tariff, coupling)

    coupling = lower(string(coupling));

    nDay = numel(dayData.P_load_actual);

    planToday = planFull;

    vectorFields = { ...
        'trade_buy_mask', ...
        'trade_sell_mask', ...
        'P_ch_plan', ...
        'P_dis_plan', ...
        'P_grid_plan', ...
        'P_curt_plan', ...
        'SoC_plan'};

    for i = 1:numel(vectorFields)
        f = vectorFields{i};

        if isfield(planFull, f)
            v = planFull.(f);
            planToday.(f) = v(1:nDay);
        end
    end

    init_params = struct( ...
        'target_energy_kWh', pars.E_cap_nom, ...
        'max_power_W', pars.P_rated * 1000, ...
        'initial_soc', local_get_field(pars, 'SoC_initial', 0.5));

    [~, state_bess] = bess_pack_model( ...
        0, ...
        'init', ...
        init_params, ...
        dayData.dt_h, ...
        []);

    switch coupling

        case "dc"

            P_bess_req_kW = ems_realtime_decision_dc( ...
                dayData.P_pv_dc_actual, ...
                dayData.P_load_actual, ...
                planToday, ...
                pars);

            [dayRes, state_bess] = topology_dc_coupled( ...
                P_bess_req_kW, ...
                dayData.P_pv_dc_actual, ...
                dayData.P_load_actual, ...
                dayData.Prices_today, ...
                pars, ...
                state_bess, ...
                dayData.dt_h);

        case "ac"

            P_bess_req_kW = ems_realtime_decision_ac( ...
                dayData.P_pv_dc_actual, ...
                dayData.P_load_actual, ...
                planToday, ...
                pars);

            [dayRes, state_bess] = topology_ac_coupled( ...
                P_bess_req_kW, ...
                dayData.P_pv_dc_actual, ...
                dayData.P_load_actual, ...
                dayData.Prices_today, ...
                pars, ...
                state_bess, ...
                dayData.dt_h);

        otherwise
            error('Unsupported coupling in topology execution: %s', coupling);
    end

    topo = struct();

    topo.planToday = planToday;
    topo.dayRes = dayRes;
    topo.state_bess = state_bess;
    topo.P_bess_req_kW = P_bess_req_kW(:);

    topo.P_grid_actual_kW = dayRes.E_grid_import(:) ./ dayData.dt_h;
    topo.SoC_actual = dayRes.SoC(:);

    topo.P_load_actual_kW = dayData.P_load_actual(:);
    topo.P_pv_dc_actual_kW = dayData.P_pv_dc_actual(:);

    topo.P_curtailment_actual_kW = local_optional_vector( ...
        dayRes, ...
        'P_curtailment_kW', ...
        nDay);

    topo.P_bess_to_load_actual_kW = local_optional_vector( ...
        dayRes, ...
        'P_bess_to_load_kW', ...
        nDay);

    topo.P_pv_to_load_actual_kW = local_optional_vector( ...
        dayRes, ...
        'P_pv_to_load_kW', ...
        nDay);

    topo.P_grid_to_load_actual_kW = local_optional_vector( ...
        dayRes, ...
        'P_grid_to_load_kW', ...
        nDay);

    topo.P_grid_to_bess_actual_kW = local_optional_vector( ...
        dayRes, ...
        'P_grid_to_bess_kW', ...
        nDay);

    topo.P_pv_to_bess_actual_kW = local_optional_vector( ...
        dayRes, ...
        'P_pv_to_bess_kW', ...
        nDay);
end


function cmp = local_compare_topology_execution(topoProd, topoFast, planProd, planFast)

    cmp = struct();

    if isempty(fieldnames(topoProd)) || isempty(fieldnames(topoFast))
        return;
    end

    nDay = numel(topoProd.P_grid_actual_kW);

    prodGridPlan = planProd.P_grid_plan(1:nDay);
    fastGridPlan = planFast.P_grid_plan(1:nDay);

    prodSocPlan = planProd.SoC_plan(1:nDay);
    fastSocPlan = planFast.SoC_plan(1:nDay);

    cmp.prodPlanVsTopoGridMaxAbsDiff_kW = ...
        max(abs(prodGridPlan(:) - topoProd.P_grid_actual_kW(:)));

    cmp.fastPlanVsTopoGridMaxAbsDiff_kW = ...
        max(abs(fastGridPlan(:) - topoFast.P_grid_actual_kW(:)));

    cmp.prodPlanVsTopoSoCMaxAbsDiff = ...
        max(abs(prodSocPlan(:) - topoProd.SoC_actual(:)));

    cmp.fastPlanVsTopoSoCMaxAbsDiff = ...
        max(abs(fastSocPlan(:) - topoFast.SoC_actual(:)));

    cmp.fastTopoVsProdGridMaxAbsDiff_kW = ...
        max(abs(topoFast.P_grid_actual_kW(:) - topoProd.P_grid_actual_kW(:)));

    cmp.fastTopoVsProdSoCMaxAbsDiff = ...
        max(abs(topoFast.SoC_actual(:) - topoProd.SoC_actual(:)));

    cmp.fastTopoVsProdBessReqMaxAbsDiff_kW = ...
        max(abs(topoFast.P_bess_req_kW(:) - topoProd.P_bess_req_kW(:)));
end


function v = local_optional_vector(S, fieldName, n)

    if isstruct(S) && isfield(S, fieldName)
        v = S.(fieldName);
        v = v(:);

        if numel(v) ~= n
            v = NaN(n, 1);
        end
    else
        v = NaN(n, 1);
    end
end

function figures = local_make_plots(T, details, opts)

    figures = struct();

    nRows = height(T);

    if nRows == 0
        warning('No rows available for plotting.');
        return;
    end

    x = 1:nRows;
    xLabels = local_build_case_labels(T);

    % =====================================================================
    % 1) Summary plot: speedup, objective, applied trajectory differences
    % =====================================================================
    figures.summarySpeedup = figure('Name', 'Fast MILP summary comparison');

    tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    bar(x, T.runtimeSpeedupFactor);
    grid on;
    ylabel('Speedup [-]');
    title('Runtime speedup: production MILP vs fast LP/MILP');
    xticks(x);
    xticklabels(xLabels);
    xtickangle(90);

    nexttile;
    bar(x, T.objectiveRelDiff_pct);
    grid on;
    ylabel('Obj. diff [%]');
    title('Objective relative difference');
    xticks(x);
    xticklabels(xLabels);
    xtickangle(90);

    nexttile;
    hold on;
    plot(x, T.maxAbsDiffApplied_P_grid_plan, '-o', 'LineWidth', 1.1);
    plot(x, T.maxAbsDiffApplied_P_ch_plan, '-s', 'LineWidth', 1.1);
    plot(x, T.maxAbsDiffApplied_P_dis_plan, '-d', 'LineWidth', 1.1);
    hold off;
    grid on;
    ylabel('Power diff [kW]');
    title('Applied 24h plan differences');
    legend({'Pgrid', 'Pcharge', 'Pdischarge'}, 'Location', 'best');
    xticks(x);
    xticklabels(xLabels);
    xtickangle(90);

    nexttile;
    bar(x, T.maxAbsDiffApplied_SoC_plan);
    grid on;
    ylabel('SoC diff [-]');
    title('Applied 24h SoC plan difference');
    xticks(x);
    xticklabels(xLabels);
    xtickangle(90);

    % =====================================================================
    % 2) Topology execution difference plot
    % =====================================================================
    hasTopologyColumns = ...
        ismember('fastTopoVsProdGridMaxAbsDiff_kW', T.Properties.VariableNames) && ...
        ismember('fastTopoVsProdBessReqMaxAbsDiff_kW', T.Properties.VariableNames) && ...
        ismember('fastTopoVsProdSoCMaxAbsDiff', T.Properties.VariableNames);

    if hasTopologyColumns

        figures.summaryTopology = figure('Name', 'Topology execution difference');

        tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

        nexttile;
        bar(x, T.fastTopoVsProdGridMaxAbsDiff_kW);
        grid on;
        ylabel('Grid diff [kW]');
        title('Topology execution: fast vs production grid import');
        xticks(x);
        xticklabels(xLabels);
        xtickangle(90);

        nexttile;
        bar(x, T.fastTopoVsProdBessReqMaxAbsDiff_kW);
        grid on;
        ylabel('BESS cmd diff [kW]');
        title('Realtime BESS command difference');
        xticks(x);
        xticklabels(xLabels);
        xtickangle(90);

        nexttile;
        bar(x, T.fastTopoVsProdSoCMaxAbsDiff);
        grid on;
        ylabel('SoC diff [-]');
        title('Topology execution: fast vs production SoC');
        xticks(x);
        xticklabels(xLabels);
        xtickangle(90);
    end

    % =====================================================================
    % 3) Acceptance classification plot
    % =====================================================================
    figures.acceptance = figure('Name', 'Fast MILP acceptance classification');

    tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile;
    bar(x, double(T.isObjectiveEquivalent));
    grid on;
    ylim([0 1.2]);
    ylabel('0/1');
    title('Objective equivalent');
    xticks(x);
    xticklabels(xLabels);
    xtickangle(90);

    nexttile;
    bar(x, double(T.isSafeDropInReplacement));
    grid on;
    ylim([0 1.2]);
    ylabel('0/1');
    title('Safe drop-in replacement');
    xticks(x);
    xticklabels(xLabels);
    xtickangle(90);

    nexttile;
    bar(x, double(T.isAlternativeOptimalPlan));
    grid on;
    ylim([0 1.2]);
    ylabel('0/1');
    title('Alternative optimal plan');
    xticks(x);
    xticklabels(xLabels);
    xtickangle(90);

    % =====================================================================
    % 4) Worst-case detailed plots
    % =====================================================================
    if opts.plotWorstN > 0 && ~isempty(details)

        score = zeros(nRows, 1);

        score = score + local_get_table_column(T, 'maxAbsDiffApplied_P_grid_plan', nRows);
        score = score + local_get_table_column(T, 'maxAbsDiffApplied_P_ch_plan', nRows);
        score = score + local_get_table_column(T, 'maxAbsDiffApplied_P_dis_plan', nRows);
        score = score + 1000 .* local_get_table_column(T, 'maxAbsDiffApplied_SoC_plan', nRows);

        if hasTopologyColumns
            score = score + local_get_table_column(T, 'fastTopoVsProdGridMaxAbsDiff_kW', nRows);
            score = score + local_get_table_column(T, 'fastTopoVsProdBessReqMaxAbsDiff_kW', nRows);
            score = score + 1000 .* local_get_table_column(T, 'fastTopoVsProdSoCMaxAbsDiff', nRows);
        end

        score(~isfinite(score)) = -inf;

        [~, order] = sort(score, 'descend');

        validOrder = order(score(order) > -inf);
        nPlot = min(opts.plotWorstN, numel(validOrder));

        for k = 1:nPlot
            idx = validOrder(k);

            if idx <= numel(details) && ~isempty(details{idx})
                fieldName = sprintf('worstCase_%d', k);
                figures.(fieldName) = local_plot_one_case_detail(details{idx});
            end
        end
    end
end

function fig = local_plot_one_case_detail(D)

    prod = D.production.plan;
    fast = D.fast.plan;

    topoProd = D.topoProduction;
    topoFast = D.topoFast;

    nDay = numel(topoProd.P_grid_actual_kW);
    t = (1:nDay).';

    figName = sprintf( ...
        '%s %s candidate %d day %d detailed comparison', ...
        string(D.objectiveMode), ...
        string(D.coupling), ...
        D.candidateIndex, ...
        D.dayIndex);

    fig = figure('Name', figName);

    % ---------------------------------------------------------------------
    % 1) Load, PV
    % ---------------------------------------------------------------------
    subplot(5, 1, 1);
    plot(t, topoProd.P_load_actual_kW(:), 'LineWidth', 1.1);
    hold on;
    plot(t, topoProd.P_pv_dc_actual_kW(:), 'LineWidth', 1.1);
    hold off;
    grid on;
    ylabel('kW');
    title(sprintf('%s / %s / cand %d / day %d: load and PV', ...
        string(D.objectiveMode), string(D.coupling), D.candidateIndex, D.dayIndex));
    legend({'Load actual', 'PV DC actual'}, 'Location', 'best');

    % ---------------------------------------------------------------------
    % 2) Grid terv es topologiai vegrehajtas
    % ---------------------------------------------------------------------
    subplot(5, 1, 2);
    plot(t, prod.P_grid_plan(1:nDay), '-', 'LineWidth', 1.1);
    hold on;
    plot(t, fast.P_grid_plan(1:nDay), '--', 'LineWidth', 1.1);
    plot(t, topoProd.P_grid_actual_kW(:), ':', 'LineWidth', 1.4);
    plot(t, topoFast.P_grid_actual_kW(:), '-.', 'LineWidth', 1.1);
    hold off;
    grid on;
    ylabel('Pgrid [kW]');
    title('Grid import: plan vs topology execution');
    legend({'Production plan', 'Fast plan', 'Production topology', 'Fast topology'}, ...
        'Location', 'best');

    % ---------------------------------------------------------------------
    % 3) BESS charge/discharge terv
    % ---------------------------------------------------------------------
    subplot(5, 1, 3);
    plot(t, prod.P_ch_plan(1:nDay), '-', 'LineWidth', 1.1);
    hold on;
    plot(t, fast.P_ch_plan(1:nDay), '--', 'LineWidth', 1.1);
    plot(t, prod.P_dis_plan(1:nDay), ':', 'LineWidth', 1.4);
    plot(t, fast.P_dis_plan(1:nDay), '-.', 'LineWidth', 1.1);
    hold off;
    grid on;
    ylabel('BESS plan [kW]');
    title('BESS charge/discharge plan');
    legend({'Production charge', 'Fast charge', 'Production discharge', 'Fast discharge'}, ...
        'Location', 'best');

    % ---------------------------------------------------------------------
    % 4) Realtime BESS parancs
    % ---------------------------------------------------------------------
    subplot(5, 1, 4);
    plot(t, topoProd.P_bess_req_kW(:), '-', 'LineWidth', 1.1);
    hold on;
    plot(t, topoFast.P_bess_req_kW(:), '--', 'LineWidth', 1.1);
    yline(0, ':');
    hold off;
    grid on;
    ylabel('P_{BESS,req} [kW]');
    title('Realtime BESS command from plan');
    legend({'Production command', 'Fast command'}, 'Location', 'best');

    % ---------------------------------------------------------------------
    % 5) SoC terv es topologiai SoC
    % ---------------------------------------------------------------------
    subplot(5, 1, 5);
    plot(t, prod.SoC_plan(1:nDay), '-', 'LineWidth', 1.1);
    hold on;
    plot(t, fast.SoC_plan(1:nDay), '--', 'LineWidth', 1.1);
    plot(t, topoProd.SoC_actual(:), ':', 'LineWidth', 1.4);
    plot(t, topoFast.SoC_actual(:), '-.', 'LineWidth', 1.1);
    hold off;
    grid on;
    ylabel('SoC [-]');
    xlabel('15-min step');
    title('SoC: plan vs topology execution');
    legend({'Production plan', 'Fast plan', 'Production topology', 'Fast topology'}, ...
        'Location', 'best');
end

function labels = local_build_case_labels(T)

    nRows = height(T);
    labels = strings(nRows, 1);

    for i = 1:nRows

        modeStr = "mode";

        if ismember('objectiveMode', T.Properties.VariableNames)
            modeStr = string(T.objectiveMode(i));
        end

        couplingStr = "x";

        if ismember('coupling', T.Properties.VariableNames)
            couplingStr = string(T.coupling(i));
        end

        cStr = "c?";

        if ismember('candidateIndex', T.Properties.VariableNames)
            cStr = "c" + string(T.candidateIndex(i));
        end

        dStr = "d?";

        if ismember('dayIndex', T.Properties.VariableNames)
            dStr = "d" + string(T.dayIndex(i));
        end

        labels(i) = modeStr + "_" + couplingStr + "_" + cStr + "_" + dStr;
    end
end


function v = local_get_table_column(T, columnName, nRows)

    if ismember(columnName, T.Properties.VariableNames)
        v = T.(columnName);
        v = v(:);

        if numel(v) ~= nRows
            v = NaN(nRows, 1);
        end
    else
        v = NaN(nRows, 1);
    end
end