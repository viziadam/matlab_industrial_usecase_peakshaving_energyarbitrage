function [figSpecs, data] = evaluation_hybrid(data, cfg, opts)
% EVALUATION_HYBRID
%
% Hybrid AC+DC BESS dolgozati kiértékelés.
%
% A run_evaluation template rendszerét használja.
%
% A hybrid esetben minden candidate egy kétdimenziós méretezési pont:
%   x tengely: DC BESS/PV arány
%   y tengely: AC BESS/PV arány
%
% Figure-ok:
%   1) Gazdasági hozzáadott érték heatmapek
%   2) Grid profile quality heatmapek
%   3) BESS sizing economic efficiency heatmapek
%
% Használat:
%   run_evaluation("hybrid")

    %#ok<INUSD>

    data = local_prepare_hybrid_columns(data, cfg);

    figSpecs = struct([]);

    % =====================================================================
    % FIGURE 1 - HYBRID ECONOMIC VALUE
    % =====================================================================

    figSpecs(1).name = "hybrid_economic_value_heatmaps";
    figSpecs(1).layout = [2 2];

    figSpecs(1).plots(1).type = "heatmap";
    figSpecs(1).plots(1).coupling = "hybrid";
    figSpecs(1).plots(1).x = "BESS_PV_ratio_dc";
    figSpecs(1).plots(1).y = "BESS_PV_ratio_ac";
    figSpecs(1).plots(1).z = "combinedPeriodNPV_MHUF";
    figSpecs(1).plots(1).title = "Hybrid NPV a BESS = 0 referenciahoz kepest";
    figSpecs(1).plots(1).xlabel = "DC BESS/PV arany [kWh/kWp]";
    figSpecs(1).plots(1).ylabel = "AC BESS/PV arany [kWh/kWp]";
    figSpecs(1).plots(1).colorLabel = "NPV [M HUF]";

    figSpecs(1).plots(2).type = "heatmap";
    figSpecs(1).plots(2).coupling = "hybrid";
    figSpecs(1).plots(2).x = "BESS_PV_ratio_dc";
    figSpecs(1).plots(2).y = "BESS_PV_ratio_ac";
    figSpecs(1).plots(2).z = "netSavingVsZero_MHUF";
    figSpecs(1).plots(2).title = "Netto megtakaritas a BESS = 0 referenciahoz kepest";
    figSpecs(1).plots(2).xlabel = "DC BESS/PV arany [kWh/kWp]";
    figSpecs(1).plots(2).ylabel = "AC BESS/PV arany [kWh/kWp]";
    figSpecs(1).plots(2).colorLabel = "Netto megtakaritas [M HUF]";

    figSpecs(1).plots(3).type = "heatmap";
    figSpecs(1).plots(3).coupling = "hybrid";
    figSpecs(1).plots(3).x = "BESS_PV_ratio_dc";
    figSpecs(1).plots(3).y = "BESS_PV_ratio_ac";
    figSpecs(1).plots(3).z = "energyCostSavingVsZero_MHUF";
    figSpecs(1).plots(3).title = "Energiakoltseg-megtakaritas";
    figSpecs(1).plots(3).xlabel = "DC BESS/PV arany [kWh/kWp]";
    figSpecs(1).plots(3).ylabel = "AC BESS/PV arany [kWh/kWp]";
    figSpecs(1).plots(3).colorLabel = "Energiakoltseg-megtakaritas [M HUF]";

    figSpecs(1).plots(4).type = "heatmap";
    figSpecs(1).plots(4).coupling = "hybrid";
    figSpecs(1).plots(4).x = "BESS_PV_ratio_dc";
    figSpecs(1).plots(4).y = "BESS_PV_ratio_ac";
    figSpecs(1).plots(4).z = "performanceSavingVsZero_MHUF";
    figSpecs(1).plots(4).title = "Teljesitmenydij-megtakaritas";
    figSpecs(1).plots(4).xlabel = "DC BESS/PV arany [kWh/kWp]";
    figSpecs(1).plots(4).ylabel = "AC BESS/PV arany [kWh/kWp]";
    figSpecs(1).plots(4).colorLabel = "Teljesitmenydij-megtakaritas [M HUF]";

    % =====================================================================
    % FIGURE 2 - GRID PROFILE QUALITY
    % =====================================================================

    figSpecs(2).name = "hybrid_grid_profile_quality_heatmaps";
    figSpecs(2).layout = [1 2];

    figSpecs(2).plots(1).type = "heatmap";
    figSpecs(2).plots(1).coupling = "hybrid";
    figSpecs(2).plots(1).x = "BESS_PV_ratio_dc";
    figSpecs(2).plots(1).y = "BESS_PV_ratio_ac";
    figSpecs(2).plots(1).z = "gridRampReduction_pct";
    figSpecs(2).plots(1).title = "Halozati ramping csokkenese";
    figSpecs(2).plots(1).xlabel = "DC BESS/PV arany [kWh/kWp]";
    figSpecs(2).plots(1).ylabel = "AC BESS/PV arany [kWh/kWp]";
    figSpecs(2).plots(1).colorLabel = "Ramp reduction [%]";

    figSpecs(2).plots(2).type = "heatmap";
    figSpecs(2).plots(2).coupling = "hybrid";
    figSpecs(2).plots(2).x = "BESS_PV_ratio_dc";
    figSpecs(2).plots(2).y = "BESS_PV_ratio_ac";
    figSpecs(2).plots(2).z = "residualLoadVariabilityReduction_pct";
    figSpecs(2).plots(2).title = "Marado halozati terheles ingadozasanak csokkenese";
    figSpecs(2).plots(2).xlabel = "DC BESS/PV arany [kWh/kWp]";
    figSpecs(2).plots(2).ylabel = "AC BESS/PV arany [kWh/kWp]";
    figSpecs(2).plots(2).colorLabel = "Variability reduction [%]";

    % =====================================================================
    % FIGURE 3 - BESS SIZING ECONOMIC EFFICIENCY
    % =====================================================================

    figSpecs(3).name = "hybrid_bess_sizing_value_heatmaps";
    figSpecs(3).layout = [1 2];

    figSpecs(3).plots(1).type = "heatmap";
    figSpecs(3).plots(1).coupling = "hybrid";
    figSpecs(3).plots(1).x = "BESS_PV_ratio_dc";
    figSpecs(3).plots(1).y = "BESS_PV_ratio_ac";
    figSpecs(3).plots(1).z = "specificNPV_HUF_per_kWh";
    figSpecs(3).plots(1).title = "Fajlagos NPV telepitett BESS kapacitasra vetitve";
    figSpecs(3).plots(1).xlabel = "DC BESS/PV arany [kWh/kWp]";
    figSpecs(3).plots(1).ylabel = "AC BESS/PV arany [kWh/kWp]";
    figSpecs(3).plots(1).colorLabel = "HUF/kWh installed";

    figSpecs(3).plots(2).type = "heatmap";
    figSpecs(3).plots(2).coupling = "hybrid";
    figSpecs(3).plots(2).x = "BESS_PV_ratio_dc";
    figSpecs(3).plots(2).y = "BESS_PV_ratio_ac";
    figSpecs(3).plots(2).z = "marginalStorageValue_HUF_per_kWh";
    figSpecs(3).plots(2).title = "BESS kapacitas hatarhaszna";
    figSpecs(3).plots(2).xlabel = "DC BESS/PV arany [kWh/kWp]";
    figSpecs(3).plots(2).ylabel = "AC BESS/PV arany [kWh/kWp]";
    figSpecs(3).plots(2).colorLabel = "HUF/kWh additional";
