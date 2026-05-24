function [figSpecs, data] = evaluation_combined(data, cfg, opts)
% EVALUATION_COMBINED
%
% Combined uzemmodhoz tartozo dolgozati kiertekeles.
%
% Combined = peak shaving + energy arbitrage.
%
% Csak a create_configurations.m alapjan letezo mentett mezoket,
% illetve azokbol itt szarmaztatott mezoket hasznal.

    data = local_add_combined_derived_columns(data);

    figSpecs = struct([]);

    % =====================================================================
    % FIGURE 1 - Combined technical overview
    % =====================================================================
    figSpecs(1).name = "combined_technical_overview";
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
    figSpecs(1).plots(2).y = "gridImportReduction_MWh";
    figSpecs(1).plots(2).title = "Grid import reduction";
    figSpecs(1).plots(2).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(1).plots(2).ylabel = "Energy [MWh]";
    figSpecs(1).plots(2).legend = "best";
    figSpecs(1).plots(2).values = true;
    figSpecs(1).plots(2).valueFmt = "%.1f";

    figSpecs(1).plots(3).type = "grouped_bar";
    figSpecs(1).plots(3).x = "BESS_PV_ratio";
    figSpecs(1).plots(3).y = "peakReduction_pct";
    figSpecs(1).plots(3).title = "Peak reduction";
    figSpecs(1).plots(3).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(1).plots(3).ylabel = "Peak reduction [%]";
    figSpecs(1).plots(3).legend = "best";
    figSpecs(1).plots(3).values = true;
    figSpecs(1).plots(3).valueFmt = "%.1f";

    figSpecs(1).plots(4).type = "line";
    figSpecs(1).plots(4).x = "BESS_PV_ratio";
    figSpecs(1).plots(4).y = [
        "finalSoH_pct"
        "equivalentCycles"
    ];
    figSpecs(1).plots(4).labels = [
        "Final SoH [%]"
        "Equivalent cycles"
    ];
    figSpecs(1).plots(4).title = "Battery aging indicators";
    figSpecs(1).plots(4).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(1).plots(4).ylabel = "Value";
    figSpecs(1).plots(4).legend = "best";

    % =====================================================================
    % FIGURE 2 - Combined cost overview
    % =====================================================================
    figSpecs(2).name = "combined_cost_overview";
    figSpecs(2).layout = [2 2];

    figSpecs(2).plots(1).type = "stacked_bar_line";
    figSpecs(2).plots(1).x = "BESS_PV_ratio";
    figSpecs(2).plots(1).y = [
        "energyCost_MHUF"
        "contractCost_MHUF"
        "overrunCost_MHUF"
        "degradationCost_MHUF"
    ];
    figSpecs(2).plots(1).labels = [
        "Energy cost"
        "Contract cost"
        "Overrun cost"
        "Degradation cost"
    ];
    figSpecs(2).plots(1).lineY = "objectiveCost_MHUF";
    figSpecs(2).plots(1).lineLabels = "Objective";
    figSpecs(2).plots(1).title = "Combined cost components and objective";
    figSpecs(2).plots(1).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(2).plots(1).ylabel = "Cost [million HUF]";
    figSpecs(2).plots(1).legend = "best";

    figSpecs(2).plots(2).type = "signed_stacked_bar_line";
    figSpecs(2).plots(2).x = "BESS_PV_ratio";
    figSpecs(2).plots(2).y = [
        "energyCostSaving_MHUF"
        "degradationCost_MHUF"
    ];
    figSpecs(2).plots(2).signs = [1 -1];
    figSpecs(2).plots(2).labels = [
        "Energy saving"
        "Degradation cost"
    ];
    figSpecs(2).plots(2).lineY = "objectiveCost_MHUF";
    figSpecs(2).plots(2).lineLabels = "Objective";
    figSpecs(2).plots(2).title = "Combined value components";
    figSpecs(2).plots(2).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(2).plots(2).ylabel = "Value [million HUF]";
    figSpecs(2).plots(2).zeroLine = true;
    figSpecs(2).plots(2).legend = "best";

    figSpecs(2).plots(3).type = "grouped_bar";
    figSpecs(2).plots(3).x = "BESS_PV_ratio";
    figSpecs(2).plots(3).y = "objectiveCost_MHUF";
    figSpecs(2).plots(3).title = "Objective cost";
    figSpecs(2).plots(3).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(2).plots(3).ylabel = "Cost [million HUF]";
    figSpecs(2).plots(3).legend = "best";
    figSpecs(2).plots(3).values = true;
    figSpecs(2).plots(3).valueFmt = "%.1f";

    figSpecs(2).plots(4).type = "scatter";
    figSpecs(2).plots(4).x = "E_BESS_kWh";
    figSpecs(2).plots(4).y = "objectiveCost_MHUF";
    figSpecs(2).plots(4).title = "Objective cost by BESS capacity";
    figSpecs(2).plots(4).xlabel = "BESS capacity [kWh]";
    figSpecs(2).plots(4).ylabel = "Objective cost [million HUF]";
    figSpecs(2).plots(4).legend = "best";

    % =====================================================================
    % FIGURE 3 - Combined energy flow overview
    % =====================================================================
    figSpecs(3).name = "combined_energy_flow_overview";
    figSpecs(3).layout = [2 2];

    figSpecs(3).plots(1).type = "stacked_bar_line";
    figSpecs(3).plots(1).x = "BESS_PV_ratio";
    figSpecs(3).plots(1).y = [
        "gridToBess_MWh"
        "pvToBess_MWh"
        "bessChargeLoss_MWh"
    ];
    figSpecs(3).plots(1).labels = [
        "Grid to BESS"
        "PV to BESS"
        "Charge loss"
    ];
    figSpecs(3).plots(1).lineY = "bessStoredActual_MWh";
    figSpecs(3).plots(1).lineLabels = "Stored actual";
    figSpecs(3).plots(1).title = "BESS charging energy and stored energy";
    figSpecs(3).plots(1).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(3).plots(1).ylabel = "Energy [MWh]";
    figSpecs(3).plots(1).legend = "best";

    figSpecs(3).plots(2).type = "stacked_bar";
    figSpecs(3).plots(2).x = "BESS_PV_ratio";
    figSpecs(3).plots(2).y = [
        "pvToLoad_MWh"
        "pvToBess_MWh"
        "curtailment_MWh"
    ];
    figSpecs(3).plots(2).labels = [
        "PV to load"
        "PV to BESS"
        "Curtailment"
    ];
    figSpecs(3).plots(2).title = "PV energy distribution";
    figSpecs(3).plots(2).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(3).plots(2).ylabel = "Energy [MWh]";
    figSpecs(3).plots(2).legend = "best";

    figSpecs(3).plots(3).type = "grouped_bar";
    figSpecs(3).plots(3).x = "BESS_PV_ratio";
    figSpecs(3).plots(3).y = "gridImport_MWh";
    figSpecs(3).plots(3).title = "Grid import";
    figSpecs(3).plots(3).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(3).plots(3).ylabel = "Energy [MWh]";
    figSpecs(3).plots(3).legend = "best";
    figSpecs(3).plots(3).values = true;
    figSpecs(3).plots(3).valueFmt = "%.1f";

    figSpecs(3).plots(4).type = "line";
    figSpecs(3).plots(4).x = "BESS_PV_ratio";
    figSpecs(3).plots(4).y = [
        "selfConsumption_pct"
        "gridImportReduction_pct"
        "peakReduction_pct"
    ];
    figSpecs(3).plots(4).labels = [
        "Self-consumption"
        "Grid import reduction"
        "Peak reduction"
    ];
    figSpecs(3).plots(4).title = "Combined performance indicators";
    figSpecs(3).plots(4).xlabel = "BESS/PV ratio [kWh/kWp]";
    figSpecs(3).plots(4).ylabel = "Ratio [%]";
    figSpecs(3).plots(4).legend = "best";
