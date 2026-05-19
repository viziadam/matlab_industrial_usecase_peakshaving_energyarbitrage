function runResult = run_all_topologies_for_mode(objectiveMode, diagnosticCandidateIndex)
% RUN_ALL_TOPOLOGIES_FOR_MODE
%
% Egy kivalasztott mukodesi modra lefuttatja mindket topologiat:
%   - DC
%   - AC
%
% objectiveMode:
%   "peak_only"
%   "energy_only"
%   "combined"
%
% Diagnosztikai futtatas:
%   run_all_topologies_for_mode("combined", [2 5 9])
%
% Teljes futtatas:
%   run_all_topologies_for_mode("combined", [])

    if nargin < 1 || strlength(string(objectiveMode)) == 0
        objectiveMode = "combined";
    end

    if nargin < 2
        diagnosticCandidateIndex = [];
    end

    objectiveMode = lower(string(objectiveMode));

    allowedModes = ["peak_only", "energy_only", "combined"];

    if ~any(objectiveMode == allowedModes)
        error('Invalid objectiveMode: %s', objectiveMode);
    end

    basePath = fileparts(mfilename('fullpath'));

    cfgBase = create_configurations(basePath);
    cfgBase.dispatch.objectiveMode = objectiveMode;

    if objectiveMode == "energy_only"
        cfgBase = add_energy_only_evaluation_metrics_to_cfg(cfgBase);
    end

    data = build_data(cfgBase);

    % ---------------------------------------------------------------------
    % Ipari pelda bemutato abra
    % ---------------------------------------------------------------------
    industrialCtxForOverview = prepare_industrial_simulation_context(data, cfgBase);
    overviewResult = plot_industrial_case_overview(cfgBase, industrialCtxForOverview); %#ok<NASGU>

    couplings = ["dc", "ac"];

    runResult = struct();
    runResult.objectiveMode = objectiveMode;
    runResult.startedAt = datetime('now');

    diagnosticMode = ~isempty(diagnosticCandidateIndex);

    for i = 1:numel(couplings)

        coupling = couplings(i);

        cfg = cfgBase;
        cfg.system.bessCoupling = coupling;
        cfg.dispatch.objectiveMode = objectiveMode;

        if objectiveMode == "energy_only"
            cfg = add_energy_only_evaluation_metrics_to_cfg(cfg);
        end

        cfg.paths.results = fullfile(cfgBase.paths.results, char(objectiveMode));
        cfg.paths.figures = fullfile(cfg.paths.results, 'figures');

        if ~exist(cfg.paths.results, 'dir')
            mkdir(cfg.paths.results);
        end

        if ~exist(cfg.paths.figures, 'dir')
            mkdir(cfg.paths.figures);
        end

        cfg.diagnostics.outputFolder = fullfile( ...
            cfg.paths.results, ...
            'diagnostics', ...
            char(coupling));

        if diagnosticMode
            cfg.diagnostics.enabled = true;
            cfg.diagnostics.testMode = true;
            cfg.diagnostics.candidateIndex = diagnosticCandidateIndex;
        else
            cfg.diagnostics.enabled = false;
            cfg.diagnostics.testMode = false;
        end

        if ~exist(cfg.diagnostics.outputFolder, 'dir')
            mkdir(cfg.diagnostics.outputFolder);
        end

        cfg.evaluation.resultFileName = sprintf( ...
            'results_%s_%s.mat', ...
            lower(string(cfg.system.bessCoupling)), ...
            lower(string(cfg.dispatch.objectiveMode)));

        fprintf('\n====================================================\n');
        fprintf('RUN MODE: %s | COUPLING: %s\n', objectiveMode, coupling);
        fprintf('====================================================\n');

        industrialCtx = prepare_industrial_simulation_context(data, cfg);

        DB = init_candidate_database_structures(data, cfg);
        DB.industrialCtxInfo = industrialCtx.info;
        DB.runInfo = struct();
        DB.runInfo.coupling = coupling;
        DB.runInfo.objectiveMode = objectiveMode;

        DB = simulate_candidates_database(data, DB, cfg, industrialCtx);

        save_candidates_database(DB, cfg);

        if ~diagnosticMode
            evalCfg = create_evaluation_config(cfg);
            evaluationResult = evaluation(cfg, evalCfg, DB); %#ok<NASGU>
        end

        runResult.(char(coupling)).cfg = cfg;
        runResult.(char(coupling)).DB = DB;
    end

    if ~diagnosticMode
        compareResult = compare_ac_dc_results_for_mode(cfgBase, objectiveMode); %#ok<NASGU>
        runResult.compareResult = compareResult;
    end

    runResult.finishedAt = datetime('now');
end
