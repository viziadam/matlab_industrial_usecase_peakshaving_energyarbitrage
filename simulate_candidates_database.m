function DB = simulate_candidates_database(data, DB, cfg, industrialCtx)
% SIMULATE_CANDIDATES_DATABASE
% Lefuttatja az osszes ipari PV+BESS candidate-et.

    if nargin < 4 || isempty(industrialCtx)
        industrialCtx = prepare_industrial_simulation_context(data, cfg);
    end

    nCandidates = DB.nCandidates;
    profilingEnabled = local_is_runtime_profiling_enabled(cfg);

    if profilingEnabled
        DB = local_init_runtime_profile_columns(DB);
    end

    diagnosticMode = false;

    if isfield(cfg, 'diagnostics')
        if isfield(cfg.diagnostics, 'enabled') && cfg.diagnostics.enabled
            diagnosticMode = true;
        elseif isfield(cfg.diagnostics, 'testMode') && cfg.diagnostics.testMode
            diagnosticMode = true;
        end
    end

    coupling = lower(string(cfg.system.bessCoupling));
    baselineIdx = [];

    if diagnosticMode

        if ~isfield(cfg.diagnostics, 'candidateIndex') || isempty(cfg.diagnostics.candidateIndex)
            error('cfg.diagnostics.enabled = true, but cfg.diagnostics.candidateIndex is missing.');
        end

        requestedCandidateList = cfg.diagnostics.candidateIndex(:).';

        if any(requestedCandidateList < 1) || any(requestedCandidateList > nCandidates)
            error('Invalid diagnostics candidateIndex.');
        end

        T = DB.candidateTable;

        if coupling == "hybrid"
            candidateList = unique(requestedCandidateList, 'stable');
            fprintf('\n====================================================\n');
            fprintf('DIAGNOSTIC MODE ACTIVE - HYBRID\n');
            fprintf('No no-BESS baseline is forced for hybrid candidates.\n');
            fprintf('Candidate list: ');
            disp(candidateList);
            fprintf('====================================================\n');
        else
            if ~ismember('BESS_PV_ratio', T.Properties.VariableNames)
                error('candidateTable does not contain BESS_PV_ratio.');
            end

            baselineIdx = find(abs(T.BESS_PV_ratio) < 1e-12);

            if isempty(baselineIdx)
                error('Diagnostic/evaluation run requires baseline candidate: BESS_PV_ratio = 0.');
            end

            if numel(baselineIdx) > 1
                error('Multiple baseline candidates found.');
            end

            candidateList = unique([baselineIdx, requestedCandidateList], 'stable');
            fprintf('\n====================================================\n');
            fprintf('DIAGNOSTIC MODE ACTIVE\n');
            fprintf('Baseline + selected candidate(s) will be simulated.\n');
            fprintf('Candidate list: ');
            disp(candidateList);
            fprintf('====================================================\n');
        end
    else
        candidateList = 1:nCandidates;
    end

    for cLoop = 1:numel(candidateList)

        c = candidateList(cLoop);
        candidateID = DB.candidateTable.candidateID(c);

        fprintf('\n====================================================\n');
        fprintf('Running candidate %d / %d: %s\n', c, nCandidates, candidateID);
        fprintf('Coupling: %s\n', string(cfg.system.bessCoupling));
        fprintf('====================================================\n');

        tCandidate = tic;
        runtimeProfile = local_empty_runtime_profile();

        try
            tStage = tic;
            design = table_row_to_design(DB.candidateTable(c, :));
            runtimeProfile.design_s = toc(tStage);

            cfgRun = cfg;

            if diagnosticMode
                cfgRun.diagnostics.storeCandidateDetail = true;
                cfgRun.diagnostics.storePlannerDebug = true;
            end

            tStage = tic;

            if lower(string(cfgRun.system.bessCoupling)) == "hybrid"
                [running, simSummary, detail] = simulate_industrial_candidate_horizon_hybrid( ...
                    industrialCtx, design, cfgRun);
            else
                [running, simSummary, detail] = simulate_industrial_candidate_horizon( ...
                    industrialCtx, design, cfgRun);
            end

            runtimeProfile.simulation_s = toc(tStage);
            runtimeProfile.contractSearch_s = local_get_numeric_field(simSummary, 'contractSearchRuntime_s', 0);
            runtimeProfile.fullHorizon_s = local_get_numeric_field(simSummary, 'fullHorizonRuntime_s', 0);
            runtimeProfile.simulationOverhead_s = max( ...
                runtimeProfile.simulation_s - runtimeProfile.contractSearch_s - runtimeProfile.fullHorizon_s, 0);

            runtimeProfile = local_copy_full_horizon_profile(runtimeProfile, simSummary);

            runtime_s = toc(tCandidate);
            running.summary.runtime_s = runtime_s;

            if isfield(running.summary, 'contractSearchRuntime_s')
                running.summary.contractSearchRuntime_s = simSummary.contractSearchRuntime_s;
            end

            if isfield(running.summary, 'fullHorizonRuntime_s')
                running.summary.fullHorizonRuntime_s = simSummary.fullHorizonRuntime_s;
            end

            tStage = tic;
            DB = finalize_candidate_result(DB, c, running, runtime_s, cfgRun);
            runtimeProfile.finalize_s = toc(tStage);

            tStageDiagnostics = tic;

            if diagnosticMode
                if ~isfield(DB, 'diagnostics') || isempty(DB.diagnostics)
                    DB.diagnostics = struct();
                end

                fieldName = sprintf('candidate_%d', c);
                DB.diagnostics.(fieldName) = struct();
                DB.diagnostics.(fieldName).design = design;
                DB.diagnostics.(fieldName).summary = simSummary;
                DB.diagnostics.(fieldName).detail = detail;

                if isfield(cfgRun.diagnostics, 'makeDispatchDiagnosticPlots') && cfgRun.diagnostics.makeDispatchDiagnosticPlots
                    local_plot_embedded_dispatch_diagnostics(cfgRun, c, design, simSummary, detail);
                    local_plot_canonical_energy_flow_diagnostics(cfgRun, c, simSummary);
                end
            end

            runtimeProfile.diagnostics_s = toc(tStageDiagnostics);

        catch ME
            runtime_s = toc(tCandidate);
            runtimeProfile.total_s = runtime_s;

            DB.candidateTable.wasSimulated(c) = false;
            DB.candidateTable.hasError(c) = true;
            DB.candidateTable.errorMessage(c) = string(ME.message);
            DB.candidateTable.runtime_s(c) = runtime_s;

            if profilingEnabled
                DB = local_store_runtime_profile(DB, c, runtimeProfile);
                local_print_candidate_runtime_profile(c, candidateID, runtimeProfile, true);
            end

            if isfield(cfg, 'sim') && isfield(cfg.sim, 'saveAfterEachCandidate') && cfg.sim.saveAfterEachCandidate
                save_candidates_database(DB, cfg);
            end

            fprintf('\nCandidate %d failed after %.2f s.\n', c, runtime_s);
            fprintf('Error message:\n%s\n', ME.message);
            rethrow(ME);
        end

        tStage = tic;

        if isfield(cfg, 'sim') && isfield(cfg.sim, 'saveAfterEachCandidate') && cfg.sim.saveAfterEachCandidate
            save_candidates_database(DB, cfg);
        end

        runtimeProfile.save_s = toc(tStage);
        runtimeProfile.total_s = toc(tCandidate);
        runtimeProfile.other_s = max( ...
            runtimeProfile.total_s - runtimeProfile.design_s - runtimeProfile.simulation_s - ...
            runtimeProfile.finalize_s - runtimeProfile.diagnostics_s - runtimeProfile.save_s, 0);

        DB.candidateTable.runtime_s(c) = runtimeProfile.total_s;

        if profilingEnabled
            DB = local_store_runtime_profile(DB, c, runtimeProfile);
            local_print_candidate_runtime_profile(c, candidateID, runtimeProfile, false);
        end
    end

    if diagnosticMode && isfield(cfg.diagnostics, 'runEvaluation') && cfg.diagnostics.runEvaluation

        if coupling == "hybrid"
            fprintf('\nHybrid diagnostic DB saved. Legacy diagnostic evaluation skipped for hybrid.\n');
        else
            evalCfgDiag = create_evaluation_config(cfg);
            evalCfgDiag.output.baseFolder = fullfile(cfg.diagnostics.outputFolder, 'evaluation');

            if ~exist(evalCfgDiag.output.baseFolder, 'dir')
                mkdir(evalCfgDiag.output.baseFolder);
            end

            evalCfgDiag.output.saveEvaluationMat = true;
            evalCfgDiag.output.saveEvaluationCsv = true;
            evalCfgDiag.output.saveReportTables = true;
            evalCfgDiag.plots.makePlots = true;
            evalCfgDiag.plots.makeCandidateSweepPlots = false;
            evalCfgDiag.plots.makeSelectedCandidateYearlyPlots = true;

            evaluationResult = evaluation(cfg, evalCfgDiag, DB); %#ok<NASGU>

            save(fullfile(evalCfgDiag.output.baseFolder, 'diagnostic_evaluation_result.mat'), ...
                'evaluationResult', '-v7.3');

            fprintf('\nDiagnostic evaluation saved:\n%s\n', fullfile(evalCfgDiag.output.baseFolder, 'diagnostic_evaluation_result.mat'));

            diagnosticCandidateList = cfg.diagnostics.candidateIndex(:).';

            for ii = 1:numel(diagnosticCandidateList)
                selectedCandidateIndex = diagnosticCandidateList(ii);

                if ~isempty(baselineIdx) && selectedCandidateIndex == baselineIdx
                    continue;
                end

                yearlyResult = evaluate_selected_candidate_yearly_budget(DB, cfg, evalCfgDiag, selectedCandidateIndex);
                yearlyOutDir = fullfile(cfg.diagnostics.outputFolder, sprintf('candidate_%06d', selectedCandidateIndex), 'yearly_budget');

                if ~exist(yearlyOutDir, 'dir')
                    mkdir(yearlyOutDir);
                end

                yearlyBudgetTable = yearlyResult.yearlyBudgetTable; %#ok<NASGU>
                writetable(yearlyBudgetTable, fullfile(yearlyOutDir, 'yearly_budget_table.csv'));
                save(fullfile(yearlyOutDir, 'yearly_budget_result.mat'), 'yearlyResult', '-v7.3');
            end
        end
    end

    if ~diagnosticMode && isfield(cfg, 'evaluation') && isfield(cfg.evaluation, 'runAfterSimulation') && cfg.evaluation.runAfterSimulation
        if coupling == "hybrid"
            fprintf('\nHybrid DB saved. Legacy evaluation skipped for hybrid.\n');
        else
            evalCfg = create_evaluation_config(cfg);
            evaluationResult = evaluation(cfg, evalCfg, DB); %#ok<NASGU>

            if isfield(cfg.evaluation, 'saveEvaluationResult') && cfg.evaluation.saveEvaluationResult
                save(fullfile(evalCfg.output.baseFolder, 'evaluation_result.mat'), 'evaluationResult', '-v7.3');
            end

            fprintf('\nFull evaluation saved:\n%s\n', fullfile(evalCfg.output.baseFolder, 'evaluation_result.mat'));
        end
    end
