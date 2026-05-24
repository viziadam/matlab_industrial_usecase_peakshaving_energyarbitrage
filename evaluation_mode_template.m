function out = evaluation_mode_template(objectiveMode, cfg, opts)
% EVALUATION_MODE_TEMPLATE
% Generic user-editable evaluation skeleton for one operation mode.
% It loads saved DC/AC result databases and exposes candidate tables.
% It does not modify simulation, saving logic, or saved metric definitions.

    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    opts = local_set_default(opts, 'couplings', ["dc", "ac"]);
    opts = local_set_default(opts, 'makeExamplePlots', true);
    opts = local_set_default(opts, 'saveFigures', true);
    opts = local_set_default(opts, 'outputFolder', fullfile(cfg.paths.figures, 'custom_evaluation', char(objectiveMode)));

    objectiveMode = lower(string(objectiveMode));

    out = struct();
    out.objectiveMode = objectiveMode;
    out.createdAt = datetime('now');
    out.opts = opts;
    out.data = eval_load_result_pair(cfg, objectiveMode, opts.couplings);
    out.examples = struct();
    out.figures = struct();

    if opts.makeExamplePlots
        plotOpts = struct();
        plotOpts.outputFolder = opts.outputFolder;
        plotOpts.saveFigure = opts.saveFigures;

        % Example 1: simple grouped bar for objective cost
        spec1 = struct();
        spec1.name = char(objectiveMode + "_objective_cost_grouped");
        spec1.xField = "BESS_PV_ratio";
        spec1.yFields = "objectiveCost_HUF";
        spec1.yLabels = "Objective cost";
        spec1.scale = 1e-6;
        spec1.title = "Objective cost - " + objectiveMode;
        spec1.xlabel = "BESS/PV ratio [kWh/kWp]";
        spec1.ylabel = "Cost [million HUF]";
        spec1.legendLocation = "best";
        spec1.showValues = false;

        out.figures.objectiveCostGrouped = eval_plot_grouped_bar(out.data, spec1, plotOpts);

        % Example 2: lines for final SoH
        spec2 = struct();
        spec2.name = char(objectiveMode + "_final_soh_lines");
        spec2.xField = "BESS_PV_ratio";
        spec2.yFields = "finalSoH";
        spec2.yLabels = "Final SoH";
        spec2.scale = 1.0;
        spec2.title = "Final SoH - " + objectiveMode;
        spec2.xlabel = "BESS/PV ratio [kWh/kWp]";
        spec2.ylabel = "SoH [-]";
        spec2.legendLocation = "best";
        spec2.showValues = false;

        out.figures.finalSoH = eval_plot_lines(out.data, spec2, plotOpts);
    end
end


function S = local_set_default(S, fieldName, defaultValue)
    if ~isfield(S, fieldName) || isempty(S.(fieldName))
        S.(fieldName) = defaultValue;
    end
end
