function [figSpecs, data] = evaluation_energy_only(data, cfg, opts)
% EVALUATION_ENERGY_ONLY
%
% Energy only uzemmodhoz tartozo evaluation.
%
% Figure-ok:
%   1) Eszkozszintu vesztesegkomponensek
%   2) Grid -> BESS, BESS -> load es osszesitett energiaut-hatasfok
%   3) PV -> BESS energiaut-hatasfok
%   4) SoH, degradacios koltseg es ekvivalens ciklusszam
%   5) Koltsegkulonbsegek BESS=0-hoz kepest es energiamerleg
    close all;
    data = local_prepare_energy_only_diagnostic_columns(data, cfg);

    figSpecs = struct([]);

    % =====================================================================
    % KOZOS BEALLITASOK
    % =====================================================================

    showEnergyValues = true;
    showEfficiencyValues = true;
    showSimpleBarValues = true;

    hideZeroBess = true;
    lineStartAtOrigin = false;

    pairedBarWidth = 0.34;
    insidePairDistance = 0.95;
    pairGroupGap = 1.25;

    autoYLim = true;
    autoYMarginFrac = 0.20;

    dcColor = [0.0000 0.4470 0.7410];
    acColor = [0.8500 0.3250 0.0980];

    couplingColors = struct();
    couplingColors.dc = dcColor;
    couplingColors.ac = acColor;

    couplingLineStyles = struct();
    couplingLineStyles.dc = "-";
    couplingLineStyles.ac = "--";

    % Eszkozszintu vesztesegszinek:
    %   1) Central inverter
    %   2) DC/DC
    %   3) PCS/B
    %   4) BESS internal
    deviceColors = [ ...
        0.0000 0.4470 0.7410; ...
        0.4660 0.6740 0.1880; ...
        0.9290 0.6940 0.1250; ...
        0.6350 0.0780 0.1840];

    % Energiaut abra szinek:
    %   1) Hasznos energia
    %   2) Veszteseg
    dcPathColors = [ ...
        0.0000 0.4470 0.7410; ...
        0.8500 0.1000 0.1000];

    acPathColors = [ ...
        0.3010 0.7450 0.9330; ...
        0.9290 0.6940 0.1250];

    efficiencyLineColors = [ ...
        0.0000 0.4470 0.7410; ...
        0.8500 0.3250 0.0980];

    costColors = [ ...
        0.0000 0.4470 0.7410; ...
        0.4660 0.6740 0.1880; ...
        0.9290 0.6940 0.1250; ...
        0.6350 0.0780 0.1840];

    energyBalanceColors = [ ...
        0.0000 0.4470 0.7410; ...
        0.4660 0.6740 0.1880; ...
        0.9290 0.6940 0.1250; ...
        0.8500 0.1000 0.1000; ...
        0.6350 0.0780 0.1840];

    % =====================================================================
    % FIGURE 1 - DEVICE LEVEL LOSS COMPONENTS
    % =====================================================================
    figSpecs(1).name = "energy_only_loss_components";
    figSpecs(1).layout = [2 1];

    figSpecs(1).plots(1).type = "paired_stacked_bar";
    figSpecs(1).plots(1).y = [
        "centralInverterLoss_MWh"
        "dcdcLoss_MWh"
        "pcsbLoss_MWh"
        "bessInternalLoss_MWh"
    ];
    figSpecs(1).plots(1).labels = [
        "Central inverter"
        "DC/DC"
        "PCS/B"
        "BESS internal"
    ];
    figSpecs(1).plots(1).colorsDc = deviceColors;
    figSpecs(1).plots(1).colorsAc = deviceColors;
    figSpecs(1).plots(1).title = "AC/DC eszkozszintu vesztesegkomponensek abszolut ertekben";
    figSpecs(1).plots(1).ylabel = "Veszteseg [MWh]";
    figSpecs(1).plots(1).legend = "eastoutside";
    figSpecs(1).plots(1).showValues = showEnergyValues;
    figSpecs(1).plots(1).valueFmt = "%.1f";
    figSpecs(1).plots(1).hideZeroBess = hideZeroBess;
    figSpecs(1).plots(1).pairedBarWidth = pairedBarWidth;
    figSpecs(1).plots(1).insidePairDistance = insidePairDistance;
    figSpecs(1).plots(1).pairGroupGap = pairGroupGap;
    figSpecs(1).plots(1).autoYLim = autoYLim;
    figSpecs(1).plots(1).autoYMarginFrac = autoYMarginFrac;

    figSpecs(1).plots(2).type = "line";
    figSpecs(1).plots(2).x = "E_BESS_kWh";
    figSpecs(1).plots(2).y = [
        "centralInverterLoss_pct"
        "dcdcLoss_pct"
        "pcsbLoss_pct"
        "bessInternalLoss_pct"
    ];
    figSpecs(1).plots(2).labels = [
        "Central inverter"
        "DC/DC"
        "PCS/B"
        "BESS internal"
    ];
    figSpecs(1).plots(2).colors = deviceColors;
    figSpecs(1).plots(2).lineStylesByCoupling = couplingLineStyles;
    figSpecs(1).plots(2).title = "Eszkozszintu vesztesegreszaranyok a teljes vesztesegen belul";
    figSpecs(1).plots(2).xlabel = "BESS kapacitas [kWh]";
    figSpecs(1).plots(2).ylabel = "Reszarany [%]";
    figSpecs(1).plots(2).legend = "eastoutside";
    figSpecs(1).plots(2).showValues = false;
    figSpecs(1).plots(2).hideZeroBess = true;
    figSpecs(1).plots(2).autoYLim = true;
    figSpecs(1).plots(2).autoYMarginFrac = 0.20;

    % =====================================================================
    % FIGURE 2 - GRID -> BESS AND BESS -> LOAD EFFICIENCY
    % =====================================================================
    figSpecs(2).name = "energy_only_grid_and_bess_path_efficiency";
    figSpecs(2).layout = [3 1];

    figSpecs(2).plots(1).type = "paired_stacked_bar_line";
    figSpecs(2).plots(1).y = [
        "gridToBessStored_MWh"
        "gridToBessLoss_MWh"
    ];
    figSpecs(2).plots(1).labels = [
        "Tenylegesen eltarolt energia"
        "Toltesi veszteseg"
    ];
    figSpecs(2).plots(1).lineY = "gridToBessChargeEfficiency_pct";
    figSpecs(2).plots(1).lineLabels = "Hatasfok";
    figSpecs(2).plots(1).colorsDc = dcPathColors;
    figSpecs(2).plots(1).colorsAc = acPathColors;
    figSpecs(2).plots(1).lineColorsByCoupling = efficiencyLineColors;
    figSpecs(2).plots(1).separateLinesByCoupling = true;
    figSpecs(2).plots(1).title = "Grid -> BESS toltes: importalt energia, eltarolt energia es hatasfok";
    figSpecs(2).plots(1).ylabel = "Energia [MWh]";
    figSpecs(2).plots(1).rightylabel = "Hatasfok [%]";
    figSpecs(2).plots(1).rightAxis = true;
    figSpecs(2).plots(1).legend = "eastoutside";
    figSpecs(2).plots(1).showValues = showEnergyValues;
    figSpecs(2).plots(1).showLineValues = showEfficiencyValues;
    figSpecs(2).plots(1).valueFmt = "%.1f";
    figSpecs(2).plots(1).lineValueFmt = "%.1f %%";
    figSpecs(2).plots(1).hideZeroBess = hideZeroBess;
    figSpecs(2).plots(1).lineStartAtOrigin = lineStartAtOrigin;
    figSpecs(2).plots(1).pairedBarWidth = pairedBarWidth;
    figSpecs(2).plots(1).insidePairDistance = insidePairDistance;
    figSpecs(2).plots(1).pairGroupGap = pairGroupGap;
    figSpecs(2).plots(1).autoYLim = autoYLim;
    figSpecs(2).plots(1).autoYMarginFrac = autoYMarginFrac;

    figSpecs(2).plots(2).type = "paired_stacked_bar_line";
    figSpecs(2).plots(2).y = [
        "bessToLoad_MWh"
        "bessToLoadConversionLoss_MWh"
    ];
    figSpecs(2).plots(2).labels = [
        "Fogyasztora juto BESS energia"
        "Kisutesi ut veszteseg"
    ];
    figSpecs(2).plots(2).lineY = "bessDischargeToLoadEfficiency_pct";
    figSpecs(2).plots(2).lineLabels = "Hatasfok";
    figSpecs(2).plots(2).colorsDc = dcPathColors;
    figSpecs(2).plots(2).colorsAc = acPathColors;
    figSpecs(2).plots(2).lineColorsByCoupling = efficiencyLineColors;
    figSpecs(2).plots(2).separateLinesByCoupling = true;
    figSpecs(2).plots(2).title = "BESS kisutes: konverzio elotti energia, fogyasztora juto energia es hatasfok";
    figSpecs(2).plots(2).ylabel = "Energia [MWh]";
    figSpecs(2).plots(2).rightylabel = "Hatasfok [%]";
    figSpecs(2).plots(2).rightAxis = true;
    figSpecs(2).plots(2).legend = "eastoutside";
    figSpecs(2).plots(2).showValues = showEnergyValues;
    figSpecs(2).plots(2).showLineValues = showEfficiencyValues;
    figSpecs(2).plots(2).valueFmt = "%.1f";
    figSpecs(2).plots(2).lineValueFmt = "%.1f %%";
    figSpecs(2).plots(2).hideZeroBess = hideZeroBess;
    figSpecs(2).plots(2).lineStartAtOrigin = lineStartAtOrigin;
    figSpecs(2).plots(2).pairedBarWidth = pairedBarWidth;
    figSpecs(2).plots(2).insidePairDistance = insidePairDistance;
    figSpecs(2).plots(2).pairGroupGap = pairGroupGap;
    figSpecs(2).plots(2).autoYLim = autoYLim;
    figSpecs(2).plots(2).autoYMarginFrac = autoYMarginFrac;

    figSpecs(2).plots(3).type = "line";
    figSpecs(2).plots(3).x = "E_BESS_kWh";
    figSpecs(2).plots(3).y = "gridToBessToLoadEfficiency_pct";
    figSpecs(2).plots(3).labels = "Osszesitett hatasfok";
    figSpecs(2).plots(3).lineColorsByCoupling = couplingColors;
    figSpecs(2).plots(3).lineStylesByCoupling = couplingLineStyles;
    figSpecs(2).plots(3).title = "Osszesitett energiaut-hatasfok: toltesi hatasfok x kisutesi hatasfok";
    figSpecs(2).plots(3).xlabel = "BESS kapacitas [kWh]";
    figSpecs(2).plots(3).ylabel = "Osszesitett hatasfok [%]";
    figSpecs(2).plots(3).legend = "eastoutside";
    figSpecs(2).plots(3).showValues = true;
    figSpecs(2).plots(3).valueFmt = "%.1f%%";
    figSpecs(2).plots(3).hideZeroBess = true;
    figSpecs(2).plots(3).autoYLim = false;
    figSpecs(2).plots(3).yLim = [80 100];

    % =====================================================================
    % FIGURE 3 - PV -> BESS EFFICIENCY
    % =====================================================================
    figSpecs(3).name = "energy_only_pv_to_bess_efficiency";
    figSpecs(3).layout = [1 1];

    figSpecs(3).plots(1).type = "paired_stacked_bar_line";
    figSpecs(3).plots(1).y = [
        "pvToBessStored_MWh"
        "pvToBessLoss_MWh"
    ];
    figSpecs(3).plots(1).labels = [
        "Tenylegesen eltarolt PV energia"
        "PV -> BESS veszteseg"
    ];
    figSpecs(3).plots(1).lineY = "pvToBessChargeEfficiency_pct";
    figSpecs(3).plots(1).lineLabels = "Hatasfok";
    figSpecs(3).plots(1).colorsDc = dcPathColors;
    figSpecs(3).plots(1).colorsAc = acPathColors;
    figSpecs(3).plots(1).lineColorsByCoupling = efficiencyLineColors;
    figSpecs(3).plots(1).separateLinesByCoupling = true;
    figSpecs(3).plots(1).title = "PV -> BESS: PV energia, tenylegesen eltarolt energia es hatasfok";
    figSpecs(3).plots(1).ylabel = "Energia [MWh]";
    figSpecs(3).plots(1).rightylabel = "Hatasfok [%]";
    figSpecs(3).plots(1).rightAxis = true;
    figSpecs(3).plots(1).legend = "eastoutside";
    figSpecs(3).plots(1).showValues = showEnergyValues;
    figSpecs(3).plots(1).showLineValues = showEfficiencyValues;
    figSpecs(3).plots(1).valueFmt = "%.1f";
    figSpecs(3).plots(1).lineValueFmt = "%.1f %%";
    figSpecs(3).plots(1).hideZeroBess = hideZeroBess;
    figSpecs(3).plots(1).lineStartAtOrigin = lineStartAtOrigin;
    figSpecs(3).plots(1).pairedBarWidth = pairedBarWidth;
    figSpecs(3).plots(1).insidePairDistance = insidePairDistance;
    figSpecs(3).plots(1).pairGroupGap = pairGroupGap;
    figSpecs(3).plots(1).autoYLim = autoYLim;
    figSpecs(3).plots(1).autoYMarginFrac = autoYMarginFrac;

    % =====================================================================
    % FIGURE 4 - SOH, DEGRADATION, EQUIVALENT CYCLES
    % =====================================================================
    figSpecs(4).name = "energy_only_soh_degradation_cycles";
    figSpecs(4).layout = [3 1];

    figSpecs(4).plots(1).type = "line";
    figSpecs(4).plots(1).x = "E_BESS_kWh";
    figSpecs(4).plots(1).y = "finalSoH_pct";
    figSpecs(4).plots(1).labels = "Final SoH";
    figSpecs(4).plots(1).lineColorsByCoupling = couplingColors;
    figSpecs(4).plots(1).lineStylesByCoupling = couplingLineStyles;
    figSpecs(4).plots(1).title = "FinalSoH a teljes szimulalt idoszak vegen";
    figSpecs(4).plots(1).xlabel = "BESS kapacitas [kWh]";
    figSpecs(4).plots(1).ylabel = "Final SoH [%]";
    figSpecs(4).plots(1).legend = "eastoutside";
    figSpecs(4).plots(1).showValues = true;
    figSpecs(4).plots(1).valueFmt = "%.2f%%";
    figSpecs(4).plots(1).hideZeroBess = true;
    figSpecs(4).plots(1).autoYLim = true;
    figSpecs(4).plots(1).autoYMarginFrac = 0.20;

    figSpecs(4).plots(2).type = "line";
    figSpecs(4).plots(2).x = "E_BESS_kWh";
    figSpecs(4).plots(2).y = "correctedDegradationCost_MHUF";
    figSpecs(4).plots(2).labels = "Degradacios koltseg";
    figSpecs(4).plots(2).lineColorsByCoupling = couplingColors;
    figSpecs(4).plots(2).lineStylesByCoupling = couplingLineStyles;
    figSpecs(4).plots(2).title = "Korrigalt BESS degradacios koltseg";
    figSpecs(4).plots(2).xlabel = "BESS kapacitas [kWh]";
    figSpecs(4).plots(2).ylabel = "Degradacios koltseg [M HUF]";
    figSpecs(4).plots(2).legend = "eastoutside";
    figSpecs(4).plots(2).showValues = true;
    figSpecs(4).plots(2).valueFmt = "%.1f";
    figSpecs(4).plots(2).hideZeroBess = true;
    figSpecs(4).plots(2).autoYLim = true;
    figSpecs(4).plots(2).autoYMarginFrac = 0.20;

    figSpecs(4).plots(3).type = "line";
    figSpecs(4).plots(3).x = "E_BESS_kWh";
    figSpecs(4).plots(3).y = "equivalentCycles";
    figSpecs(4).plots(3).labels = "Ekvivalens ciklusszam";
    figSpecs(4).plots(3).lineColorsByCoupling = couplingColors;
    figSpecs(4).plots(3).lineStylesByCoupling = couplingLineStyles;
    figSpecs(4).plots(3).title = "Ekvivalens ciklusszam a vizsgalt idoszakban";
    figSpecs(4).plots(3).xlabel = "BESS kapacitas [kWh]";
    figSpecs(4).plots(3).ylabel = "Ekvivalens ciklusszam [-]";
    figSpecs(4).plots(3).legend = "eastoutside";
    figSpecs(4).plots(3).showValues = true;
    figSpecs(4).plots(3).valueFmt = "%.1f";
    figSpecs(4).plots(3).hideZeroBess = true;
    figSpecs(4).plots(3).autoYLim = true;
    figSpecs(4).plots(3).autoYMarginFrac = 0.20;

    % =====================================================================
    % FIGURE 5 - SAVINGS VS BESS=0 AND NET VALUE
    % =====================================================================
    figSpecs(5).name = "energy_only_savings_and_net_value";
    figSpecs(5).layout = [2 1];

    % ---------------------------------------------------------------------
    % 5/A - Cost differences relative to BESS = 0
    %
    % Positive value:
    %   the BESS case is cheaper than the BESS = 0 reference.
    %
    % Negative value:
    %   the BESS case is more expensive than the BESS = 0 reference.
    %
    % Important:
    %   This is a signed stacked bar. The zero level must be visually centered,
    %   therefore symmetricYLimAroundZero = true.
    % ---------------------------------------------------------------------
    figSpecs(5).plots(1).type = "paired_stacked_bar";
    figSpecs(5).plots(1).y = [
        "energyCostSavingVsZero_MHUF"
        "contractCostSavingVsZero_MHUF"
        "overrunCostSavingVsZero_MHUF"
        "degradationCostSavingVsZero_MHUF"
    ];
    figSpecs(5).plots(1).labels = [
        "Energy cost"
        "Contract cost"
        "Overrun cost"
        "Degradation cost"
    ];

    figSpecs(5).plots(1).colorsDc = costColors;
    figSpecs(5).plots(1).colorsAc = costColors;

    figSpecs(5).plots(1).title = "Koltsegkulonbsegek BESS = 0 esethez kepest";
    figSpecs(5).plots(1).ylabel = "Koltsegkulonbseg [M HUF]";
    figSpecs(5).plots(1).legend = "eastoutside";

    figSpecs(5).plots(1).showValues = true;
    figSpecs(5).plots(1).valueFmt = "%.1f";
    figSpecs(5).plots(1).zeroLine = true;

    figSpecs(5).plots(1).hideZeroBess = true;
    figSpecs(5).plots(1).pairedBarWidth = pairedBarWidth;
    figSpecs(5).plots(1).insidePairDistance = insidePairDistance;
    figSpecs(5).plots(1).pairGroupGap = pairGroupGap;

    figSpecs(5).plots(1).autoYLim = true;
    figSpecs(5).plots(1).autoYMarginFrac = 0.20;

    % Signed stacked bar beallitasok.
    figSpecs(5).plots(1).includeZeroInYLim = true;
    figSpecs(5).plots(1).forceZeroBottom = false;
    figSpecs(5).plots(1).symmetricYLimAroundZero = true;

    % ---------------------------------------------------------------------
    % 5/B - Net value / NPV-like value over the investigated period
    %
    % This is the sum of the signed cost components above:
    %
    %   net = energy saving
    %       + contract saving
    %       + overrun saving
    %       + degradation saving
    %
    % Positive value:
    %   economically better than BESS = 0 over the investigated period.
    %
    % Negative value:
    %   economically worse than BESS = 0 over the investigated period.
    % ---------------------------------------------------------------------
    figSpecs(5).plots(2).type = "line";
    figSpecs(5).plots(2).x = "E_BESS_kWh";
    figSpecs(5).plots(2).y = "netSavingVsZero_MHUF";
    figSpecs(5).plots(2).labels = "Net saving";

    figSpecs(5).plots(2).lineColorsByCoupling = couplingColors;
    figSpecs(5).plots(2).lineStylesByCoupling = couplingLineStyles;

    figSpecs(5).plots(2).title = "Netto megtakaritas BESS = 0 esethez kepest a vizsgalt idoszakban";
    figSpecs(5).plots(2).xlabel = "BESS kapacitas [kWh]";
    figSpecs(5).plots(2).ylabel = "Netto megtakaritas [M HUF]";
    figSpecs(5).plots(2).legend = "eastoutside";

    figSpecs(5).plots(2).showValues = true;
    figSpecs(5).plots(2).valueFmt = "%.1f";

    figSpecs(5).plots(2).hideZeroBess = true;
    figSpecs(5).plots(2).autoYLim = true;
    figSpecs(5).plots(2).autoYMarginFrac = 0.20;
    figSpecs(5).plots(2).zeroLine = true;
