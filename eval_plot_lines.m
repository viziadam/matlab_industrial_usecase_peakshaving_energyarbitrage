function fig = eval_plot_lines(data, spec, opts)
% EVAL_PLOT_LINES
% Line plot template for DC/AC comparison across all BESS sizes.
%
% Example:
%   modeData = eval_load_result_pair(cfg, "energy_only", ["dc", "ac"]);
%   spec = struct();
%   spec.name = "technical_lines";
%   spec.xField = "BESS_PV_ratio";
%   spec.yFields = ["finalSoH", "equivalentCycles"];
%   spec.yLabels = ["Final SoH", "Equivalent cycles"];
%   spec.scale = 1;
%   spec.title = "Technical indicators";
%   spec.xlabel = "BESS/PV ratio [kWh/kWp]";
%   spec.ylabel = "Value [-]";
%   spec.showLineValues = true;
%   spec.valueFormat = "%.2f";
%   fig = eval_plot_lines(modeData, spec);

    if nargin < 3
        opts = struct();
    end

    spec.type = "lines";
    fig = eval_plot_generic(data, spec, opts);
end
