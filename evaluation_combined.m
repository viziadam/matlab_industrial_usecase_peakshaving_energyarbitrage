function [figSpecs, data] = evaluation_combined(data, cfg, opts)
% EVALUATION_COMBINED
%
% Combined uzemmodhoz tartozo dolgozati kiertekeles.
%
% Combined = peak shaving + energy arbitrage.
%
% A figure-ok ugyanazzal a template-alapu logikaval keszulnek, mint az
% energy_only evaluation eseteben.
%
% Figure-ok:
%   1) BESS degradacio es kihasznaltsag
%   2) Megtakaritasok, BESS tobbletkoltseg es NPV
%   3) Combined muszaki mukodesi mutatok

    %#ok<INUSD>

    % ---------------------------------------------------------------------
    % Combined economic assumptions
    % ---------------------------------------------------------------------
    % Fajlagos BESS CAPEX ertekek kulon AC- es DC-csatolt BESS agra.
    % Mertekegyseg: HUF/kWh
    %
    % Ezeket itt lehet gyorsan valtoztatni erzekenysegvizsgalathoz.
    %
    % Megjegyzes:
    %   A teljesitmeny oldali CAPEX tovabbra is a
    %   cfg.cost.bess_power_huf_per_kW erteket hasznalja.
    eur_to_huf = 400;

    capexDC_eur_per_kWh = 280;
    capexAC_eur_per_kWh = 280;

    capexDc_HUF_per_kWh = capexDC_eur_per_kWh * eur_to_huf;
    capexAc_HUF_per_kWh = capexAC_eur_per_kWh * eur_to_huf;

    costPars = struct();
    costPars.capexDc_HUF_per_kWh = capexDc_HUF_per_kWh;
    costPars.capexAc_HUF_per_kWh = capexAc_HUF_per_kWh;

    data = local_prepare_combined_diagnostic_columns(data, cfg, costPars);

    figSpecs = struct([]);

    % =====================================================================
    % KOZOS BEALLITASOK
    % =====================================================================

    showValues = true;
    showLineValues = true;
    hideZeroBess = true;

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

    costColors = [ ...
        0.0000 0.4470 0.7410; ...
        0.4660 0.6740 0.1880; ...
        0.9290 0.6940 0.1250; ...
        0.6350 0.0780 0.1840; ...
        0.4940 0.1840 0.5560];

    % =====================================================================
    % FIGURE 1 - DEGRADATION, SOH, EQUIVALENT CYCLES
    % =====================================================================

    figSpecs(1).name = "combined_degradation_soh_cycles";
    figSpecs(1).layout = [3 1];

    % ---------------------------------------------------------------------
    % 1/A - Equivalent cycles
    % ---------------------------------------------------------------------
    figSpecs(1).plots(1).type = "line";
    figSpecs(1).plots(1).x = "E_BESS_kWh";
    figSpecs(1).plots(1).y = "equivalentCycles";
    figSpecs(1).plots(1).labels = "Ekvivalens ciklusszam";
    figSpecs(1).plots(1).lineColorsByCoupling = couplingColors;
    figSpecs(1).plots(1).lineStylesByCoupling = couplingLineStyles;
    figSpecs(1).plots(1).title = "Ekvivalens ciklusszam combined uzemmodban";
    figSpecs(1).plots(1).xlabel = "BESS kapacitas [kWh]";
    figSpecs(1).plots(1).ylabel = "Ekvivalens ciklusszam [-]";
    figSpecs(1).plots(1).legend = "eastoutside";
    figSpecs(1).plots(1).showValues = showValues;
    figSpecs(1).plots(1).valueFmt = "%.1f";
    figSpecs(1).plots(1).hideZeroBess = hideZeroBess;
    figSpecs(1).plots(1).autoYLim = autoYLim;
    figSpecs(1).plots(1).autoYMarginFrac = autoYMarginFrac;

    % ---------------------------------------------------------------------
    % 1/B - Final SoH
    % ---------------------------------------------------------------------
    figSpecs(1).plots(2).type = "line";
    figSpecs(1).plots(2).x = "E_BESS_kWh";
    figSpecs(1).plots(2).y = "finalSoH_pct";
    figSpecs(1).plots(2).labels = "Final SoH";
    figSpecs(1).plots(2).lineColorsByCoupling = couplingColors;
    figSpecs(1).plots(2).lineStylesByCoupling = couplingLineStyles;
    figSpecs(1).plots(2).title = "FinalSoH a teljes szimulalt idoszak vegen";
    figSpecs(1).plots(2).xlabel = "BESS kapacitas [kWh]";
    figSpecs(1).plots(2).ylabel = "Final SoH [%]";
    figSpecs(1).plots(2).legend = "eastoutside";
    figSpecs(1).plots(2).showValues = showValues;
    figSpecs(1).plots(2).valueFmt = "%.2f%%";
    figSpecs(1).plots(2).hideZeroBess = hideZeroBess;
    figSpecs(1).plots(2).autoYLim = autoYLim;
    figSpecs(1).plots(2).autoYMarginFrac = autoYMarginFrac;

    % ---------------------------------------------------------------------
    % 1/C - Cyclic and calendar degradation
    % ---------------------------------------------------------------------
    figSpecs(1).plots(3).type = "line";
    figSpecs(1).plots(3).x = "E_BESS_kWh";
    figSpecs(1).plots(3).y = [
        "finalCycleDegradationPct"
        "finalCalendarDegradationPct"
    ];
    figSpecs(1).plots(3).labels = [
        "Ciklikus degradacio"
        "Naptari degradacio"
    ];
    figSpecs(1).plots(3).colors = [
        0.0000 0.4470 0.7410
        0.8500 0.3250 0.0980
    ];
    figSpecs(1).plots(3).lineStylesByCoupling = couplingLineStyles;
    figSpecs(1).plots(3).title = "Ciklikus es naptari degradacio alakulasa";
    figSpecs(1).plots(3).xlabel = "BESS kapacitas [kWh]";
    figSpecs(1).plots(3).ylabel = "SoH-veszteseg [%]";
    figSpecs(1).plots(3).legend = "eastoutside";
    figSpecs(1).plots(3).showValues = showValues;
    figSpecs(1).plots(3).valueFmt = "%.2f%%";
    figSpecs(1).plots(3).hideZeroBess = hideZeroBess;
    figSpecs(1).plots(3).autoYLim = autoYLim;
    figSpecs(1).plots(3).autoYMarginFrac = autoYMarginFrac;

    % =====================================================================
    % FIGURE 2 - SAVINGS, ADDITIONAL COSTS, NPV
    % Ugyanaz a logika, mint energy_only esetben:
    %   - signed stacked bar
    %   - pozitiv: megtakaritas
    %   - negativ: BESS tobbletkoltseg
    %   - kulon NPV gorbe
    % =====================================================================

    figSpecs(2).name = "combined_savings_and_net_value";
    figSpecs(2).layout = [3 1];

    figSpecs(2).plots(1).type = "paired_stacked_bar";
    figSpecs(2).plots(1).y = [
        "energyCostSavingVsZero_MHUF"
        "contractCostSavingVsZero_MHUF"
        "overrunCostSavingVsZero_MHUF"
        "bessSohCapexCostVsZero_MHUF"
        "bessOpexCostVsZero_MHUF"
    ];
    figSpecs(2).plots(1).labels = [
        "Energy cost saving"
        "Contract cost saving"
        "Overrun cost saving"
        "BESS SoH CAPEX"
        "BESS OPEX"
    ];
    figSpecs(2).plots(1).colorsDc = costColors;
    figSpecs(2).plots(1).colorsAc = costColors;
    figSpecs(2).plots(1).title = "Koltsegkulonbsegek BESS = 0 esethez kepest";
    figSpecs(2).plots(1).ylabel = "Koltsegkulonbseg [M HUF]";
    figSpecs(2).plots(1).legend = "eastoutside";
    figSpecs(2).plots(1).showValues = showValues;
    figSpecs(2).plots(1).valueFmt = "%.1f";
    figSpecs(2).plots(1).zeroLine = true;
    figSpecs(2).plots(1).hideZeroBess = hideZeroBess;
    figSpecs(2).plots(1).pairedBarWidth = pairedBarWidth;
    figSpecs(2).plots(1).insidePairDistance = insidePairDistance;
    figSpecs(2).plots(1).pairGroupGap = pairGroupGap;
    figSpecs(2).plots(1).autoYLim = autoYLim;
    figSpecs(2).plots(1).autoYMarginFrac = autoYMarginFrac;
    figSpecs(2).plots(1).includeZeroInYLim = true;
    figSpecs(2).plots(1).forceZeroBottom = false;
    figSpecs(2).plots(1).symmetricYLimAroundZero = true;

    figSpecs(2).plots(2).type = "line";
    figSpecs(2).plots(2).x = "E_BESS_kWh";
    figSpecs(2).plots(2).y = "combinedPeriodNPV_MHUF";
    figSpecs(2).plots(2).labels = "NPV";
    figSpecs(2).plots(2).lineColorsByCoupling = couplingColors;
    figSpecs(2).plots(2).lineStylesByCoupling = couplingLineStyles;
    figSpecs(2).plots(2).title = "Idoszaki netto jelenertek BESS = 0 esethez kepest";
    figSpecs(2).plots(2).xlabel = "BESS kapacitas [kWh]";
    figSpecs(2).plots(2).ylabel = "Netto jelenertek [M HUF]";
    figSpecs(2).plots(2).legend = "eastoutside";
    figSpecs(2).plots(2).showValues = showValues;
    figSpecs(2).plots(2).valueFmt = "%.1f";
    figSpecs(2).plots(2).hideZeroBess = hideZeroBess;
    figSpecs(2).plots(2).autoYLim = autoYLim;
    figSpecs(2).plots(2).autoYMarginFrac = autoYMarginFrac;
    figSpecs(2).plots(2).zeroLine = true;

    figSpecs(2).plots(3).type = "line";
    figSpecs(2).plots(3).x = "E_BESS_kWh";
    figSpecs(2).plots(3).y = "marginalBenefit_MHUF_per_MWh";
    figSpecs(2).plots(3).labels = "Marginalis BESS haszon";
    figSpecs(2).plots(3).lineColorsByCoupling = couplingColors;
    figSpecs(2).plots(3).lineStylesByCoupling = couplingLineStyles;
    figSpecs(2).plots(3).title = "BESS kapacitas marginalis haszna";
    figSpecs(2).plots(3).xlabel = "BESS kapacitas [kWh]";
    figSpecs(2).plots(3).ylabel = "Marginalis haszon [M HUF/MWh]";
    figSpecs(2).plots(3).legend = "eastoutside";
    figSpecs(2).plots(3).showValues = showValues;
    figSpecs(2).plots(3).valueFmt = "%.2f";
    figSpecs(2).plots(3).hideZeroBess = true;
    figSpecs(2).plots(3).autoYLim = autoYLim;
    figSpecs(2).plots(3).autoYMarginFrac = autoYMarginFrac;
    figSpecs(2).plots(3).zeroLine = true;

    % =====================================================================
    % FIGURE 3 - COMBINED OPERATION INDICATORS
    % =====================================================================

    figSpecs(3).name = "combined_operation_indicators";
    figSpecs(3).layout = [2 2];

    % ---------------------------------------------------------------------
    % 3/A - Contracted power
    % ---------------------------------------------------------------------
    figSpecs(3).plots(1).type = "line";
    figSpecs(3).plots(1).x = "E_BESS_kWh";
    figSpecs(3).plots(1).y = "bestContract_kW";
    figSpecs(3).plots(1).labels = "Lekotott teljesitmeny";
    figSpecs(3).plots(1).lineColorsByCoupling = couplingColors;
    figSpecs(3).plots(1).lineStylesByCoupling = couplingLineStyles;
    figSpecs(3).plots(1).title = "Optimalis lekotott teljesitmeny";
    figSpecs(3).plots(1).xlabel = "BESS kapacitas [kWh]";
    figSpecs(3).plots(1).ylabel = "Lekotott teljesitmeny [kW]";
    figSpecs(3).plots(1).legend = "eastoutside";
    figSpecs(3).plots(1).showValues = showValues;
    figSpecs(3).plots(1).valueFmt = "%.0f";
    figSpecs(3).plots(1).hideZeroBess = false;
    figSpecs(3).plots(1).autoYLim = autoYLim;
    figSpecs(3).plots(1).autoYMarginFrac = autoYMarginFrac;

    % ---------------------------------------------------------------------
    % 3/B - PV utilization
    % ---------------------------------------------------------------------
    figSpecs(3).plots(2).type = "line";
    figSpecs(3).plots(2).x = "E_BESS_kWh";
    figSpecs(3).plots(2).y = "pvUtilization_pct";
    figSpecs(3).plots(2).labels = "PV hasznositas";
    figSpecs(3).plots(2).lineColorsByCoupling = couplingColors;
    figSpecs(3).plots(2).lineStylesByCoupling = couplingLineStyles;
    figSpecs(3).plots(2).title = "Teljes PV energia hasznositasa";
    figSpecs(3).plots(2).xlabel = "BESS kapacitas [kWh]";
    figSpecs(3).plots(2).ylabel = "PV hasznositas [%]";
    figSpecs(3).plots(2).legend = "eastoutside";
    figSpecs(3).plots(2).showValues = showValues;
    figSpecs(3).plots(2).valueFmt = "%.1f%%";
    figSpecs(3).plots(2).hideZeroBess = false;
    figSpecs(3).plots(2).autoYLim = autoYLim;
    figSpecs(3).plots(2).autoYMarginFrac = autoYMarginFrac;

    % ---------------------------------------------------------------------
    % 3/C - Peak-shaving effectiveness
    % ---------------------------------------------------------------------
    figSpecs(3).plots(3).type = "line";
    figSpecs(3).plots(3).x = "E_BESS_kWh";
    figSpecs(3).plots(3).y = "peakShavingEfficiency_kW_per_MWh";
    figSpecs(3).plots(3).labels = "Peak-shaving hatekonysag";
    figSpecs(3).plots(3).lineColorsByCoupling = couplingColors;
    figSpecs(3).plots(3).lineStylesByCoupling = couplingLineStyles;
    figSpecs(3).plots(3).title = "Lekotott teljesitmeny csokkenes / BESS kapacitas";
    figSpecs(3).plots(3).xlabel = "BESS kapacitas [kWh]";
    figSpecs(3).plots(3).ylabel = "kW/MWh";
    figSpecs(3).plots(3).legend = "eastoutside";
    figSpecs(3).plots(3).showValues = showValues;
    figSpecs(3).plots(3).valueFmt = "%.2f";
    figSpecs(3).plots(3).hideZeroBess = hideZeroBess;
    figSpecs(3).plots(3).autoYLim = autoYLim;
    figSpecs(3).plots(3).autoYMarginFrac = autoYMarginFrac;

    % ---------------------------------------------------------------------
    % 3/D - Energy arbitrage value intensity
    % ---------------------------------------------------------------------
    figSpecs(3).plots(4).type = "line";
    figSpecs(3).plots(4).x = "E_BESS_kWh";
    figSpecs(3).plots(4).y = "energyValuePerThroughput_HUF_per_kWh";
    figSpecs(3).plots(4).labels = "Energiaoldali ertekintenzitas";
    figSpecs(3).plots(4).lineColorsByCoupling = couplingColors;
    figSpecs(3).plots(4).lineStylesByCoupling = couplingLineStyles;
    figSpecs(3).plots(4).title = "Energiakoltseg-megtakaritas / BESS throughput";
    figSpecs(3).plots(4).xlabel = "BESS kapacitas [kWh]";
    figSpecs(3).plots(4).ylabel = "HUF/kWh throughput";
    figSpecs(3).plots(4).legend = "eastoutside";
    figSpecs(3).plots(4).showValues = showValues;
    figSpecs(3).plots(4).valueFmt = "%.2f";
    figSpecs(3).plots(4).hideZeroBess = hideZeroBess;
    figSpecs(3).plots(4).autoYLim = autoYLim;
    figSpecs(3).plots(4).autoYMarginFrac = autoYMarginFrac;
