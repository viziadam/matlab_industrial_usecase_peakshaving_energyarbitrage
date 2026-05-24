function [figSpecs, data] = evaluation_peak_only(data, cfg, opts)
% EVALUATION_PEAK_ONLY
%
% Peak only uzemmodhoz tartozo dolgozati kiertekeles.
%
% Csak a create_configurations.m alapjan letezo mentett mezoket,
% illetve azokbol itt szarmaztatott mezoket hasznal.

    data = local_add_peak_only_derived_columns(data);

    figSpecs = struct([]);

    % =====================================================================
    % FIGURE 1 - Peak shaving overview
    % =====================================================================
    figSpecs(1).name = "peak_only_peak_shaving_overview";
    figSpecs(1).layout = [2 2];

    figSpecs(1).plots(1).type = "line";
    figSpecs(1).plots(1).x = "BESS_PV_ratio";
    figSpecs(1).plots(1).y = [
        "bestContract_kW"
        "maxGridImportPeak_kW"
        "maxGridImportNoBessPeak_kW"
    ];
    figSpecs(1).plots(1).labels = [
        "Best contract"
        "Grid peak with BESS"
        "No-BESS grid peak"
    ];
    figSpecs(1).plots(1).title = "Contracted power and grid peak";
    figSpecs(1).plots(1).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(1).plots(1).ylabel = "Power [kW]";
    figSpecs(1).plots(1).legend = "best";

    figSpecs(1).plots(2).type = "grouped_bar";
    figSpecs(1).plots(2).x = "BESS_PV_ratio";
    figSpecs(1).plots(2).y = "peakReduction_kW";
    figSpecs(1).plots(2).title = "Peak reduction";
    figSpecs(1).plots(2).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(1).plots(2).ylabel = "Peak reduction [kW]";
    figSpecs(1).plots(2).legend = "best";
    figSpecs(1).plots(2).values = true;
    figSpecs(1).plots(2).valueFmt = "%.0f";

    figSpecs(1).plots(3).type = "grouped_bar";
    figSpecs(1).plots(3).x = "BESS_PV_ratio";
    figSpecs(1).plots(3).y = "peakReduction_pct";
    figSpecs(1).plots(3).title = "Relative peak reduction";
    figSpecs(1).plots(3).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(1).plots(3).ylabel = "Peak reduction [%]";
    figSpecs(1).plots(3).legend = "best";
    figSpecs(1).plots(3).values = true;
    figSpecs(1).plots(3).valueFmt = "%.1f";

    figSpecs(1).plots(4).type = "scatter";
    figSpecs(1).plots(4).x = "E_BESS_kWh";
    figSpecs(1).plots(4).y = "peakReduction_kW";
    figSpecs(1).plots(4).title = "Peak reduction by BESS capacity";
    figSpecs(1).plots(4).xlabel = "BESS capacity [kWh]";
    figSpecs(1).plots(4).ylabel = "Peak reduction [kW]";
    figSpecs(1).plots(4).legend = "best";

    % =====================================================================
    % FIGURE 2 - Peak shaving cost overview
    % =====================================================================
    figSpecs(2).name = "peak_only_cost_overview";
    figSpecs(2).layout = [2 2];

    figSpecs(2).plots(1).type = "stacked_bar_line";
    figSpecs(2).plots(1).x = "BESS_PV_ratio";
    figSpecs(2).plots(1).y = [
        "contractCost_MHUF"
        "overrunCost_MHUF"
        "degradationCost_MHUF"
    ];
    figSpecs(2).plots(1).labels = [
        "Contract cost"
        "Overrun cost"
        "Degradation cost"
    ];
    figSpecs(2).plots(1).lineY = "objectiveCost_MHUF";
    figSpecs(2).plots(1).lineLabels = "Objective";
    figSpecs(2).plots(1).title = "Peak shaving cost components";
    figSpecs(2).plots(1).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(2).plots(1).ylabel = "Cost [million HUF]";
    figSpecs(2).plots(1).legend = "best";

    figSpecs(2).plots(2).type = "grouped_bar";
    figSpecs(2).plots(2).x = "BESS_PV_ratio";
    figSpecs(2).plots(2).y = "objectiveCost_MHUF";
    figSpecs(2).plots(2).title = "Objective cost";
    figSpecs(2).plots(2).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(2).plots(2).ylabel = "Cost [million HUF]";
    figSpecs(2).plots(2).legend = "best";
    figSpecs(2).plots(2).values = true;
    figSpecs(2).plots(2).valueFmt = "%.1f";

    figSpecs(2).plots(3).type = "line";
    figSpecs(2).plots(3).x = "BESS_PV_ratio";
    figSpecs(2).plots(3).y = [
        "finalSoH_pct"
        "equivalentCycles"
    ];
    figSpecs(2).plots(3).labels = [
        "Final SoH [%]"
        "Equivalent cycles"
    ];
    figSpecs(2).plots(3).title = "Battery aging indicators";
    figSpecs(2).plots(3).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(2).plots(3).ylabel = "Value";
    figSpecs(2).plots(3).legend = "best";

    figSpecs(2).plots(4).type = "heatmap";
    figSpecs(2).plots(4).coupling = "dc";
    figSpecs(2).plots(4).x = "E_BESS_kWh";
    figSpecs(2).plots(4).y = "P_BESS_kW";
    figSpecs(2).plots(4).z = "objectiveCost_MHUF";
    figSpecs(2).plots(4).title = "DC objective cost map";
    figSpecs(2).plots(4).xlabel = "BESS capacity [kWh]";
    figSpecs(2).plots(4).ylabel = "BESS power [kW]";
    figSpecs(2).plots(4).colorLabel = "Cost [million HUF]";
    figSpecs(2).plots(4).hideLegend = true;
end


function data = local_add_peak_only_derived_columns(data)

    couplings = string(fieldnames(data));

    for i = 1:numel(couplings)

        coupling = couplings(i);

        if ~isfield(data.(char(coupling)), 'candidateTable')
            continue;
        end

        T = data.(char(coupling)).candidateTable;

        T.objectiveCost_MHUF = T.objectiveCost_HUF / 1e6;
        T.contractCost_MHUF = T.contractCost_HUF / 1e6;
        T.overrunCost_MHUF = T.overrunCost_HUF / 1e6;
        T.degradationCost_MHUF = T.degradationCost_HUF / 1e6;

        data.(char(coupling)).candidateTable = T;
    end
end