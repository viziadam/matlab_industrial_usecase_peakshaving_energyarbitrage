function specs = eval_plot_examples(exampleGroup)
% EVAL_PLOT_EXAMPLES
% Editable example plot specifications for the generic evaluation plotting system.
%
% Usage:
%   specs = eval_plot_examples();
%   specs = eval_plot_examples("all");
%   specs = eval_plot_examples("costs");
%   specs = eval_plot_examples("technical");
%   specs = eval_plot_examples("signed");
%
% The returned specs can be edited freely and passed to:
%   eval_plot_batch(modeData, specs, opts)
% or individually to one of:
%   eval_plot_grouped_bar
%   eval_plot_stacked_grouped_bar
%   eval_plot_stacked_grouped_bar_lines
%   eval_plot_signed_stacked_grouped_bar
%   eval_plot_signed_stacked_grouped_bar_lines
%   eval_plot_lines

    if nargin < 1 || isempty(exampleGroup)
        exampleGroup = "all";
    end

    exampleGroup = lower(string(exampleGroup));

    allSpecs = local_all_specs();

    switch exampleGroup
        case "all"
            specs = allSpecs;

        case "costs"
            names = ["objective_cost_grouped", "cost_components_stacked", "cost_stack_with_objective_line"];
            specs = local_filter_specs(allSpecs, names);

        case "technical"
            names = ["final_soh_lines", "contract_and_peak_lines"];
            specs = local_filter_specs(allSpecs, names);

        case "signed"
            names = ["signed_value_stack", "signed_value_stack_with_line"];
            specs = local_filter_specs(allSpecs, names);

        otherwise
            error('Unknown exampleGroup: %s', exampleGroup);
    end
end