end


function data = local_prepare_combined_diagnostic_columns(data, cfg, costPars)
    couplings = ["dc", "ac"];

    for c = 1:numel(couplings)

        coupling = couplings(c);

        if ~isfield(data, char(coupling)) || ...
           ~isfield(data.(char(coupling)), 'candidateTable')
            continue;
        end

        T = data.(char(coupling)).candidateTable;

        T = local_add_basic_combined_columns(T, cfg, coupling, costPars);
        T = local_add_zero_bess_reference_columns(T, cfg);
        T = local_add_degradation_split_columns(T);

        data.(char(coupling)).candidateTable = T;
    end
end


function T = local_add_basic_combined_columns(T, cfg, coupling, costPars)

    simYears = cfg.analysis.simYears;

    T.gridImport_MWh = local_col(T, 'gridImport_kWh', NaN) / 1000;
    T.gridImportNoBess_MWh = local_col(T, 'gridImportNoBess_kWh', NaN) / 1000;

    T.bessThroughput_MWh = local_col(T, 'bessThroughput_kWh', NaN) / 1000;
    T.bessCharge_MWh = local_col(T, 'bessCharge_kWh', NaN) / 1000;
    T.bessDischarge_MWh = local_col(T, 'bessDischarge_kWh', NaN) / 1000;

    T.pvToLoad_MWh = local_col(T, 'pvToLoad_kWh', NaN) / 1000;
    T.pvToBess_MWh = local_col(T, 'pvToBess_kWh', NaN) / 1000;
    T.curtailment_MWh = local_col(T, 'curtailment_kWh', NaN) / 1000;

    T.finalSoH_pct = 100 * local_col(T, 'finalSoH', 1);

    if ~ismember('equivalentCycles', T.Properties.VariableNames)
        T.equivalentCycles = local_safe_divide_vec( ...
            local_col(T, 'bessThroughput_kWh', NaN), ...
            2 .* local_col(T, 'E_BESS_kWh', NaN));
    end

    T.energyCost_MHUF = local_col(T, 'energyCost_HUF', NaN) / 1e6;
    T.contractCost_MHUF = local_col(T, 'contractCost_HUF', NaN) / 1e6;
    T.overrunCost_MHUF = local_col(T, 'overrunCost_HUF', NaN) / 1e6;
    T.degradationCost_MHUF = local_col(T, 'degradationCost_HUF', NaN) / 1e6;
    T.objectiveCost_MHUF = local_col(T, 'objectiveCost_HUF', NaN) / 1e6;

    coupling = lower(string(coupling));

    if coupling == "dc"

        capexEnergy_HUF_per_kWh = costPars.capexDc_HUF_per_kWh;

    elseif coupling == "ac"

        capexEnergy_HUF_per_kWh = costPars.capexAc_HUF_per_kWh;

    else

        error('Unknown coupling in combined evaluation: %s', coupling);
    end

    capexBessEnergy_HUF = ...
        local_col(T, 'E_BESS_kWh', 0) .* capexEnergy_HUF_per_kWh;

    capexBessPower_HUF = ...
        local_col(T, 'P_BESS_kW', 0) .* cfg.cost.bess_power_huf_per_kW;

    capexBess_HUF = ...
        capexBessEnergy_HUF + ...
        capexBessPower_HUF;

    opexBessAnnual_HUF = capexBess_HUF .* cfg.cost.bess_opex_frac_per_year;

    finalSoH = local_col(T, 'finalSoH', 1);
    finalSoH(~isfinite(finalSoH)) = 1;

    deltaSoHTotal = max(0, 1 - finalSoH);
    deltaSoHAnnualEq = deltaSoHTotal ./ simYears;

    if isfield(cfg.cost, 'bess_eol_soh_window')
        eolWindow = cfg.cost.bess_eol_soh_window;
    else
        eolWindow = 0.2;
    end

    bessSohCapexAnnual_HUF = ...
        (deltaSoHAnnualEq ./ eolWindow) .* capexBess_HUF;

    bessAnnualCapexOpex_HUF = ...
        bessSohCapexAnnual_HUF + opexBessAnnual_HUF;

    bessCapexOpexTotal_HUF = ...
        simYears .* bessAnnualCapexOpex_HUF;

    zeroMask = local_col(T, 'E_BESS_kWh', 0) <= 0 | ...
               local_col(T, 'P_BESS_kW', 0) <= 0;

    capexBess_HUF(zeroMask) = 0;
    opexBessAnnual_HUF(zeroMask) = 0;
    deltaSoHTotal(zeroMask) = 0;
    deltaSoHAnnualEq(zeroMask) = 0;
    bessSohCapexAnnual_HUF(zeroMask) = 0;
    bessAnnualCapexOpex_HUF(zeroMask) = 0;
    bessCapexOpexTotal_HUF(zeroMask) = 0;

    T.bessCapex_HUF = capexBess_HUF;
    T.capexEnergy_HUF_per_kWh = ...
        capexEnergy_HUF_per_kWh .* ones(height(T), 1);

    T.bessCapexEnergy_HUF = capexBessEnergy_HUF;
    T.bessCapexPower_HUF = capexBessPower_HUF;

    T.bessCapex_MHUF = T.bessCapex_HUF ./ 1e6;
    T.bessCapexEnergy_MHUF = T.bessCapexEnergy_HUF ./ 1e6;
    T.bessCapexPower_MHUF = T.bessCapexPower_HUF ./ 1e6;
    T.bessOpexAnnual_HUF = opexBessAnnual_HUF;
    T.deltaSoHTotal = deltaSoHTotal;
    T.deltaSoHAnnualEq = deltaSoHAnnualEq;
    T.bessSohCapexAnnual_HUF = bessSohCapexAnnual_HUF;
    T.bessAnnualCapexOpex_HUF = bessAnnualCapexOpex_HUF;
    T.bessCapexOpexTotal_HUF = bessCapexOpexTotal_HUF;

    T.operationalCostNoDispatchDeg_HUF = ...
        local_col(T, 'objectiveCost_HUF', NaN) - ...
        local_col(T, 'degradationCost_HUF', 0);

    pvUsed_kWh = ...
        local_col(T, 'pvToLoad_kWh', NaN) + ...
        local_col(T, 'pvToBess_kWh', NaN);

    pvProduced_kWh = ...
        local_col(T, 'pvToLoad_kWh', NaN) + ...
        local_col(T, 'pvToBess_kWh', NaN) + ...
        local_col(T, 'curtailment_kWh', 0);

    T.pvUtilization_pct = ...
        100 .* local_safe_divide_vec(pvUsed_kWh, pvProduced_kWh);