end


function data = local_prepare_hybrid_columns(data, cfg)

    if ~isfield(data, 'hybrid') || ...
       ~isfield(data.hybrid, 'candidateTable')

        error('evaluation_hybrid requires data.hybrid.candidateTable.');
    end

    T = data.hybrid.candidateTable;

    T = T(logical(T.wasSimulated) & ~logical(T.hasError), :);

    local_require_columns(T, { ...
        'BESS_PV_ratio_dc', ...
        'BESS_PV_ratio_ac', ...
        'BESS_PV_ratio_total', ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'energyCost_HUF', ...
        'energyCostNoBess_HUF', ...
        'contractCost_HUF', ...
        'overrunCost_HUF', ...
        'objectiveCost_HUF', ...
        'degradationCost_HUF', ...
        'bestContract_kW', ...
        'finalSoH', ...
        'bessThroughput_kWh'});

    T = local_add_hybrid_basic_economics(T, cfg);
    T = local_add_hybrid_reference_metrics(T, cfg);
    T = local_add_hybrid_profile_quality_metrics(T, data.hybrid);
    T = local_add_hybrid_sizing_value_metrics(T);

    data.hybrid.candidateTable = T;
end


function T = local_add_hybrid_basic_economics(T, cfg)

    simYears = cfg.analysis.simYears;

    capexBess_HUF = ...
        T.E_BESS_kWh .* cfg.cost.bess_huf_per_kWh + ...
        T.P_BESS_kW .* cfg.cost.bess_power_huf_per_kW;

    opexBessAnnual_HUF = capexBess_HUF .* cfg.cost.bess_opex_frac_per_year;

    finalSoH = T.finalSoH;
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

    T.finalSoH_pct = 100 .* finalSoH;
    T.deltaSoHTotal = deltaSoHTotal;

    T.bessCapex_HUF = capexBess_HUF;
    T.bessOpexAnnual_HUF = opexBessAnnual_HUF;
    T.bessSohCapexAnnual_HUF = bessSohCapexAnnual_HUF;
    T.bessAnnualCapexOpex_HUF = bessAnnualCapexOpex_HUF;
    T.bessCapexOpexTotal_HUF = bessCapexOpexTotal_HUF;

    T.operationalCostNoDispatchDeg_HUF = ...
        T.objectiveCost_HUF - T.degradationCost_HUF;