end


function local_plot_canonical_energy_flow_diagnostics(cfgRun, candidateIndex, simSummary)

    if ~isfield(simSummary, 'full_result') || isempty(simSummary.full_result)
        return;
    end

    fig = plot_canonical_energy_flow_diagnostics_4y(simSummary.full_result);

    if isempty(fig) || ~isgraphics(fig, 'figure')
        return;
    end

    outDir = fullfile( ...
        cfgRun.diagnostics.outputFolder, ...
        sprintf('candidate_%06d', candidateIndex), ...
        'dispatch_diagnostics');

    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    fileBase = fullfile(outDir, 'canonical_energy_flow_diagnostics');
    savefig(fig, [fileBase, '.fig']);

    try
        exportgraphics(fig, [fileBase, '.png'], 'Resolution', 150);
    catch
        if isgraphics(fig, 'figure')
            saveas(fig, [fileBase, '.png']);
        end
    end
end


function design = table_row_to_design(row)

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

    requiredFields = {'P_PV_kW', 'P_inv_kW', 'E_BESS_kWh', 'P_BESS_kW'};

    for k = 1:numel(requiredFields)
        f = requiredFields{k};
        if ~isfield(design, f)
            error('Design structure missing field: %s', f);
        end
    end
end


function enabled = local_is_runtime_profiling_enabled(cfg)

    enabled = false;

    if isfield(cfg, 'profiling') && isfield(cfg.profiling, 'enabled')
        enabled = logical(cfg.profiling.enabled);
    end
