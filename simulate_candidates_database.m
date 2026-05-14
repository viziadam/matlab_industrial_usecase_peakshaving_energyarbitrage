function DB = simulate_candidates_database(data, DB, cfg, industrialCtx)
% SIMULATE_CANDIDATES_DATABASE
%
% Lefuttatja az összes ipari PV+BESS candidate-et.
%
% Fontos:
%   - A candidate loop megmarad.
%   - A metrikák cfg.output alapján kerülnek mentésre.
%   - A DC/AC topológia cfg.system.bessCoupling alapján választódik ki.
%   - DC esetben kész a peak shaving + arbitrázs + contract optimalizálás.
%   - AC esetben ugyanaz az interfész megvan, de a planner/topology placeholder.

    if nargin < 4 || isempty(industrialCtx)
        industrialCtx = prepare_industrial_simulation_context(data, cfg);
    end

    nCandidates = DB.nCandidates;

    % =====================================================================
% Diagnostic mode
% =====================================================================
    diagnosticMode = false;

    if isfield(cfg, 'diagnostics')
        if isfield(cfg.diagnostics, 'enabled') && cfg.diagnostics.enabled
            diagnosticMode = true;
        elseif isfield(cfg.diagnostics, 'testMode') && cfg.diagnostics.testMode
            diagnosticMode = true;
        end
    end

    if diagnosticMode

        if ~isfield(cfg.diagnostics, 'candidateIndex') || ...
        isempty(cfg.diagnostics.candidateIndex)

            error('cfg.diagnostics.enabled = true, de cfg.diagnostics.candidateIndex nincs megadva.');
        end

        requestedCandidateList = cfg.diagnostics.candidateIndex(:).';

        if any(requestedCandidateList < 1) || any(requestedCandidateList > nCandidates)
            error('Érvénytelen diagnostics candidateIndex.');
        end

        T = DB.candidateTable;

        if ~ismember('BESS_PV_ratio', T.Properties.VariableNames)
            error('A candidateTable nem tartalmaz BESS_PV_ratio oszlopot.');
        end

        baselineIdx = find(abs(T.BESS_PV_ratio) < 1e-12);

        if isempty(baselineIdx)
            error('Diagnosztikai/evaluation futáshoz kell baseline candidate: BESS_PV_ratio = 0.');
        end

        if numel(baselineIdx) > 1
            error('Több baseline candidate található. Ez nem egyértelmű.');
        end

        candidateList = unique([baselineIdx, requestedCandidateList], 'stable');

        fprintf('\n====================================================\n');
        fprintf('DIAGNOSTIC MODE ACTIVE\n');
        fprintf('Baseline + selected candidate(s) will be simulated.\n');
        fprintf('Candidate list: ');
        disp(candidateList);
        fprintf('====================================================\n');

    else
        candidateList = 1:nCandidates;
    end

    % =====================================================================
    % Candidate loop
    % =====================================================================
    for cLoop = 1:numel(candidateList)

        c = candidateList(cLoop);
        candidateID = DB.candidateTable.candidateID(c);

        fprintf('\n====================================================\n');
        fprintf('Running candidate %d / %d: %s\n', c, nCandidates, candidateID);
        fprintf('Coupling: %s\n', string(cfg.system.bessCoupling));
        fprintf('====================================================\n');

        tCandidate = tic;

        try
            % -------------------------------------------------------------
            % Candidate design
            % -------------------------------------------------------------
            design = table_row_to_design(DB.candidateTable(c, :));

            % -------------------------------------------------------------
            % Horizon-level candidate simulation
            % -------------------------------------------------------------
            cfgRun = cfg;

            if diagnosticMode
                cfgRun.diagnostics.storeCandidateDetail = true;
                cfgRun.diagnostics.storePlannerDebug = true;
            end
            [running, simSummary, detail] = simulate_industrial_candidate_horizon( ...
                industrialCtx, ...
                design, ...
                cfgRun);

            runtime_s = toc(tCandidate);

            % -------------------------------------------------------------
            % Runtime summary
            % -------------------------------------------------------------
            running.summary.runtime_s = runtime_s;

            if isfield(running.summary, 'contractSearchRuntime_s')
                running.summary.contractSearchRuntime_s = simSummary.contractSearchRuntime_s;
            end

            if isfield(running.summary, 'fullHorizonRuntime_s')
                running.summary.fullHorizonRuntime_s = simSummary.fullHorizonRuntime_s;
            end

            % -------------------------------------------------------------
            % Candidate result finalization
            % -------------------------------------------------------------
            DB = finalize_candidate_result( ...
                DB, ...
                c, ...
                running, ...
                runtime_s, ...
                cfgRun);

            % -------------------------------------------------------------
            % Detailed diagnostics
            % -------------------------------------------------------------
            if diagnosticMode

                if ~isfield(DB, 'diagnostics') || isempty(DB.diagnostics)
                    DB.diagnostics = struct();
                end

                fieldName = sprintf('candidate_%d', c);

                DB.diagnostics.(fieldName) = struct();
                DB.diagnostics.(fieldName).design = design;
                DB.diagnostics.(fieldName).summary = simSummary;
                DB.diagnostics.(fieldName).detail = detail;
            end

        catch ME

            runtime_s = toc(tCandidate);

            DB.candidateTable.wasSimulated(c) = false;
            DB.candidateTable.hasError(c) = true;
            DB.candidateTable.errorMessage(c) = string(ME.message);
            DB.candidateTable.runtime_s(c) = runtime_s;

            if isfield(cfg, 'sim') && ...
               isfield(cfg.sim, 'saveAfterEachCandidate') && ...
               cfg.sim.saveAfterEachCandidate

                save_candidates_database(DB, cfg);
            end

            fprintf('\nCandidate %d failed after %.2f s.\n', c, runtime_s);
            fprintf('Error message:\n%s\n', ME.message);

            rethrow(ME);
        end

        

        % -----------------------------------------------------------------
        % Partial save
        % -----------------------------------------------------------------
        if isfield(cfg, 'sim') && ...
           isfield(cfg.sim, 'saveAfterEachCandidate') && ...
           cfg.sim.saveAfterEachCandidate

            save_candidates_database(DB, cfg);
        end
    end

    if diagnosticMode && isfield(cfg.diagnostics, 'runEvaluation') && cfg.diagnostics.runEvaluation

            evalCfgDiag = create_evaluation_config(cfg);

            evalCfgDiag.output.baseFolder = fullfile( ...
                cfg.diagnostics.outputFolder, ...
                'evaluation');

            if ~exist(evalCfgDiag.output.baseFolder, 'dir')
                mkdir(evalCfgDiag.output.baseFolder);
            end

            evalCfgDiag.output.saveEvaluationMat = true;
            evalCfgDiag.output.saveEvaluationCsv = true;
            evalCfgDiag.output.saveReportTables = true;

            evalCfgDiag.plots.makePlots = true;

            % Diagnosztikai módban nem kérünk teljes sweep-görbéket,
            % mert csak baseline + selected candidate van.
            evalCfgDiag.plots.makeCandidateSweepPlots = false;

            % Helyette részletes éves költségvetést rajzolunk a kiválasztott candidate-re.
            evalCfgDiag.plots.makeSelectedCandidateYearlyPlots = true;

            evaluationResult = evaluation(cfg, evalCfgDiag, DB); %#ok<NASGU>

            save(fullfile(evalCfgDiag.output.baseFolder, 'diagnostic_evaluation_result.mat'), ...
                'evaluationResult', ...
                '-v7.3');

            fprintf('\nDiagnostic evaluation saved:\n%s\n', ...
                fullfile(evalCfgDiag.output.baseFolder, 'diagnostic_evaluation_result.mat'));

            % -----------------------------------------------------------------
            % Részletes éves költségvetés a kiválasztott diagnosztikai candidate-re
            % -----------------------------------------------------------------
            diagnosticCandidateList = cfg.diagnostics.candidateIndex(:).';

            for ii = 1:numel(diagnosticCandidateList)

                selectedCandidateIndex = diagnosticCandidateList(ii);

                if selectedCandidateIndex == baselineIdx
                    continue;
                end

                yearlyResult = evaluate_selected_candidate_yearly_budget( ...
                    DB, ...
                    cfg, ...
                    evalCfgDiag, ...
                    selectedCandidateIndex);

                yearlyOutDir = fullfile( ...
                    cfg.diagnostics.outputFolder, ...
                    sprintf('candidate_%06d', selectedCandidateIndex), ...
                    'yearly_budget');

                if ~exist(yearlyOutDir, 'dir')
                    mkdir(yearlyOutDir);
                end

                yearlyBudgetTable = yearlyResult.yearlyBudgetTable; %#ok<NASGU>
                writetable(yearlyBudgetTable, fullfile(yearlyOutDir, 'yearly_budget_table.csv'));

                save(fullfile(yearlyOutDir, 'yearly_budget_result.mat'), ...
                    'yearlyResult', ...
                    '-v7.3');
            end
     end
end


% =========================================================================
% DESIGN STRUCTURE FROM TABLE ROW
% =========================================================================
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
            error('A design struktúra hiányzó mezője: %s', f);
        end
    end
end