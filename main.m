function DB = main()

    clc;
    close all;

    basePath = fileparts(mfilename('fullpath'));

    cfg = create_configurations(basePath);

    data = build_data(cfg);

    industrialCtx = prepare_industrial_simulation_context(data, cfg);

    DB = init_candidate_database_structures(data, cfg);

    DB.industrialCtxInfo = industrialCtx.info;

    DB = simulate_candidates_database(data, DB, cfg, industrialCtx);

    save_candidates_database(DB, cfg);

    fprintf('\nIndustrial PV+BESS candidate database simulation finished.\n');
    fprintf('Coupling: %s\n', string(cfg.system.bessCoupling));
    fprintf('Candidates in database: %d\n', height(DB.candidateTable));

    if isfield(cfg, 'diagnostics') && ...
       isfield(cfg.diagnostics, 'enabled') && ...
       cfg.diagnostics.enabled

        fprintf('Diagnostic mode was active. Normal evaluation was handled in simulate_candidates_database.\n');
        return;
    end

    evalCfg = create_evaluation_config(cfg);
    evaluationResult = evaluation(cfg, evalCfg, DB); %#ok<NASGU>
end