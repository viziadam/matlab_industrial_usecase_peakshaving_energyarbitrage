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
    opts = local_set_default(opts, 'makePlots', false);
    opts = local_set_default(opts, 'saveResult', true);
    opts = local_set_default(opts, 'validationTol_kW', 1e-5);
    opts = local_set_default(opts, 'lpSimultaneousPowerTolerance_kW', 1e-5);

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
                    coupling, dayData, pars, industrialCtx.tariff, ...
                    contract_state, maxSolverTime_s, opts.nRepeat);

                fast.validation = local_validate_plan( ...
                    fast.plan, dayData, pars, coupling, ...
                    contract_state, opts.validationTol_kW);

                comparison = local_compare_plans( ...
                    production.plan, fast.plan, ...
                    production.runtime_s, fast.runtime_s);

                rowCounter = rowCounter + 1;

                rows{rowCounter, 1} = local_build_summary_row( ...
                    objectiveMode, coupling, candidateIndex, dayIndex, ...
                    dayData.abs_day, production, fast, comparison, opts);

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
                    'comparison', comparison);

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
        out.figures = local_make_plots(summaryTable);
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


function result = local_run_fast_planner(coupling, dayData, pars, tariff, contract_state, maxSolverTime_s, nRepeat)

    runtime_s = zeros(nRepeat, 1);
    plan = [];

    for r = 1:nRepeat
        tRun = tic;

        switch lower(string(coupling))
            case "dc"
                plan = ems_day_ahead_planner_milp_contract_fast_dc_test( ...
                    dayData.P_load_48h, ...
                    dayData.P_pv_48h, ...
                    dayData.Prices_48h, ...
                    pars, ...
                    tariff, ...
                    dayData.dt_h, ...
                    contract_state, ...
                    maxSolverTime_s);

            case "ac"
                plan = ems_day_ahead_planner_milp_contract_fast_ac_test( ...
                    dayData.P_load_48h, ...
                    dayData.P_pv_48h, ...
                    dayData.Prices_48h, ...
                    pars, ...
                    tariff, ...
                    dayData.dt_h, ...
                    contract_state, ...
                    maxSolverTime_s);

            otherwise
                error('Unsupported coupling: %s', coupling);
        end

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
    production, fast, comparison, opts)

    fastSolver = "";

    if isfield(fast.plan, 'fastSolver')
        fastSolver = string(fast.plan.fastSolver);
    end

    fastLpAccepted = false;

    if isfield(fast.plan, 'fastLpAccepted')
        fastLpAccepted = fast.plan.fastLpAccepted;
    end

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

    T.nAppliedSteps = comparison.nAppliedSteps;

    % Full 48h trajectory differences
    T.maxAbsDiff_P_grid_plan = local_get_field(comparison, 'maxAbsDiff_P_grid_plan', NaN);
    T.maxAbsDiff_P_ch_plan = local_get_field(comparison, 'maxAbsDiff_P_ch_plan', NaN);
    T.maxAbsDiff_P_dis_plan = local_get_field(comparison, 'maxAbsDiff_P_dis_plan', NaN);
    T.maxAbsDiff_P_curt_plan = local_get_field(comparison, 'maxAbsDiff_P_curt_plan', NaN);
    T.maxAbsDiff_SoC_plan = local_get_field(comparison, 'maxAbsDiff_SoC_plan', NaN);

    % Applied first 24h trajectory differences
    T.maxAbsDiffApplied_P_grid_plan = local_get_field(comparison, 'maxAbsDiffApplied_P_grid_plan', NaN);
    T.maxAbsDiffApplied_P_ch_plan = local_get_field(comparison, 'maxAbsDiffApplied_P_ch_plan', NaN);
    T.maxAbsDiffApplied_P_dis_plan = local_get_field(comparison, 'maxAbsDiffApplied_P_dis_plan', NaN);
    T.maxAbsDiffApplied_P_curt_plan = local_get_field(comparison, 'maxAbsDiffApplied_P_curt_plan', NaN);
    T.maxAbsDiffApplied_SoC_plan = local_get_field(comparison, 'maxAbsDiffApplied_SoC_plan', NaN);

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

    T.fastSolver = fastSolver;
    T.fastLpAccepted = fastLpAccepted;

    % ---------------------------------------------------------------------
    % Acceptance logic split into separate meanings
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

    % Ez jelenti azt, hogy production helyett kozvetlenul beteheto lenne.
    T.isSafeDropInReplacement = ...
        T.isObjectiveEquivalent && ...
        T.isAppliedTrajectoryIdentical;

    % Ez jelenti azt, amit most latsz:
    % az objective ugyanaz, a megoldas valid, de mas optimalis trajektoriat valaszt.
    T.isAlternativeOptimalPlan = ...
        T.isObjectiveEquivalent && ...
        ~T.isAppliedTrajectoryIdentical;

    % Backward compatibility:
    % A regi "isAcceptable" legyen szigoru, vagyis csak drop-in replacement.
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