end


function T = local_add_hybrid_reference_metrics(T, cfg)

    simYears = cfg.analysis.simYears;
    discountRate = cfg.cost.discount_rate;

    % Hybrid candidate racsban altalaban nincs BESS = 0 sor.
    % Ezert a no-BESS referencia a candidateTable-ben mentett
    % NoBess koltsegoszlopokbol, illetve a cfg.dispatch.noBessContract_kW
    % ertekbol jon.
    refEnergy_HUF = local_first_finite(T.energyCostNoBess_HUF);

    if ismember('contractCostNoBess_HUF', T.Properties.VariableNames)
        refContract_HUF = local_first_finite(T.contractCostNoBess_HUF);
    else
        refContract_HUF = local_first_finite(T.contractCost_HUF);
    end

    if ismember('overrunCostNoBess_HUF', T.Properties.VariableNames)
        refOverrun_HUF = local_first_finite(T.overrunCostNoBess_HUF);
    else
        refOverrun_HUF = 0;
    end

    if isfield(cfg, 'dispatch') && isfield(cfg.dispatch, 'noBessContract_kW')
        refContract_kW = cfg.dispatch.noBessContract_kW;
    else
        refContract_kW = local_first_finite(T.bestContract_kW);
    end

    T.energyCostSavingVsZero_HUF = ...
        refEnergy_HUF - T.energyCost_HUF;

    T.contractCostSavingVsZero_HUF = ...
        refContract_HUF - T.contractCost_HUF;

    T.overrunCostSavingVsZero_HUF = ...
        refOverrun_HUF - T.overrunCost_HUF;

    T.performanceSavingVsZero_HUF = ...
        T.contractCostSavingVsZero_HUF + ...
        T.overrunCostSavingVsZero_HUF;

    T.operationalSavingVsZero_HUF = ...
        T.energyCostSavingVsZero_HUF + ...
        T.performanceSavingVsZero_HUF;

    T.netSavingVsZero_HUF = ...
        T.operationalSavingVsZero_HUF - ...
        T.bessCapexOpexTotal_HUF;

    T.energyCostSavingVsZero_MHUF = ...
        T.energyCostSavingVsZero_HUF ./ 1e6;

    T.contractCostSavingVsZero_MHUF = ...
        T.contractCostSavingVsZero_HUF ./ 1e6;

    T.overrunCostSavingVsZero_MHUF = ...
        T.overrunCostSavingVsZero_HUF ./ 1e6;

    T.performanceSavingVsZero_MHUF = ...
        T.performanceSavingVsZero_HUF ./ 1e6;

    T.netSavingVsZero_MHUF = ...
        T.netSavingVsZero_HUF ./ 1e6;

    discountFactor = 0;

    for y = 1:simYears
        discountFactor = discountFactor + 1 / (1 + discountRate)^y;
    end

    T.combinedAnnualNetSaving_HUF = ...
        T.operationalSavingVsZero_HUF ./ simYears - ...
        T.bessAnnualCapexOpex_HUF;

    T.combinedPeriodNPV_HUF = ...
        T.combinedAnnualNetSaving_HUF .* discountFactor;

    T.combinedPeriodNPV_MHUF = ...
        T.combinedPeriodNPV_HUF ./ 1e6;

    T.contractReductionVsZero_kW = ...
        refContract_kW - T.bestContract_kW;

    T.contractReductionVsZero_pct = ...
        100 .* local_safe_divide_vec( ...
            T.contractReductionVsZero_kW, ...
            refContract_kW .* ones(height(T), 1));
end