end


function profile = local_empty_runtime_profile()

    profile = struct();

    % Outer candidate-level stages
    profile.design_s = 0;
    profile.simulation_s = 0;
    profile.contractSearch_s = 0;
    profile.fullHorizon_s = 0;
    profile.simulationOverhead_s = 0;
    profile.finalize_s = 0;
    profile.diagnostics_s = 0;
    profile.save_s = 0;
    profile.other_s = 0;
    profile.total_s = 0;

    % Inner full-horizon stages
    profile.fh_init_s = 0;
    profile.fh_preallocation_s = 0;
    profile.fh_dataPrep_s = 0;
    profile.fh_milp_s = 0;
    profile.fh_planPostprocess_s = 0;
    profile.fh_realtimeControl_s = 0;
    profile.fh_topology_s = 0;
    profile.fh_aggregation_s = 0;
    profile.fh_diagnostics_s = 0;
    profile.fh_finalize_s = 0;
    profile.fh_dayLoopTotal_s = 0;
    profile.fh_other_s = 0;
    profile.fh_total_s = 0;
end


function DB = local_init_runtime_profile_columns(DB)

    names = { ...
    'runtimeDesign_s', ...
    'runtimeSimulation_s', ...
    'runtimeContractSearch_s', ...
    'runtimeFullHorizon_s', ...
    'runtimeSimulationOverhead_s', ...
    'runtimeFinalize_s', ...
    'runtimeDiagnostics_s', ...
    'runtimeSave_s', ...
    'runtimeOther_s', ...
    'runtimeProfileTotal_s', ...
    'runtimeFullHorizon_pct', ...
    'runtimeContractSearch_pct', ...
    'runtimeSave_pct', ...
    ...
    'runtimeFHInit_s', ...
    'runtimeFHPreallocation_s', ...
    'runtimeFHDataPrep_s', ...
    'runtimeFHMILP_s', ...
    'runtimeFHPlanPostprocess_s', ...
    'runtimeFHRealtimeControl_s', ...
    'runtimeFHTopology_s', ...
    'runtimeFHAggregation_s', ...
    'runtimeFHDiagnostics_s', ...
    'runtimeFHFinalize_s', ...
    'runtimeFHDayLoopTotal_s', ...
    'runtimeFHOther_s', ...
    'runtimeFHTotal_s', ...
    ...
    'runtimeFHMILP_pctOfCandidate', ...
    'runtimeFHTopology_pctOfCandidate', ...
    'runtimeFHAggregation_pctOfCandidate', ...
    'runtimeFHMILP_pctOfFullHorizon', ...
    'runtimeFHTopology_pctOfFullHorizon', ...
    'runtimeFHAggregation_pctOfFullHorizon'};

    for i = 1:numel(names)
        name = names{i};
        if ~ismember(name, DB.candidateTable.Properties.VariableNames)
            DB.candidateTable.(name) = NaN(height(DB.candidateTable), 1);
        end
    end
