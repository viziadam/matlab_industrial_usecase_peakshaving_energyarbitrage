function [figSpecs, data] = evaluation_energy_only(data, cfg, opts)
% EVALUATION_ENERGY_ONLY
%
% Energy only uzemmodhoz tartozo dolgozati kiertekeles.
%
% Itt csak azt adod meg, hogy:
%   - milyen abrak legyenek,
%   - hany subplot legyen,
%   - melyik subplot milyen tipusu legyen,
%   - milyen oszlopokat abrazoljon.
%
% A plotting logikat nem itt kell kezelni.

    data = local_add_energy_only_derived_columns(data);

    figSpecs = struct([]);

    % =====================================================================
    % FIGURE 1 - Energy flow overview
    % =====================================================================
    figSpecs(1).name = "energy_only_energy_flow_overview";
    figSpecs(1).layout = [2 2];

    figSpecs(1).plots(1).type = "stacked_bar_line";
    figSpecs(1).plots(1).x = "BESS_PV_ratio";
    figSpecs(1).plots(1).y = [
        "gridToBess_MWh"
        "pvToBess_MWh"
        "bessChargeLoss_MWh"
    ];
    figSpecs(1).plots(1).labels = [
        "Grid to BESS"
        "PV to BESS"
        "Charge loss"
    ];
    figSpecs(1).plots(1).lineY = "bessStoredActual_MWh";
    figSpecs(1).plots(1).lineLabels = "Stored actual";
    figSpecs(1).plots(1).title = "BESS charging energy and stored energy";
    figSpecs(1).plots(1).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(1).plots(1).ylabel = "Energy [MWh]";
    figSpecs(1).plots(1).legend = "best";

    figSpecs(1).plots(2).type = "stacked_bar";
    figSpecs(1).plots(2).x = "BESS_PV_ratio";
    figSpecs(1).plots(2).y = [
        "pvToLoad_MWh"
        "pvToBess_MWh"
        "pvCurtailment_MWh"
    ];
    figSpecs(1).plots(2).labels = [
        "PV to load"
        "PV to BESS"
        "PV curtailment"
    ];
    figSpecs(1).plots(2).title = "PV energy distribution";
    figSpecs(1).plots(2).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(1).plots(2).ylabel = "Energy [MWh]";
    figSpecs(1).plots(2).legend = "best";

    figSpecs(1).plots(3).type = "grouped_bar";
    figSpecs(1).plots(3).x = "BESS_PV_ratio";
    figSpecs(1).plots(3).y = "gridImport_MWh";
    figSpecs(1).plots(3).title = "Grid import";
    figSpecs(1).plots(3).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(1).plots(3).ylabel = "Energy [MWh]";
    figSpecs(1).plots(3).legend = "best";
    figSpecs(1).plots(3).values = true;
    figSpecs(1).plots(3).valueFmt = "%.1f";

    figSpecs(1).plots(4).type = "line";
    figSpecs(1).plots(4).x = "BESS_PV_ratio";
    figSpecs(1).plots(4).y = [
        "selfConsumption_pct"
        "gridImportReduction_pct"
    ];
    figSpecs(1).plots(4).labels = [
        "Self-consumption"
        "Grid import reduction"
    ];
    figSpecs(1).plots(4).title = "Energy performance indicators";
    figSpecs(1).plots(4).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(1).plots(4).ylabel = "Ratio [%]";
    figSpecs(1).plots(4).legend = "best";

    % =====================================================================
    % FIGURE 2 - Cost overview
    % =====================================================================
    figSpecs(2).name = "energy_only_cost_overview";
    figSpecs(2).layout = [2 2];

    figSpecs(2).plots(1).type = "stacked_bar_line";
    figSpecs(2).plots(1).x = "BESS_PV_ratio";
    figSpecs(2).plots(1).y = [
        "energyCost_MHUF"
        "degradationCost_MHUF"
    ];
    figSpecs(2).plots(1).labels = [
        "Energy cost"
        "Degradation cost"
    ];
    figSpecs(2).plots(1).lineY = "objectiveCost_MHUF";
    figSpecs(2).plots(1).lineLabels = "Objective";
    figSpecs(2).plots(1).title = "Cost components and objective";
    figSpecs(2).plots(1).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(2).plots(1).ylabel = "Cost [million HUF]";
    figSpecs(2).plots(1).legend = "best";

    figSpecs(2).plots(2).type = "signed_stacked_bar";
    figSpecs(2).plots(2).x = "BESS_PV_ratio";
    figSpecs(2).plots(2).y = [
        "energyCostSaving_MHUF"
        "degradationCost_MHUF"
    ];
    figSpecs(2).plots(2).signs = [1 -1];
    figSpecs(2).plots(2).labels = [
        "Energy cost saving"
        "Degradation cost"
    ];
    figSpecs(2).plots(2).title = "Energy arbitrage value components";
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

    figSpecs(2).plots(4).type = "scatter";
    figSpecs(2).plots(4).x = "E_BESS_kWh";
    figSpecs(2).plots(4).y = "objectiveCost_MHUF";
    figSpecs(2).plots(4).title = "Objective cost by BESS capacity";
    figSpecs(2).plots(4).xlabel = "BESS capacity [kWh]";
    figSpecs(2).plots(4).ylabel = "Objective cost [million HUF]";
    figSpecs(2).plots(4).legend = "best";
