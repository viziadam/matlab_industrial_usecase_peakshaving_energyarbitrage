function [figSpecs, data] = evaluation_peak_only(data, cfg, opts)
% EVALUATION_PEAK_ONLY
%
% Peak only uzemmodhoz tartozo dolgozati kiertekeles.
%
% Itt csak a peak shavinghez kapcsolodo figure-ok vannak megadva.
% A plotting logikat nem itt kell kezelni.

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

    figSpecs(2).plots(2).type = "signed_stacked_bar";
    figSpecs(2).plots(2).x = "BESS_PV_ratio";
    figSpecs(2).plots(2).y = [
        "contractCostSaving_MHUF"
        "overrunCostSaving_MHUF"
        "degradationCost_MHUF"
    ];
    figSpecs(2).plots(2).signs = [1 1 -1];
    figSpecs(2).plots(2).labels = [
        "Contract saving"
        "Overrun saving"
        "Degradation cost"
    ];
    figSpecs(2).plots(2).title = "Peak shaving value components";
    figSpecs(2).plots(2).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(2).plots(2).ylabel = "Value [million HUF]";
    figSpecs(2).plots(2).zeroLine = true;
    figSpecs(2).plots(2).legend = "best";

    figSpecs(2).plots(3).type = "line";
    figSpecs(2).plots(3).x = "BESS_PV_ratio";
    figSpecs(2).plots(3).y = [
        "finalSoH"
        "equivalentCycles"
    ];
    figSpecs(2).plots(3).labels = [
        "Final SoH"
        "Equivalent cycles"
    ];
    figSpecs(2).plots(3).title = "Battery aging indicators";
    figSpecs(2).plots(3).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(2).plots(3).ylabel = "Value [-]";
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

        T = local_add_mhuf(T, "objectiveCost_HUF", "objectiveCost_MHUF");
        T = local_add_mhuf(T, "contractCost_HUF", "contractCost_MHUF");
        T = local_add_mhuf(T, "overrunCost_HUF", "overrunCost_MHUF");
        T = local_add_mhuf(T, "degradationCost_HUF", "degradationCost_MHUF");
        T = local_add_mhuf(T, "contractCostSaving_HUF", "contractCostSaving_MHUF");
        T = local_add_mhuf(T, "overrunCostSaving_HUF", "overrunCostSaving_MHUF");

        if ismember('maxGridImportNoBessPeak_kW', T.Properties.VariableNames) && ...
           ismember('maxGridImportPeak_kW', T.Properties.VariableNames)

            T.peakReduction_kW = ...
                T.maxGridImportNoBessPeak_kW - T.maxGridImportPeak_kW;

            T.peakReduction_pct = ...
                100 * T.peakReduction_kW ./ T.maxGridImportNoBessPeak_kW;
        end

        data.(char(coupling)).candidateTable = T;
    end
end


function T = local_add_mhuf(T, sourceName, targetName)

    if ismember(sourceName, T.Properties.VariableNames)
        T.(targetName) = T.(sourceName) / 1e6;
    end
end