end


function T = local_add_zero_bess_reference_columns(T, cfg)

    simYears = cfg.analysis.simYears;
    discountRate = cfg.cost.discount_rate;

    idx0 = find(abs(T.BESS_PV_ratio) < 1e-12, 1, 'first');

    if isempty(idx0)
        error('No BESS = 0 reference candidate found in combined evaluation.');
    end

    zeroRow = T(idx0, :);

    zeroEnergyCost_HUF = zeroRow.energyCost_HUF(1);
    zeroContractCost_HUF = zeroRow.contractCost_HUF(1);
    zeroOverrunCost_HUF = zeroRow.overrunCost_HUF(1);
    zeroOperationalCost_HUF = zeroRow.operationalCostNoDispatchDeg_HUF(1);

    if ismember('bestContract_kW', T.Properties.VariableNames)
        zeroContract_kW = zeroRow.bestContract_kW(1);
    else
        zeroContract_kW = NaN;
    end

    T.energyCostSavingVsZero_HUF = ...
        zeroEnergyCost_HUF - local_col(T, 'energyCost_HUF', NaN);

    T.contractCostSavingVsZero_HUF = ...
        zeroContractCost_HUF - local_col(T, 'contractCost_HUF', NaN);

    T.overrunCostSavingVsZero_HUF = ...
        zeroOverrunCost_HUF - local_col(T, 'overrunCost_HUF', NaN);

    T.operationalSavingVsZero_HUF = ...
        zeroOperationalCost_HUF - local_col(T, 'operationalCostNoDispatchDeg_HUF', NaN);

    T.energyCostSavingVsZero_HUF_per_year = ...
        T.energyCostSavingVsZero_HUF ./ simYears;

    T.performanceSavingVsZero_HUF_per_year = ...
        (T.contractCostSavingVsZero_HUF + T.overrunCostSavingVsZero_HUF) ./ simYears;

    T.bessSohCapexCostVsZero_HUF = -T.bessSohCapexAnnual_HUF .* simYears;
    T.bessOpexCostVsZero_HUF = -T.bessOpexAnnual_HUF .* simYears;

    T.netSavingVsZero_HUF = ...
        T.operationalSavingVsZero_HUF - T.bessCapexOpexTotal_HUF;

    T.netAnnualSavingVsZero_HUF_per_year = ...
        T.netSavingVsZero_HUF ./ simYears;

    discountFactor = 0;

    for y = 1:simYears
        discountFactor = discountFactor + 1 / (1 + discountRate)^y;
    end

    T.combinedAnnualNetSaving_HUF = ...
        (T.energyCostSavingVsZero_HUF + ...
         T.contractCostSavingVsZero_HUF + ...
         T.overrunCostSavingVsZero_HUF) ./ simYears - ...
         T.bessAnnualCapexOpex_HUF;

    T.combinedPeriodNPV_HUF = ...
        T.combinedAnnualNetSaving_HUF .* discountFactor;

    T.energyCostSavingVsZero_MHUF = ...
        T.energyCostSavingVsZero_HUF ./ 1e6;

    T.contractCostSavingVsZero_MHUF = ...
        T.contractCostSavingVsZero_HUF ./ 1e6;

    T.overrunCostSavingVsZero_MHUF = ...
        T.overrunCostSavingVsZero_HUF ./ 1e6;

    T.bessSohCapexCostVsZero_MHUF = ...
        T.bessSohCapexCostVsZero_HUF ./ 1e6;

    T.bessOpexCostVsZero_MHUF = ...
        T.bessOpexCostVsZero_HUF ./ 1e6;

    T.netSavingVsZero_MHUF = ...
        T.netSavingVsZero_HUF ./ 1e6;

    T.combinedPeriodNPV_MHUF = ...
        T.combinedPeriodNPV_HUF ./ 1e6;

    T.contractReductionVsZero_kW = ...
        zeroContract_kW - local_col(T, 'bestContract_kW', NaN);

    T.contractReductionVsZero_pct = ...
        100 .* local_safe_divide_vec( ...
            T.contractReductionVsZero_kW, ...
            zeroContract_kW .* ones(height(T), 1));

    T.peakShavingEfficiency_kW_per_MWh = ...
        local_safe_divide_vec( ...
            T.contractReductionVsZero_kW, ...
            local_col(T, 'E_BESS_kWh', NaN) ./ 1000);

    T.energyValuePerThroughput_HUF_per_kWh = ...
        local_safe_divide_vec( ...
            T.energyCostSavingVsZero_HUF, ...
            local_col(T, 'bessThroughput_kWh', NaN));

    zeroMask = local_col(T, 'E_BESS_kWh', 0) <= 0 | ...
               local_col(T, 'P_BESS_kW', 0) <= 0;

    T.energyCostSavingVsZero_HUF(zeroMask) = 0;
    T.contractCostSavingVsZero_HUF(zeroMask) = 0;
    T.overrunCostSavingVsZero_HUF(zeroMask) = 0;
    T.operationalSavingVsZero_HUF(zeroMask) = 0;
    T.energyCostSavingVsZero_HUF_per_year(zeroMask) = 0;
    T.performanceSavingVsZero_HUF_per_year(zeroMask) = 0;
    T.bessSohCapexCostVsZero_HUF(zeroMask) = 0;
    T.bessOpexCostVsZero_HUF(zeroMask) = 0;
    T.netSavingVsZero_HUF(zeroMask) = 0;
    T.netAnnualSavingVsZero_HUF_per_year(zeroMask) = 0;
    T.combinedAnnualNetSaving_HUF(zeroMask) = 0;
    T.combinedPeriodNPV_HUF(zeroMask) = 0;

    T.energyCostSavingVsZero_MHUF(zeroMask) = 0;
    T.contractCostSavingVsZero_MHUF(zeroMask) = 0;
    T.overrunCostSavingVsZero_MHUF(zeroMask) = 0;
    T.bessSohCapexCostVsZero_MHUF(zeroMask) = 0;
    T.bessOpexCostVsZero_MHUF(zeroMask) = 0;
    T.netSavingVsZero_MHUF(zeroMask) = 0;
    T.combinedPeriodNPV_MHUF(zeroMask) = 0;
    T.contractReductionVsZero_kW(zeroMask) = 0;
    T.contractReductionVsZero_pct(zeroMask) = 0;
    T.peakShavingEfficiency_kW_per_MWh(zeroMask) = NaN;
    T.energyValuePerThroughput_HUF_per_kWh(zeroMask) = NaN;
    T.marginalBenefit_HUF_per_kWh = ...
        local_compute_marginal_benefit_by_capacity( ...
            T, ...
            'E_BESS_kWh', ...
            'combinedPeriodNPV_HUF');

    T.marginalBenefit_MHUF_per_MWh = ...
        T.marginalBenefit_HUF_per_kWh ./ 1000;