end


function data = local_add_energy_only_derived_columns(data)

    couplings = string(fieldnames(data));

    for i = 1:numel(couplings)

        coupling = couplings(i);

        if ~isfield(data.(char(coupling)), 'candidateTable')
            continue;
        end

        T = data.(char(coupling)).candidateTable;

        T = local_add_mwh(T, "gridImport_kWh", "gridImport_MWh");
        T = local_add_mwh(T, "gridImportNoBess_kWh", "gridImportNoBess_MWh");
        T = local_add_mwh(T, "gridToBess_kWh", "gridToBess_MWh");
        T = local_add_mwh(T, "pvToBess_kWh", "pvToBess_MWh");
        T = local_add_mwh(T, "pvToLoad_kWh", "pvToLoad_MWh");
        T = local_add_mwh(T, "pvCurtailment_kWh", "pvCurtailment_MWh");
        T = local_add_mwh(T, "bessStoredActual_kWh", "bessStoredActual_MWh");
        T = local_add_mwh(T, "bessChargeLoss_kWh", "bessChargeLoss_MWh");

        T = local_add_mhuf(T, "objectiveCost_HUF", "objectiveCost_MHUF");
        T = local_add_mhuf(T, "energyCost_HUF", "energyCost_MHUF");
        T = local_add_mhuf(T, "degradationCost_HUF", "degradationCost_MHUF");
        T = local_add_mhuf(T, "energyCostSaving_HUF", "energyCostSaving_MHUF");

        if ismember('gridImportNoBess_MWh', T.Properties.VariableNames) && ...
           ismember('gridImport_MWh', T.Properties.VariableNames)

            T.gridImportReduction_MWh = ...
                T.gridImportNoBess_MWh - T.gridImport_MWh;

            T.gridImportReduction_pct = ...
                100 * T.gridImportReduction_MWh ./ T.gridImportNoBess_MWh;
        end

        if ismember('pvToLoad_MWh', T.Properties.VariableNames) && ...
           ismember('pvToBess_MWh', T.Properties.VariableNames) && ...
           ismember('pvCurtailment_MWh', T.Properties.VariableNames)

            pvUsed_MWh = T.pvToLoad_MWh + T.pvToBess_MWh;
            pvTotal_MWh = pvUsed_MWh + T.pvCurtailment_MWh;

            T.selfConsumption_pct = 100 * pvUsed_MWh ./ pvTotal_MWh;
        end

        data.(char(coupling)).candidateTable = T;
    end
end


function T = local_add_mwh(T, sourceName, targetName)

    if ismember(sourceName, T.Properties.VariableNames)
        T.(targetName) = T.(sourceName) / 1000;
    end
end


function T = local_add_mhuf(T, sourceName, targetName)

    if ismember(sourceName, T.Properties.VariableNames)
        T.(targetName) = T.(sourceName) / 1e6;
    end
end