function specs = local_all_specs()

    specs = struct([]);
    k = 0;

    % ------------------------------------------------------------------
    % 1) Simple grouped bar
    % ------------------------------------------------------------------
    k = k + 1;
    specs(k).name = "objective_cost_grouped";
    specs(k).type = "grouped_bar";
    specs(k).xField = "BESS_PV_ratio";
    specs(k).yFields = "objectiveCost_HUF";
    specs(k).yLabels = "Objective cost";
    specs(k).scale = 1e-6;
    specs(k).title = "Objective cost by BESS size";
    specs(k).xlabel = "BESS/PV ratio [kWh/kWp]";
    specs(k).ylabel = "Cost [million HUF]";
    specs(k).legendLocation = "best";
    specs(k).showValues = false;
    specs(k).valueFormat = "%.1f";

    % ------------------------------------------------------------------
    % 2) Stacked grouped bar
    % ------------------------------------------------------------------
    k = k + 1;
    specs(k).name = "cost_components_stacked";
    specs(k).type = "stacked_grouped_bar";
    specs(k).xField = "BESS_PV_ratio";
    specs(k).yFields = ["energyCost_HUF", "contractCost_HUF", "overrunCost_HUF", "degradationCost_HUF"];
    specs(k).yLabels = ["Energy", "Contract", "Overrun", "Degradation"];
    specs(k).scale = 1e-6;
    specs(k).title = "Cost components by BESS size";
    specs(k).xlabel = "BESS/PV ratio [kWh/kWp]";
    specs(k).ylabel = "Cost [million HUF]";
    specs(k).legendLocation = "best";
    specs(k).showStackValues = false;
    specs(k).valueFormat = "%.1f";

    % ------------------------------------------------------------------
    % 3) Stacked grouped bar with overlay line
    % ------------------------------------------------------------------
    k = k + 1;
    specs(k).name = "cost_stack_with_objective_line";
    specs(k).type = "stacked_grouped_bar_lines";
    specs(k).xField = "BESS_PV_ratio";
    specs(k).yFields = ["energyCost_HUF", "contractCost_HUF", "overrunCost_HUF", "degradationCost_HUF"];
    specs(k).yLabels = ["Energy", "Contract", "Overrun", "Degradation"];
    specs(k).lineFields = "objectiveCost_HUF";
    specs(k).lineLabels = "Objective cost";
    specs(k).scale = 1e-6;
    specs(k).lineScale = 1e-6;
    specs(k).title = "Cost stack with objective curve";
    specs(k).xlabel = "BESS/PV ratio [kWh/kWp]";
    specs(k).ylabel = "Cost [million HUF]";
    specs(k).legendLocation = "best";
    specs(k).showStackValues = false;
    specs(k).showLineValues = true;
    specs(k).valueFormat = "%.1f";

    % ------------------------------------------------------------------
    % 4) Lines
    % ------------------------------------------------------------------
    k = k + 1;
    specs(k).name = "final_soh_lines";
    specs(k).type = "lines";
    specs(k).xField = "BESS_PV_ratio";
    specs(k).yFields = ["finalSoH", "equivalentCycles"];
    specs(k).yLabels = ["Final SoH", "Equivalent cycles"];
    specs(k).scale = 1;
    specs(k).title = "Battery technical indicators";
    specs(k).xlabel = "BESS/PV ratio [kWh/kWp]";
    specs(k).ylabel = "Value [-]";
    specs(k).legendLocation = "best";
    specs(k).showLineValues = false;
    specs(k).valueFormat = "%.2f";

    % ------------------------------------------------------------------
    % 5) Signed stacked grouped bar
    % ------------------------------------------------------------------
    k = k + 1;
    specs(k).name = "signed_value_stack";
    specs(k).type = "signed_stacked_grouped_bar";
    specs(k).xField = "BESS_PV_ratio";
    specs(k).yFields = ["energyCostSaving_HUF", "overrunCost_HUF", "degradationCost_HUF"];
    specs(k).ySigns = [1, -1, -1];
    specs(k).yLabels = ["Energy saving", "Overrun cost", "Degradation cost"];
    specs(k).scale = 1e-6;
    specs(k).title = "Positive and negative value stack";
    specs(k).xlabel = "BESS/PV ratio [kWh/kWp]";
    specs(k).ylabel = "Value [million HUF]";
    specs(k).legendLocation = "best";
    specs(k).showStackValues = true;
    specs(k).valueFormat = "%.1f";
    specs(k).showZeroLine = true;

    % ------------------------------------------------------------------
    % 6) Signed stacked grouped bar with overlay line
    % ------------------------------------------------------------------
    k = k + 1;
    specs(k).name = "signed_value_stack_with_line";
    specs(k).type = "signed_stacked_grouped_bar_lines";
    specs(k).xField = "BESS_PV_ratio";
    specs(k).yFields = ["energyCostSaving_HUF", "overrunCost_HUF", "degradationCost_HUF"];
    specs(k).ySigns = [1, -1, -1];
    specs(k).yLabels = ["Energy saving", "Overrun cost", "Degradation cost"];
    specs(k).lineFields = "objectiveCost_HUF";
    specs(k).lineLabels = "Objective cost";
    specs(k).scale = 1e-6;
    specs(k).lineScale = 1e-6;
    specs(k).title = "Signed value stack with objective curve";
    specs(k).xlabel = "BESS/PV ratio [kWh/kWp]";
    specs(k).ylabel = "Value [million HUF]";
    specs(k).legendLocation = "best";
    specs(k).showStackValues = false;
    specs(k).showLineValues = true;
    specs(k).valueFormat = "%.1f";
    specs(k).showZeroLine = true;

    % ------------------------------------------------------------------
    % 7) Contract and peak lines
    % ------------------------------------------------------------------
    k = k + 1;
    specs(k).name = "contract_and_peak_lines";
    specs(k).type = "lines";
    specs(k).xField = "BESS_PV_ratio";
    specs(k).yFields = ["bestContract_kW", "maxGridImportPeak_kW", "maxGridImportNoBessPeak_kW"];
    specs(k).yLabels = ["Best contract", "Grid peak with BESS", "No-BESS grid peak"];
    specs(k).scale = 1;
    specs(k).title = "Contract and peak power";
    specs(k).xlabel = "BESS/PV ratio [kWh/kWp]";
    specs(k).ylabel = "Power [kW]";
    specs(k).legendLocation = "best";
    specs(k).showLineValues = false;
    specs(k).valueFormat = "%.0f";
end


function selected = local_filter_specs(specs, names)

    selected = struct([]);

    for i = 1:numel(specs)
        if any(string(specs(i).name) == names)
            selected(end+1) = specs(i); %#ok<AGROW>
        end
    end
end
