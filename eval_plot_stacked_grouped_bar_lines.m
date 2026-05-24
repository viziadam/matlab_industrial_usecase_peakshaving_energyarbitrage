function fig = eval_plot_stacked_grouped_bar_lines(data, spec, opts)
% EVAL_PLOT_STACKED_GROUPED_BAR_LINES
% Stacked grouped bar template with optional overlay curves.
%
% Example: cost components as stacked bars and objective cost as line.
%   modeData = eval_load_result_pair(cfg, "combined", ["dc", "ac"]);
%   spec = struct();
%   spec.name = "cost_stack_with_objective";
%   spec.xField = "BESS_PV_ratio";
%   spec.yFields = ["energyCost_HUF", "contractCost_HUF", "overrunCost_HUF", "degradationCost_HUF"];
%   spec.yLabels = ["Energy", "Contract", "Overrun", "Degradation"];
%   spec.lineFields = "objectiveCost_HUF";
%   spec.lineLabels = "Objective cost";
%   spec.scale = 1e-6;
%   spec.lineScale = 1e-6;
%   spec.title = "Cost stack with objective curve";
%   spec.xlabel = "BESS/PV ratio [kWh/kWp]";
%   spec.ylabel = "Cost [million HUF]";
%   spec.showLineValues = true;
%   spec.valueFormat = "%.1f";
%   fig = eval_plot_stacked_grouped_bar_lines(modeData, spec);

    if nargin < 3
        opts = struct();
    end

    spec.type = "stacked_grouped_bar_lines";
    fig = eval_plot_generic(data, spec, opts);
end
