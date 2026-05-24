function fig = eval_plot_signed_stacked_grouped_bar(data, spec, opts)
% EVAL_PLOT_SIGNED_STACKED_GROUPED_BAR
% Signed stacked grouped bar template for DC/AC comparison.
% Positive components are plotted upward, negative components downward.
%
% Example:
%   modeData = eval_load_result_pair(cfg, "combined", ["dc", "ac"]);
%   spec = struct();
%   spec.name = "signed_value_stack";
%   spec.xField = "BESS_PV_ratio";
%   spec.yFields = ["energyCostSaving_HUF", "overrunCost_HUF", "degradationCost_HUF"];
%   spec.ySigns = [1, -1, -1];
%   spec.yLabels = ["Energy saving", "Overrun cost", "Degradation cost"];
%   spec.scale = 1e-6;
%   spec.title = "Positive and negative value stack";
%   spec.xlabel = "BESS/PV ratio [kWh/kWp]";
%   spec.ylabel = "Value [million HUF]";
%   spec.showStackValues = true;
%   spec.valueFormat = "%.1f";
%   spec.showZeroLine = true;
%   fig = eval_plot_signed_stacked_grouped_bar(modeData, spec);

    if nargin < 3
        opts = struct();
    end

    spec.type = "signed_stacked_grouped_bar";
    fig = eval_plot_generic(data, spec, opts);
end
