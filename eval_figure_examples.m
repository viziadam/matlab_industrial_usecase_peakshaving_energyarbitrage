function figSpecs = eval_figure_examples(groupName)
% EVAL_FIGURE_EXAMPLES
% Editable examples for eval_build_figures.
%
% You can copy any block into plot_energy_only_thesis_evaluation,
% plot_peak_only_thesis_evaluation, or plot_combined_thesis_evaluation.
%
% Only edit the specs: type, y, labels, lineY, signs, titles, layout.

    if nargin < 1 || isempty(groupName)
        groupName = "all";
    end

    groupName = lower(string(groupName));

    switch groupName
        case "all"
            figSpecs = [example_energy_flows(), example_costs(), example_technical()];
        case "energy"
            figSpecs = example_energy_flows();
        case "costs"
            figSpecs = example_costs();
        case "technical"
            figSpecs = example_technical();
        otherwise
            error('Unknown example group: %s', groupName);
    end
end

function fs = example_energy_flows()
    fs.name = "energy_flow_overview";
    fs.layout = [2 2];

    fs.plots(1).type = "stacked_bar_line";
    fs.plots(1).x = "BESS_PV_ratio";
    fs.plots(1).y = ["gridToBess_kWh", "pvToBess_kWh", "bessLoss_kWh"];
    fs.plots(1).labels = ["Grid to BESS", "PV to BESS", "BESS losses"];
    fs.plots(1).lineY = "bessStoredActual_kWh";
    fs.plots(1).lineLabels = "Stored actual";
    fs.plots(1).title = "BESS charging energy and stored energy";
    fs.plots(1).xlabel = "BESS/PV ratio [kWh/kWp]";
    fs.plots(1).ylabel = "Energy [kWh]";
    fs.plots(1).legend = "best";

    fs.plots(2).type = "stacked_bar";
    fs.plots(2).x = "BESS_PV_ratio";
    fs.plots(2).y = ["pvToLoad_kWh", "pvToBess_kWh", "pvCurtailment_kWh"];
    fs.plots(2).labels = ["PV to load", "PV to BESS", "PV curtailment"];
    fs.plots(2).title = "PV energy distribution";
    fs.plots(2).xlabel = "BESS/PV ratio [kWh/kWp]";
    fs.plots(2).ylabel = "Energy [kWh]";

    fs.plots(3).type = "grouped_bar";
    fs.plots(3).x = "BESS_PV_ratio";
    fs.plots(3).y = "gridImport_kWh";
    fs.plots(3).title = "Grid import";
    fs.plots(3).xlabel = "BESS/PV ratio [kWh/kWp]";
    fs.plots(3).ylabel = "Energy [kWh]";

    fs.plots(4).type = "line";
    fs.plots(4).x = "BESS_PV_ratio";
    fs.plots(4).y = ["selfConsumption_pct", "gridImportReduction_pct"];
    fs.plots(4).labels = ["Self-consumption", "Grid import reduction"];
    fs.plots(4).title = "Energy performance indicators";
    fs.plots(4).xlabel = "BESS/PV ratio [kWh/kWp]";
    fs.plots(4).ylabel = "Ratio [%]";
end

function fs = example_costs()
    fs.name = "cost_overview";
    fs.layout = [2 2];

    fs.plots(1).type = "stacked_bar_line";
    fs.plots(1).x = "BESS_PV_ratio";
    fs.plots(1).y = ["energyCost_HUF", "contractCost_HUF", "overrunCost_HUF", "degradationCost_HUF"];
    fs.plots(1).labels = ["Energy", "Contract", "Overrun", "Degradation"];
    fs.plots(1).lineY = "objectiveCost_HUF";
    fs.plots(1).lineLabels = "Objective";
    fs.plots(1).scale = 1e-6;
    fs.plots(1).lineScale = 1e-6;
    fs.plots(1).title = "Cost components and objective";
    fs.plots(1).xlabel = "BESS/PV ratio [kWh/kWp]";
    fs.plots(1).ylabel = "Cost [million HUF]";

    fs.plots(2).type = "signed_stacked_bar";
    fs.plots(2).x = "BESS_PV_ratio";
    fs.plots(2).y = ["energyCostSaving_HUF", "contractCostSaving_HUF", "degradationCost_HUF"];
    fs.plots(2).signs = [1 1 -1];
    fs.plots(2).labels = ["Energy saving", "Contract saving", "Degradation"];
    fs.plots(2).scale = 1e-6;
    fs.plots(2).title = "Positive and negative value components";
    fs.plots(2).xlabel = "BESS/PV ratio [kWh/kWp]";
    fs.plots(2).ylabel = "Value [million HUF]";
    fs.plots(2).zeroLine = true;

    fs.plots(3).type = "grouped_bar";
    fs.plots(3).x = "BESS_PV_ratio";
    fs.plots(3).y = "objectiveCost_HUF";
    fs.plots(3).scale = 1e-6;
    fs.plots(3).title = "Objective cost";
    fs.plots(3).xlabel = "BESS/PV ratio [kWh/kWp]";
    fs.plots(3).ylabel = "Cost [million HUF]";

    fs.plots(4).type = "line";
    fs.plots(4).x = "BESS_PV_ratio";
    fs.plots(4).y = ["NPV_HUF", "totalLifecycleCost_HUF"];
    fs.plots(4).labels = ["NPV", "Lifecycle cost"];
    fs.plots(4).scale = 1e-6;
    fs.plots(4).title = "Lifecycle indicators";
    fs.plots(4).xlabel = "BESS/PV ratio [kWh/kWp]";
    fs.plots(4).ylabel = "Value [million HUF]";
end

function fs = example_technical()
    fs.name = "technical_overview";
    fs.layout = [2 2];

    fs.plots(1).type = "line";
    fs.plots(1).x = "BESS_PV_ratio";
    fs.plots(1).y = ["finalSoH", "equivalentCycles"];
    fs.plots(1).labels = ["Final SoH", "Equivalent cycles"];
    fs.plots(1).title = "Battery aging indicators";
    fs.plots(1).xlabel = "BESS/PV ratio [kWh/kWp]";
    fs.plots(1).ylabel = "Value [-]";

    fs.plots(2).type = "line";
    fs.plots(2).x = "BESS_PV_ratio";
    fs.plots(2).y = ["bestContract_kW", "maxGridImportPeak_kW", "maxGridImportNoBessPeak_kW"];
    fs.plots(2).labels = ["Best contract", "Grid peak", "No-BESS peak"];
    fs.plots(2).title = "Peak and contracted power";
    fs.plots(2).xlabel = "BESS/PV ratio [kWh/kWp]";
    fs.plots(2).ylabel = "Power [kW]";

    fs.plots(3).type = "scatter";
    fs.plots(3).x = "E_BESS_kWh";
    fs.plots(3).y = "finalSoH";
    fs.plots(3).title = "Final SoH by BESS capacity";
    fs.plots(3).xlabel = "BESS capacity [kWh]";
    fs.plots(3).ylabel = "SoH [-]";

    fs.plots(4).type = "heatmap";
    fs.plots(4).coupling = "dc";
    fs.plots(4).x = "E_BESS_kWh";
    fs.plots(4).y = "P_BESS_kW";
    fs.plots(4).z = "objectiveCost_HUF";
    fs.plots(4).scale = 1e-6;
    fs.plots(4).title = "DC objective cost map";
    fs.plots(4).xlabel = "BESS capacity [kWh]";
    fs.plots(4).ylabel = "BESS power [kW]";
    fs.plots(4).colorLabel = "Cost [million HUF]";
end