end


function DB = local_store_runtime_profile(DB, c, profile)

    if ~ismember('runtimeDesign_s', DB.candidateTable.Properties.VariableNames)
        DB = local_init_runtime_profile_columns(DB);
    end

    total_s = max(profile.total_s, eps);

    DB.candidateTable.runtimeDesign_s(c) = profile.design_s;
    DB.candidateTable.runtimeSimulation_s(c) = profile.simulation_s;
    DB.candidateTable.runtimeContractSearch_s(c) = profile.contractSearch_s;
    DB.candidateTable.runtimeFullHorizon_s(c) = profile.fullHorizon_s;
    DB.candidateTable.runtimeSimulationOverhead_s(c) = profile.simulationOverhead_s;
    DB.candidateTable.runtimeFinalize_s(c) = profile.finalize_s;
    DB.candidateTable.runtimeDiagnostics_s(c) = profile.diagnostics_s;
    DB.candidateTable.runtimeSave_s(c) = profile.save_s;
    DB.candidateTable.runtimeOther_s(c) = profile.other_s;
    DB.candidateTable.runtimeProfileTotal_s(c) = profile.total_s;
    DB.candidateTable.runtimeFullHorizon_pct(c) = 100 * profile.fullHorizon_s / total_s;
    DB.candidateTable.runtimeContractSearch_pct(c) = 100 * profile.contractSearch_s / total_s;
    DB.candidateTable.runtimeSave_pct(c) = 100 * profile.save_s / total_s;
    fhTotal_s = max(profile.fh_total_s, eps);

    DB.candidateTable.runtimeFHInit_s(c) = profile.fh_init_s;
    DB.candidateTable.runtimeFHPreallocation_s(c) = profile.fh_preallocation_s;
    DB.candidateTable.runtimeFHDataPrep_s(c) = profile.fh_dataPrep_s;
    DB.candidateTable.runtimeFHMILP_s(c) = profile.fh_milp_s;
    DB.candidateTable.runtimeFHPlanPostprocess_s(c) = profile.fh_planPostprocess_s;
    DB.candidateTable.runtimeFHRealtimeControl_s(c) = profile.fh_realtimeControl_s;
    DB.candidateTable.runtimeFHTopology_s(c) = profile.fh_topology_s;
    DB.candidateTable.runtimeFHAggregation_s(c) = profile.fh_aggregation_s;
    DB.candidateTable.runtimeFHDiagnostics_s(c) = profile.fh_diagnostics_s;
    DB.candidateTable.runtimeFHFinalize_s(c) = profile.fh_finalize_s;
    DB.candidateTable.runtimeFHDayLoopTotal_s(c) = profile.fh_dayLoopTotal_s;
    DB.candidateTable.runtimeFHOther_s(c) = profile.fh_other_s;
    DB.candidateTable.runtimeFHTotal_s(c) = profile.fh_total_s;

    DB.candidateTable.runtimeFHMILP_pctOfCandidate(c) = 100 * profile.fh_milp_s / total_s;
    DB.candidateTable.runtimeFHTopology_pctOfCandidate(c) = 100 * profile.fh_topology_s / total_s;
    DB.candidateTable.runtimeFHAggregation_pctOfCandidate(c) = 100 * profile.fh_aggregation_s / total_s;

    DB.candidateTable.runtimeFHMILP_pctOfFullHorizon(c) = 100 * profile.fh_milp_s / fhTotal_s;
    DB.candidateTable.runtimeFHTopology_pctOfFullHorizon(c) = 100 * profile.fh_topology_s / fhTotal_s;
    DB.candidateTable.runtimeFHAggregation_pctOfFullHorizon(c) = 100 * profile.fh_aggregation_s / fhTotal_s;
