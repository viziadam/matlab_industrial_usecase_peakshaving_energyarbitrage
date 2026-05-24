function fig = eval_plot_signed_stacked_grouped_bar_lines(data, spec, opts)
% EVAL_PLOT_SIGNED_STACKED_GROUPED_BAR_LINES
% Signed stacked grouped bar template with overlay curves.
% Positive components are plotted upward, negative components downward.
%
% Example:
%   modeData = eval_load_result_pair(cfg, "combined", ["dc", "ac"]);
%   spec = struct();
%   spec.name = "signed_value_stack_with_net";
%   spec.xField = "BESS_PV_ratio";
%   spec.yFields = ["energyCostSaving_HUF", "overrunCost_HUF", "degradationCost_HUF"];
%   spec.ySigns = [1, -1, -1];
%   spec.yLabels = ["Energy saving", "Overrun cost", "Degradation cost"];
%   spec.lineFields = "objectiveCost_HUF";
%   spec.lineLabels = "Objective cost";
%   spec.scale = 1e-6;
%   spec.lineScale = 1e-6;
%   spec.title = "Signed stack with objective curve";
%   spec.xlabel = "BESS/PV ratio [kWh/kWp]";
%   spec.ylabel = "Value [million HUF]";
%   spec.showStackValues = false;
%   spec.showLineValues = true;
%   spec.valueFormat = "%.1f";
%   spec.showZeroLine = true;
%   fig = eval_plot_signed_stacked_grouped_bar_lines(modeData, spec);

    if nargin < 3
        opts = struct();
    end

    spec.type = "signed_stacked_grouped_bar_lines";
    fig = eval_plot_generic(data, spec, opts);
end
