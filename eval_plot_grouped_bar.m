function fig = eval_plot_grouped_bar(data, spec, opts)
% EVAL_PLOT_GROUPED_BAR
% Grouped bar template for DC/AC comparison across all BESS sizes.
%
% Example:
%   modeData = eval_load_result_pair(cfg, "energy_only", ["dc", "ac"]);
%   spec = struct();
%   spec.name = "final_soh_grouped";
%   spec.xField = "BESS_PV_ratio";
%   spec.yFields = "finalSoH";
%   spec.yLabels = "Final SoH";
%   spec.scale = 1;
%   spec.title = "Final SoH by BESS size";
%   spec.xlabel = "BESS/PV ratio [kWh/kWp]";
%   spec.ylabel = "SoH [-]";
%   spec.showValues = true;
%   fig = eval_plot_grouped_bar(modeData, spec);

    if nargin < 3
        opts = struct();
    end

    spec.type = "grouped_bar";
    fig = eval_plot_generic(data, spec, opts);
end