end


function local_print_candidate_runtime_profile(c, candidateID, profile, failed)

    total_s = max(profile.total_s, eps);

    if failed
        statusText = 'FAILED';
    else
        statusText = 'OK';
    end

    fprintf('\n--- Runtime profile | candidate %d | %s | %s ---\n', c, string(candidateID), statusText);
    fprintf('Total candidate runtime       : %10.3f s | %6.2f %%\n', profile.total_s, 100.0);
    fprintf('  Design conversion           : %10.3f s | %6.2f %%\n', profile.design_s, 100 * profile.design_s / total_s);
    fprintf('  Candidate simulation        : %10.3f s | %6.2f %%\n', profile.simulation_s, 100 * profile.simulation_s / total_s);
    fprintf('    Contract search           : %10.3f s | %6.2f %%\n', profile.contractSearch_s, 100 * profile.contractSearch_s / total_s);
    fprintf('    Full horizon simulation   : %10.3f s | %6.2f %%\n', profile.fullHorizon_s, 100 * profile.fullHorizon_s / total_s);

    fhTotal_s = max(profile.fh_total_s, eps);

    fprintf('      FH initialization       : %10.3f s | %6.2f %% of FH | %6.2f %% total\n', ...
        profile.fh_init_s, 100 * profile.fh_init_s / fhTotal_s, 100 * profile.fh_init_s / total_s);

    fprintf('      FH preallocation/state  : %10.3f s | %6.2f %% of FH | %6.2f %% total\n', ...
        profile.fh_preallocation_s, 100 * profile.fh_preallocation_s / fhTotal_s, 100 * profile.fh_preallocation_s / total_s);

    fprintf('      FH data preparation     : %10.3f s | %6.2f %% of FH | %6.2f %% total\n', ...
        profile.fh_dataPrep_s, 100 * profile.fh_dataPrep_s / fhTotal_s, 100 * profile.fh_dataPrep_s / total_s);

    fprintf('      FH MILP planner         : %10.3f s | %6.2f %% of FH | %6.2f %% total\n', ...
        profile.fh_milp_s, 100 * profile.fh_milp_s / fhTotal_s, 100 * profile.fh_milp_s / total_s);

    fprintf('      FH plan postprocess     : %10.3f s | %6.2f %% of FH | %6.2f %% total\n', ...
        profile.fh_planPostprocess_s, 100 * profile.fh_planPostprocess_s / fhTotal_s, 100 * profile.fh_planPostprocess_s / total_s);

    fprintf('      FH realtime control     : %10.3f s | %6.2f %% of FH | %6.2f %% total\n', ...
        profile.fh_realtimeControl_s, 100 * profile.fh_realtimeControl_s / fhTotal_s, 100 * profile.fh_realtimeControl_s / total_s);

    fprintf('      FH topology execution   : %10.3f s | %6.2f %% of FH | %6.2f %% total\n', ...
        profile.fh_topology_s, 100 * profile.fh_topology_s / fhTotal_s, 100 * profile.fh_topology_s / total_s);

    fprintf('      FH aggregation/metrics  : %10.3f s | %6.2f %% of FH | %6.2f %% total\n', ...
        profile.fh_aggregation_s, 100 * profile.fh_aggregation_s / fhTotal_s, 100 * profile.fh_aggregation_s / total_s);

    fprintf('      FH diagnostics/detail   : %10.3f s | %6.2f %% of FH | %6.2f %% total\n', ...
        profile.fh_diagnostics_s, 100 * profile.fh_diagnostics_s / fhTotal_s, 100 * profile.fh_diagnostics_s / total_s);

    fprintf('      FH finalize             : %10.3f s | %6.2f %% of FH | %6.2f %% total\n', ...
        profile.fh_finalize_s, 100 * profile.fh_finalize_s / fhTotal_s, 100 * profile.fh_finalize_s / total_s);

    fprintf('      FH other                : %10.3f s | %6.2f %% of FH | %6.2f %% total\n', ...
        profile.fh_other_s, 100 * profile.fh_other_s / fhTotal_s, 100 * profile.fh_other_s / total_s);

    fprintf('    Simulation overhead       : %10.3f s | %6.2f %%\n', profile.simulationOverhead_s, 100 * profile.simulationOverhead_s / total_s);
    fprintf('  Finalize result             : %10.3f s | %6.2f %%\n', profile.finalize_s, 100 * profile.finalize_s / total_s);
    fprintf('  Diagnostics                 : %10.3f s | %6.2f %%\n', profile.diagnostics_s, 100 * profile.diagnostics_s / total_s);
    fprintf('  Save database               : %10.3f s | %6.2f %%\n', profile.save_s, 100 * profile.save_s / total_s);
    fprintf('  Other loop overhead         : %10.3f s | %6.2f %%\n', profile.other_s, 100 * profile.other_s / total_s);
    fprintf('------------------------------------------------------\n');