end

function data = local_prepare_energy_only_diagnostic_columns(data, cfg)

    couplings = ["dc", "ac"];

    for c = 1:numel(couplings)

        coupling = couplings(c);

        if ~isfield(data, char(coupling)) || ...
           ~isfield(data.(char(coupling)), 'candidateTable')
            continue;
        end

        T = data.(char(coupling)).candidateTable;

        % -----------------------------------------------------------------
        % Direction-specific base losses [MWh]
        % -----------------------------------------------------------------
        T.centralInvDcToAcLoss_MWh = max(T.centralInvDcToAcLoss_kWh, 0) / 1000;
        T.centralInvAcToDcLoss_MWh = max(T.centralInvAcToDcLoss_kWh, 0) / 1000;

        T.dcdcChargeLoss_MWh = max(T.dcdcChargeLoss_kWh, 0) / 1000;
        T.dcdcDischargeLoss_MWh = max(T.dcdcDischargeLoss_kWh, 0) / 1000;

        T.pcsbChargeLoss_MWh = max(T.pcsbChargeLoss_kWh, 0) / 1000;
        T.pcsbDischargeLoss_MWh = max(T.pcsbDischargeLoss_kWh, 0) / 1000;

        T.bessInternalChargeLoss_MWh = max(T.bessInternalChargeLoss_kWh, 0) / 1000;
        T.bessInternalDischargeLoss_MWh = max(T.bessInternalDischargeLoss_kWh, 0) / 1000;

        % -----------------------------------------------------------------
        % Device-level losses [MWh]
        % -----------------------------------------------------------------
        T.centralInverterLoss_MWh = ...
            T.centralInvDcToAcLoss_MWh + ...
            T.centralInvAcToDcLoss_MWh;

        T.dcdcLoss_MWh = ...
            T.dcdcChargeLoss_MWh + ...
            T.dcdcDischargeLoss_MWh;

        T.pcsbLoss_MWh = ...
            T.pcsbChargeLoss_MWh + ...
            T.pcsbDischargeLoss_MWh;

        T.bessInternalLoss_MWh = ...
            T.bessInternalChargeLoss_MWh + ...
            T.bessInternalDischargeLoss_MWh;

        deviceLossMatrix_MWh = [ ...
            T.centralInverterLoss_MWh, ...
            T.dcdcLoss_MWh, ...
            T.pcsbLoss_MWh, ...
            T.bessInternalLoss_MWh];

        totalDeviceLoss_MWh = sum(deviceLossMatrix_MWh, 2);

        lossPct = zeros(size(deviceLossMatrix_MWh));
        validLoss = totalDeviceLoss_MWh > 1e-12;

        lossPct(validLoss, :) = ...
            100 * deviceLossMatrix_MWh(validLoss, :) ./ totalDeviceLoss_MWh(validLoss);

        T.centralInverterLoss_pct = lossPct(:, 1);
        T.dcdcLoss_pct = lossPct(:, 2);
        T.pcsbLoss_pct = lossPct(:, 3);
        T.bessInternalLoss_pct = lossPct(:, 4);

        T.totalLoss_MWh = totalDeviceLoss_MWh;

        % -----------------------------------------------------------------
        % Energy path quantities [MWh]
        % -----------------------------------------------------------------
        T.gridImport_MWh = T.gridImport_kWh / 1000;
        T.gridToBess_MWh = T.gridToBess_kWh / 1000;
        T.gridToBessStored_MWh = T.gridToBessStored_kWh / 1000;
        T.gridToBessLoss_MWh = max(T.gridToBess_MWh - T.gridToBessStored_MWh, 0);

        T.pvToBess_MWh = T.pvToBess_kWh / 1000;
        T.pvToBessStored_MWh = T.pvToBessStored_kWh / 1000;
        T.pvToBessLoss_MWh = max(T.pvToBess_MWh - T.pvToBessStored_MWh, 0);

        T.pvToLoad_MWh = T.pvToLoad_kWh / 1000;
        T.bessToLoad_MWh = T.bessToLoad_kWh / 1000;
        T.curtailment_MWh = T.curtailment_kWh / 1000;

        T.gridToLoad_MWh = max(T.gridImport_MWh - T.gridToBess_MWh, 0);

        T.bessDischargeBeforeConversion_MWh = ...
            T.bessDischargeBeforeConversion_kWh / 1000;

        T.bessToLoadConversionLoss_MWh = ...
            max(T.bessDischargeBeforeConversion_MWh - T.bessToLoad_MWh, 0);

        % -----------------------------------------------------------------
        % Efficiencies [%]
        % -----------------------------------------------------------------
        T.gridToBessChargeEfficiency_pct = ...
            local_eff_percent(T.gridToBessStored_MWh, T.gridToBess_MWh);

        T.pvToBessChargeEfficiency_pct = ...
            local_eff_percent(T.pvToBessStored_MWh, T.pvToBess_MWh);

        T.bessDischargeToLoadEfficiency_pct = ...
            local_eff_percent(T.bessToLoad_MWh, T.bessDischargeBeforeConversion_MWh);

        T.gridToBessToLoadEfficiency_pct = ...
            T.gridToBessChargeEfficiency_pct .* ...
            T.bessDischargeToLoadEfficiency_pct / 100;

        T.pvToBessToLoadEfficiency_pct = ...
            T.pvToBessChargeEfficiency_pct .* ...
            T.bessDischargeToLoadEfficiency_pct / 100;

        % -----------------------------------------------------------------
        % SoH and degradation
        % -----------------------------------------------------------------
        if ~ismember('finalSoH_pct', T.Properties.VariableNames)
            T.finalSoH_pct = 100 * T.finalSoH;
        end

        capex_HUF = ...
            T.E_BESS_kWh .* cfg.cost.bess_huf_per_kWh + ...
            T.P_BESS_kW .* cfg.cost.bess_power_huf_per_kW;

        if isfield(cfg.cost, 'bess_eol_soh_window')
            eolWindow = cfg.cost.bess_eol_soh_window;
        else
            eolWindow = 0.2;
        end

        T.correctedDegradationCost_MHUF = ...
            max(0, (1 - T.finalSoH) ./ eolWindow) .* capex_HUF / 1e6;

        % -----------------------------------------------------------------
        % Cost differences relative to BESS = 0
        %
        % Positive value = saving compared to BESS = 0.
        % Negative value = extra cost compared to BESS = 0.
        % -----------------------------------------------------------------
        idxZero = find(abs(T.E_BESS_kWh) <= 1e-12, 1, 'first');

        if isempty(idxZero)
            idxZero = 1;
        end

        T.energyCost_MHUF = T.energyCost_HUF / 1e6;
        T.degradationCost_MHUF = T.degradationCost_HUF / 1e6;
        T.objectiveCost_MHUF = T.objectiveCost_HUF / 1e6;

        if ismember('contractCost_HUF', T.Properties.VariableNames)
            T.contractCost_MHUF = T.contractCost_HUF / 1e6;
        else
            T.contractCost_MHUF = zeros(height(T), 1);
        end

        if ismember('overrunCost_HUF', T.Properties.VariableNames)
            T.overrunCost_MHUF = T.overrunCost_HUF / 1e6;
        else
            T.overrunCost_MHUF = zeros(height(T), 1);
        end

        T.energyCostSavingVsZero_MHUF = ...
            T.energyCost_MHUF(idxZero) - T.energyCost_MHUF;

        T.contractCostSavingVsZero_MHUF = ...
            T.contractCost_MHUF(idxZero) - T.contractCost_MHUF;

        T.overrunCostSavingVsZero_MHUF = ...
            T.overrunCost_MHUF(idxZero) - T.overrunCost_MHUF;

        T.degradationCostSavingVsZero_MHUF = ...
            T.degradationCost_MHUF(idxZero) - T.degradationCost_MHUF;

        T.objectiveCostSavingVsZero_MHUF = ...
            T.objectiveCost_MHUF(idxZero) - T.objectiveCost_MHUF;

        % -----------------------------------------------------------------
        % Net saving / NPV-like value relative to BESS = 0.
        %
        % Positive value:
        %   the BESS case is economically better than the BESS = 0 case.
        %
        % Negative value:
        %   the BESS case is economically worse than the BESS = 0 case.
        %
        % This value is calculated from the same signed components that are
        % displayed in the stacked cost-difference figure.
        % -----------------------------------------------------------------
        T.netSavingVsZero_MHUF = ...
            T.energyCostSavingVsZero_MHUF + ...
            T.contractCostSavingVsZero_MHUF + ...
            T.overrunCostSavingVsZero_MHUF + ...
            T.degradationCostSavingVsZero_MHUF;

        data.(char(coupling)).candidateTable = T;
    end
end


function eff = local_eff_percent(numerator, denominator)

    numerator = numerator(:);
    denominator = denominator(:);

    eff = NaN(size(numerator));

    valid = denominator > 1e-12;
    eff(valid) = 100 * numerator(valid) ./ denominator(valid);

    eff = min(max(eff, 0), 100);
end