end


function T = local_add_degradation_split_columns(T)

    T.cyclicDeltaSoH_pct = local_pick_optional_pct_column(T, { ...
        'cyclicDeltaSoH_pct', ...
        'deltaSoHCyclic_pct', ...
        'cycleDeltaSoH_pct', ...
        'cyclicDegradation_pct', ...
        'cycleDegradation_pct', ...
        'sohLossCyclic_pct'});

    T.calendarDeltaSoH_pct = local_pick_optional_pct_column(T, { ...
        'calendarDeltaSoH_pct', ...
        'deltaSoHCalendar_pct', ...
        'calendarDegradation_pct', ...
        'sohLossCalendar_pct'});
end


function y = local_pick_optional_pct_column(T, candidates)

    y = NaN(height(T), 1);

    for i = 1:numel(candidates)

        col = candidates{i};

        if ismember(col, T.Properties.VariableNames)

            y = T.(col);

            finiteMask = isfinite(y);

            if any(finiteMask) && max(abs(y(finiteMask))) <= 1.0
                y = 100 .* y;
            end

            return;
        end
    end
end


function y = local_col(T, colName, defaultValue)

    if ismember(colName, T.Properties.VariableNames)
        y = T.(colName);
    else
        y = defaultValue .* ones(height(T), 1);
    end
end


function y = local_safe_divide_vec(a, b)

    y = NaN(size(a));
    mask = isfinite(a) & isfinite(b) & abs(b) > 1e-12;
    y(mask) = a(mask) ./ b(mask);
end

function marginalValue = local_compute_marginal_benefit_by_capacity(T, xField, valueField)

    x = T.(xField);
    v = T.(valueField);

    marginalValue = NaN(height(T), 1);

    valid = isfinite(x) & isfinite(v);
    idx = find(valid);

    if numel(idx) < 2
        return;
    end

    [~, ord] = sort(x(idx));
    idx = idx(ord);

    dx = [NaN; diff(x(idx))];
    dv = [NaN; diff(v(idx))];

    marginalValue(idx) = dv ./ max(dx, eps);
end