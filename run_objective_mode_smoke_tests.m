function smokeResults = run_objective_mode_smoke_tests(data, DB_in, basePath, candidateIndex)
% RUN_OBJECTIVE_MODE_SMOKE_TESTS
%
% Gyors teszt mind a 6 esetre:
%   dc/ac x peak_only/energy_only/combined
%
% Nem valtoztatja a szimulacios lepeskozt.
% Nem kapcsol be reszletes napi diagnostic mentest.
% Nem keszit dispatch diagnostic plotokat.
%
% Bemenetek:
%   data           - mar betoltott bemeneti adatstruktura
%   DB_in          - eredeti candidate adatbazis
%   basePath       - projekt gyoker
%   candidateIndex - tesztelendo candidate indexek, pl. [2 5 9]

    couplings = ["dc", "ac"];
    objectiveModes = ["peak_only", "energy_only", "combined"];

    smokeResults = struct();

    for iC = 1:numel(couplings)

        for iM = 1:numel(objectiveModes)

            coupling = couplings(iC);
            objectiveMode = objectiveModes(iM);

            cfg = create_configurations(basePath);
            cfg = configure_objective_case(cfg, coupling, objectiveMode, "smoke_test");

            % -------------------------------------------------------------
            % A lepeskoz marad 15 perc.
            % -------------------------------------------------------------
            cfg.targetStepMin = 15;

            % -------------------------------------------------------------
            % Gyors diagnosztikai futas:
            % csak baseline + kijelolt candidate-ek,
            % de reszletes debug/plot nelkul.
            % -------------------------------------------------------------
            cfg.diagnostics.enabled = true;
            cfg.diagnostics.testMode = true;
            cfg.diagnostics.candidateIndex = candidateIndex;

            cfg.diagnostics.storeCandidateDetail = false;
            cfg.diagnostics.storePlannerDebug = false;
            cfg.diagnostics.printPlannerDebug = false;

            cfg.diagnostics.makePlots = false;
            cfg.diagnostics.saveFigures = false;
            cfg.diagnostics.makePlannerExecutionDebugPlot = false;
            cfg.diagnostics.makeDispatchDiagnosticPlots = false;
            cfg.diagnostics.plotDispatchDiagnosticsForBaseline = false;

            cfg.diagnostics.runEvaluation = true;

            cfg.sim.verbose = false;
            cfg.sim.saveAfterEachCandidate = false;

            DB = DB_in;

            industrialCtx = prepare_industrial_simulation_context(data, cfg);

            fprintf('\n====================================================\n');
            fprintf('SMOKE TEST: coupling = %s | objectiveMode = %s\n', ...
                coupling, objectiveMode);
            fprintf('====================================================\n');

            tCase = tic;

            DB = simulate_candidates_database(data, DB, cfg, industrialCtx);

            runtime_s = toc(tCase);

            fieldName = sprintf('%s_%s', coupling, objectiveMode);

            smokeResults.(fieldName) = struct();
            smokeResults.(fieldName).DB = DB;
            smokeResults.(fieldName).runtime_s = runtime_s;
            smokeResults.(fieldName).resultFolder = cfg.paths.results;

            save(fullfile(cfg.paths.results, 'smoke_test_result.mat'), ...
                'DB', ...
                'cfg', ...
                'runtime_s', ...
                '-v7.3');
        end
    end
end