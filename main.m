function DB = main()
% MAIN
%
% Ipari PV+BESS optimalizáció:
%   - DC/AC kapcsoló cfg.system.bessCoupling alapján
%   - candidate adatbázis
%   - közös metrikarendszer cfg.output alapján
%   - DC esetben peak shaving + energia arbitrázs + contract optimalizálás
%   - AC ág későbbi implementációhoz előkészítve

    clc;
    close all;

    basePath = fileparts(mfilename('fullpath'));

    cfg = create_configurations(basePath);

    % ---------------------------------------------------------------------
    % 1) Adatbeolvasás a meglévő keretrendszer szerint
    % ---------------------------------------------------------------------
    data = build_data(cfg);

    % ---------------------------------------------------------------------
    % 2) Ipari szimulációs kontextus egyszeri előkészítése
    % ---------------------------------------------------------------------
    industrialCtx = prepare_industrial_simulation_context(data, cfg);

    % ---------------------------------------------------------------------
    % 3) Candidate database
    % ---------------------------------------------------------------------
    DB = init_candidate_database_structures(data, cfg);

    DB.industrialCtxInfo = industrialCtx.info;

    % ---------------------------------------------------------------------
    % 4) Candidate-ek futtatása
    % ---------------------------------------------------------------------
    DB = simulate_candidates_database(data, DB, cfg, industrialCtx);

    % ---------------------------------------------------------------------
    % 5) Mentés
    % ---------------------------------------------------------------------
    save_candidates_database(DB, cfg);

    fprintf('\nIndustrial PV+BESS candidate database simulation finished.\n');
    fprintf('Coupling: %s\n', string(cfg.system.bessCoupling));
    fprintf('Candidates: %d\n', height(DB.candidateTable));

    % ---------------------------------------------------------------------
    % 6) Kiértékelés
    % ---------------------------------------------------------------------
    evalCfg = create_evaluation_config(cfg);
    evaluationResult = evaluation(cfg, evalCfg); %#ok<NASGU>
end