function run_evaluation(mode)
    
    if nargin < 1
        mode = "combined";
    end
    basePath = fileparts(mfilename('fullpath'));;

    cfg = create_configurations(basePath);

    cfg.dispatch.objectiveMode = mode;

    compareResult = compare_ac_dc_results_for_mode(cfg, mode);


end