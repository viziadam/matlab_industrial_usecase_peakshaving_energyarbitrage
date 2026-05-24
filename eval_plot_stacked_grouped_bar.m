function fig = eval_plot_stacked_grouped_bar(data, spec, opts)
% EVAL_PLOT_STACKED_GROUPED_BAR
% Stacked grouped bar template for DC/AC comparison across all BESS sizes.
%
% Example: converter losses stacked by component, DC and AC side-by-side.
%   modeData = eval_load_result_pair(cfg, "energy_only", ["dc", "ac"]);
%   spec = struct();
%   spec.name = "converter_losses_stacked";
%   spec.xField = "BESS_PV_ratio";
%   spec.yFields = ["centralInverterLoss_kWh", "dcdcLoss_kWh", "pcsLoss_kWh"];
%   spec.yLabels = ["Central inverter", "DC/DC", "PCS"];
%   spec.scale = 1;
%   spec.title = "Converter losses by BESS size";
%   spec.xlabel = "BESS/PV ratio [kWh/kWp]";
%   spec.ylabel = "Loss [kWh]";
%   spec.showStackValues = true;
%   spec.valueFormat = "%.0f";
%   fig = eval_plot_stacked_grouped_bar(modeData, spec);

    if nargin < 3
        opts = struct();
    end

    spec.type = "stacked_grouped_bar";
    fig = eval_plot_generic(data, spec, opts);
end