end


function data = local_add_combined_derived_columns(data)

    couplings = string(fieldnames(data));

    for i = 1:numel(couplings)

        coupling = couplings(i);

        if ~isfield(data.(char(coupling)), 'candidateTable')
            continue;
        end

        T = data.(char(coupling)).candidateTable;

        T.gridImport_MWh = T.gridImport_kWh / 1000;
        T.gridImportNoBess_MWh = T.gridImportNoBess_kWh / 1000;

        T.gridToBess_MWh = T.gridToBess_kWh / 1000;
        T.gridToBessStored_MWh = T.gridToBessStored_kWh / 1000;
        T.gridToBessLoss_MWh = T.gridToBessLoss_kWh / 1000;

        T.pvToBess_MWh = T.pvToBess_kWh / 1000;
        T.pvToBessStored_MWh = T.pvToBessStored_kWh / 1000;
        T.pvToBessLoss_MWh = T.pvToBessLoss_kWh / 1000;

        T.pvToLoad_MWh = T.pvToLoad_kWh / 1000;
        T.bessToLoad_MWh = T.bessToLoad_kWh / 1000;
        T.curtailment_MWh = T.curtailment_kWh / 1000;

        T.bessChargeLoss_MWh = ...
            T.gridToBessLoss_MWh + T.pvToBessLoss_MWh;

        T.bessStoredActual_MWh = ...
            T.gridToBessStored_MWh + T.pvToBessStored_MWh;

        T.objectiveCost_MHUF = T.objectiveCost_HUF / 1e6;
        T.energyCost_MHUF = T.energyCost_HUF / 1e6;
        T.contractCost_MHUF = T.contractCost_HUF / 1e6;
        T.overrunCost_MHUF = T.overrunCost_HUF / 1e6;
        T.degradationCost_MHUF = T.degradationCost_HUF / 1e6;
        T.energyCostSaving_MHUF = T.energyCostSaving_HUF / 1e6;

        T.gridImportReduction_MWh = T.gridImportReduction_kWh / 1000;

        pvUsed_MWh = T.pvToLoad_MWh + T.pvToBess_MWh;
        pvTotal_MWh = pvUsed_MWh + T.curtailment_MWh;

        T.selfConsumption_pct = 100 * pvUsed_MWh ./ pvTotal_MWh;

        data.(char(coupling)).candidateTable = T;
    end
end