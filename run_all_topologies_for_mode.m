function runResult = run_all_topologies_for_mode(objectiveMode, diagnosticCandidateIndex)
% RUN_ALL_TOPOLOGIES_FOR_MODE
%
% Egy kivalasztott mukodesi modra lefuttatja a topologiakat:
%   - DC
%   - AC
%   - HYBRID csak combined modban
%
% Megjegyzes:
%   A compare_ac_dc_results_for_mode tovabbra is csak a legacy AC/DC
%   osszehasonlitasra szolgal. A hybrid eredmenyek kulon DB fajlba
%   mentodnek, es kesobb kulon hybrid kiertekelo fajl dolgozza fel oket.

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

    if ~isfield(cfgBase, 'profiling')
        cfgBase.profiling = struct();
    end

    if ~isfield(cfgBase.profiling, 'enabled')
        cfgBase.profiling.enabled = true;
    end

    data = build_data(cfgBase);

    industrialCtxForOverview = prepare_industrial_simulation_context(data, cfgBase);
    overviewResult = plot_industrial_case_overview(cfgBase, industrialCtxForOverview); %#ok<NASGU>

    if objectiveMode == "combined"
        % couplings = ["dc", "ac", "hybrid"];
        couplings = [ "ac", "hybrid"];
    else
        couplings = ["dc", "ac"];
    end

    runResult = struct();
    runResult.objectiveMode = objectiveMode;
    runResult.startedAt = datetime('now');

    diagnosticMode = ~isempty(diagnosticCandidateIndex);

    for i = 1:numel(couplings)

        coupling = couplings(i);

        cfg = cfgBase;
        cfg.system.bessCoupling = coupling;
        cfg.dispatch.objectiveMode = objectiveMode;

        if coupling == "hybrid"
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


        cfg.paths.results = fullfile(cfgBase.paths.results, char(objectiveMode));
        cfg.paths.figures = fullfile(cfg.paths.results, 'figures');

        if ~exist(cfg.paths.results, 'dir')
            mkdir(cfg.paths.results);
        end

        if ~exist(cfg.paths.figures, 'dir')
            mkdir(cfg.paths.figures);
        end

        cfg.diagnostics.outputFolder = fullfile(cfg.paths.results, 'diagnostics', char(coupling));

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

        % Egységes, újrahasznosítható candidate-szintű kiértékelési cache.
        % Diagnosztikai és teljes futás esetén is ugyanabba a struktúrába ment.
        candidateMetrics = save_canonical_candidate_metrics(DB, cfg); %#ok<NASGU>

        if ~diagnosticMode && coupling ~= "hybrid"

            if local_has_valid_baseline_candidate(DB)

                evalCfg = create_evaluation_config(cfg);
                evaluationResult = evaluation(cfg, evalCfg, DB); %#ok<NASGU>

            else

                fprintf('\nLegacy evaluation skipped for %s because no valid BESS_PV_ratio = 0 baseline candidate was found.\n', coupling);
                fprintf('Simulation results and canonical candidate metrics were saved successfully.\n');

            end

        elseif ~diagnosticMode && coupling == "hybrid"

            fprintf('\nHybrid DB saved. Legacy evaluation skipped for hybrid; use the future hybrid evaluator.\n');

        end

        runResult.(char(coupling)).cfg = cfg;
        runResult.(char(coupling)).DB = DB;
    end

    if diagnosticMode
        % Teljes szimulalt idoszakra vonatkozo AC/DC diagnosztikai
        % osszehasonlitas. A candidateTable-ben mentett, teljes horizonra
        % osszegzett kanonikus metrikakbol dolgozik, nem a final_day-bol.
        disp('szia!! :)')
        % runResult.acDcDiagnosticComparison = ...
        %     plot_ac_dc_diagnostic_comparison( ...
        %         runResult, ...
        %         cfgBase, ...
        %         objectiveMode, ...
        %         diagnosticCandidateIndex);
    else
        compareResult = compare_ac_dc_results_for_mode(cfgBase, objectiveMode);

        if objectiveMode == "energy_only" || objectiveMode == "combined"
            compareResult.figures.arbitrageEnergyFlowFigures = ...
                plot_arbitrage_energy_flow_figures(compareResult.tableAll, cfgBase, compareResult.outputFolder);

            save(fullfile(compareResult.outputFolder, 'comparison_result.mat'), ...
                'compareResult', '-v7.3');
        end

        runResult.compareResult = compareResult;
    end

    runResult.finishedAt = datetime('now');
end

function hasBaseline = local_has_valid_baseline_candidate(DB)

    hasBaseline = false;

    if ~isfield(DB, 'candidateTable') || isempty(DB.candidateTable)
        return;
    end

    T = DB.candidateTable;

    requiredColumns = {'BESS_PV_ratio', 'wasSimulated', 'hasError'};

    for i = 1:numel(requiredColumns)
        if ~ismember(requiredColumns{i}, T.Properties.VariableNames)
            return;
        end
    end

    validMask = logical(T.wasSimulated) & ~logical(T.hasError);
    baselineMask = abs(T.BESS_PV_ratio) < 1e-12;

    hasBaseline = any(validMask & baselineMask);
end
