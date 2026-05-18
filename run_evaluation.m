function run_evaluation()
    
    basePath = fileparts(mfilename('fullpath'));;

    cfg = create_configurations(basePath);

    cfg.dispatch.objectiveMode = "peak_only";

    compareResult = compare_ac_dc_results_for_mode(cfg, "peak_only");


end