function T = local_add_hybrid_profile_quality_metrics(T, hybridData)

    T.gridRampReduction_pct = NaN(height(T), 1);
    T.residualLoadVariabilityReduction_pct = NaN(height(T), 1);

    if ~isfield(hybridData, 'candidateProfiles') || isempty(hybridData.candidateProfiles)
        return;
    end

    P = hybridData.candidateProfiles;

    if ~isfield(P, 'meanGridImport_kW') || ...
       ~isfield(P, 'meanGridImportNoBess_kW')
        return;
    end

    for i = 1:height(T)

        rowIdx = i;

        if ismember('candidateIndex', T.Properties.VariableNames) && ...
           isfinite(T.candidateIndex(i))
            rowIdx = T.candidateIndex(i);
        end

        if rowIdx < 1 || rowIdx > size(P.meanGridImport_kW, 1)
            continue;
        end

        gridBess = P.meanGridImport_kW(rowIdx, :).';
        gridRef = P.meanGridImportNoBess_kW(rowIdx, :).';

        rampRef = abs(diff(gridRef));
        rampBess = abs(diff(gridBess));

        T.gridRampReduction_pct(i) = ...
            100 .* (sum(rampRef) - sum(rampBess)) ./ ...
            max(sum(rampRef), eps);

        T.residualLoadVariabilityReduction_pct(i) = ...
            100 .* (std(gridRef) - std(gridBess)) ./ ...
            max(std(gridRef), eps);
    end
end


function T = local_add_hybrid_sizing_value_metrics(T)

    T.specificNPV_HUF_per_kWh = ...
        local_safe_divide_vec(T.combinedPeriodNPV_HUF, T.E_BESS_kWh);

    T.specificNetValue_HUF_per_kWh = ...
        local_safe_divide_vec(T.netSavingVsZero_HUF, T.E_BESS_kWh);

    T.marginalStorageValue_HUF_per_kWh = NaN(height(T), 1);

    dcVals = unique(T.BESS_PV_ratio_dc);
    acVals = unique(T.BESS_PV_ratio_ac);

    % Marginal value along DC direction
    for iAc = 1:numel(acVals)

        mask = abs(T.BESS_PV_ratio_ac - acVals(iAc)) < 1e-12;
        subIdx = find(mask);

        if numel(subIdx) < 2
            continue;
        end

        [~, ord] = sort(T.BESS_PV_ratio_dc(subIdx));
        subIdx = subIdx(ord);

        dValue = [NaN; diff(T.combinedPeriodNPV_HUF(subIdx))];
        dE = [NaN; diff(T.E_BESS_kWh(subIdx))];

        T.marginalStorageValue_HUF_per_kWh(subIdx) = ...
            dValue ./ max(dE, eps);
    end

    % Marginal value along AC direction.
    % Ha mindket iranybol van becsles, akkor az atlagot vesszuk.
    marginalAc = NaN(height(T), 1);

    for iDc = 1:numel(dcVals)

        mask = abs(T.BESS_PV_ratio_dc - dcVals(iDc)) < 1e-12;
        subIdx = find(mask);

        if numel(subIdx) < 2
            continue;
        end

        [~, ord] = sort(T.BESS_PV_ratio_ac(subIdx));
        subIdx = subIdx(ord);

        dValue = [NaN; diff(T.combinedPeriodNPV_HUF(subIdx))];
        dE = [NaN; diff(T.E_BESS_kWh(subIdx))];

        marginalAc(subIdx) = dValue ./ max(dE, eps);
    end

    both = isfinite(T.marginalStorageValue_HUF_per_kWh) & isfinite(marginalAc);
    onlyAc = ~isfinite(T.marginalStorageValue_HUF_per_kWh) & isfinite(marginalAc);

    T.marginalStorageValue_HUF_per_kWh(both) = ...
        0.5 .* (T.marginalStorageValue_HUF_per_kWh(both) + marginalAc(both));

    T.marginalStorageValue_HUF_per_kWh(onlyAc) = marginalAc(onlyAc);
end


function value = local_first_finite(x)

    idx = find(isfinite(x), 1, 'first');

    if isempty(idx)
        value = NaN;
    else
        value = x(idx);
    end
end


function local_require_columns(T, colNames)

    for i = 1:numel(colNames)
        if ~ismember(colNames{i}, T.Properties.VariableNames)
            error('Missing required hybrid evaluation column: %s', colNames{i});
        end
    end
end


function y = local_safe_divide_vec(a, b)

    y = NaN(size(a));
    mask = isfinite(a) & isfinite(b) & abs(b) > 1e-12;
    y(mask) = a(mask) ./ b(mask);
end