end


function value = local_get_numeric_field(S, fieldName, defaultValue)

    if isfield(S, fieldName) && isnumeric(S.(fieldName)) && isscalar(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function profile = local_copy_full_horizon_profile(profile, simSummary)

    if ~isfield(simSummary, 'fullHorizonProfile') || isempty(simSummary.fullHorizonProfile)
        return;
    end

    fh = simSummary.fullHorizonProfile;

    profile.fh_init_s = local_get_numeric_field(fh, 'init_s', 0);
    profile.fh_preallocation_s = local_get_numeric_field(fh, 'preallocation_s', 0);
    profile.fh_dataPrep_s = local_get_numeric_field(fh, 'dataPrep_s', 0);
    profile.fh_milp_s = local_get_numeric_field(fh, 'milp_s', 0);
    profile.fh_planPostprocess_s = local_get_numeric_field(fh, 'planPostprocess_s', 0);
    profile.fh_realtimeControl_s = local_get_numeric_field(fh, 'realtimeControl_s', 0);
    profile.fh_topology_s = local_get_numeric_field(fh, 'topology_s', 0);
    profile.fh_aggregation_s = local_get_numeric_field(fh, 'aggregation_s', 0);
    profile.fh_diagnostics_s = local_get_numeric_field(fh, 'diagnostics_s', 0);
    profile.fh_finalize_s = local_get_numeric_field(fh, 'finalize_s', 0);
    profile.fh_dayLoopTotal_s = local_get_numeric_field(fh, 'dayLoopTotal_s', 0);
    profile.fh_total_s = local_get_numeric_field(fh, 'total_s', 0);
    profile.fh_other_s = local_get_numeric_field(fh, 'other_s', 0);

    if profile.fh_total_s <= 0
        profile.fh_total_s = profile.fullHorizon_s;
    end

    if profile.fh_other_s <= 0
        measuredFH_s = ...
            profile.fh_init_s + ...
            profile.fh_preallocation_s + ...
            profile.fh_dataPrep_s + ...
            profile.fh_milp_s + ...
            profile.fh_planPostprocess_s + ...
            profile.fh_realtimeControl_s + ...
            profile.fh_topology_s + ...
            profile.fh_aggregation_s + ...
            profile.fh_diagnostics_s + ...
            profile.fh_finalize_s;

        profile.fh_other_s = max(profile.fh_total_s - measuredFH_s, 0);
    end
end
