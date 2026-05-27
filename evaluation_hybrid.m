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
    figSpecs(3).layout = [1 3];

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
    figSpecs(3).plots(2).x = "E_BESS_total_MWh";
    figSpecs(3).plots(2).y = "bessAcShare_pct";
    figSpecs(3).plots(2).z = "marginalStorageValueDc_MHUF_per_MWh";
    figSpecs(3).plots(2).title = "DC BESS kapacitas marginalis haszna";
    figSpecs(3).plots(2).xlabel = "Teljes BESS kapacitas [MWh]";
    figSpecs(3).plots(2).ylabel = "AC-csatolt BESS reszaranya [%]";
    figSpecs(3).plots(2).colorLabel = "M HUF/MWh";

    figSpecs(3).plots(3).type = "heatmap";
    figSpecs(3).plots(3).coupling = "hybrid";
    figSpecs(3).plots(3).x = "E_BESS_total_MWh";
    figSpecs(3).plots(3).y = "bessAcShare_pct";
    figSpecs(3).plots(3).z = "marginalStorageValueAc_MHUF_per_MWh";
    figSpecs(3).plots(3).title = "AC BESS kapacitas marginalis haszna";
    figSpecs(3).plots(3).xlabel = "Teljes BESS kapacitas [MWh]";
    figSpecs(3).plots(3).ylabel = "AC-csatolt BESS reszaranya [%]";
    figSpecs(3).plots(3).colorLabel = "M HUF/MWh";

    figSpecs = local_apply_hybrid_total_share_axes(figSpecs);
    figSpecs = local_apply_hybrid_heatmap_styles(figSpecs);
end


function data = local_prepare_hybrid_columns(data, cfg)

    if ~isfield(data, 'hybrid') || ...
       ~isfield(data.hybrid, 'candidateTable')

        error('evaluation_hybrid requires data.hybrid.candidateTable.');
    end

    T = data.hybrid.candidateTable;

    T = T(logical(T.wasSimulated) & ~logical(T.hasError), :);
    T.sourceCoupling = repmat("hybrid", height(T), 1);

    T = local_append_single_coupling_candidates(T, data, "dc");
    T = local_append_single_coupling_candidates(T, data, "ac");
    
    local_require_columns(T, { ...
        'BESS_PV_ratio_dc', ...
        'BESS_PV_ratio_ac', ...
        'BESS_PV_ratio_total', ...
        'E_BESS_dc_kWh', ...
        'E_BESS_ac_kWh', ...
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

    T = local_add_hybrid_axis_columns(T);
    T = local_add_hybrid_basic_economics(T, cfg);
    T = local_add_hybrid_reference_metrics(T, cfg);
    T = local_add_hybrid_profile_quality_metrics(T, data);
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


function T = local_add_hybrid_profile_quality_metrics(T, data)

    T.gridRampReduction_pct = NaN(height(T), 1);
    T.residualLoadVariabilityReduction_pct = NaN(height(T), 1);

    for i = 1:height(T)

        sourceCoupling = string(T.sourceCoupling(i));
        dataFields = string(fieldnames(data));

        if ~ismember(sourceCoupling, dataFields)
            continue;
        end

        item = data.(char(sourceCoupling));
        itemFields = string(fieldnames(item));

        if ~ismember("candidateProfiles", itemFields)
            continue;
        end

        P = item.candidateProfiles;
        profileFields = string(fieldnames(P));

        if ~ismember("meanGridImport_kW", profileFields) || ...
           ~ismember("meanGridImportNoBess_kW", profileFields)

            continue;
        end

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

    T.marginalStorageValueDc_HUF_per_kWh = NaN(height(T), 1);
    T.marginalStorageValueAc_HUF_per_kWh = NaN(height(T), 1);

    dcVals = unique(T.BESS_PV_ratio_dc);
    acVals = unique(T.BESS_PV_ratio_ac);

    for iAc = 1:numel(acVals)

        mask = abs(T.BESS_PV_ratio_ac - acVals(iAc)) < 1e-12;
        subIdx = find(mask);

        if numel(subIdx) < 2
            continue;
        end

        [~, ord] = sort(T.E_BESS_dc_kWh(subIdx));
        subIdx = subIdx(ord);

        dValue = [NaN; diff(T.combinedPeriodNPV_HUF(subIdx))];
        dE = [NaN; diff(T.E_BESS_dc_kWh(subIdx))];

        T.marginalStorageValueDc_HUF_per_kWh(subIdx) = ...
            dValue ./ max(dE, eps);
    end

    for iDc = 1:numel(dcVals)

        mask = abs(T.BESS_PV_ratio_dc - dcVals(iDc)) < 1e-12;
        subIdx = find(mask);

        if numel(subIdx) < 2
            continue;
        end

        [~, ord] = sort(T.E_BESS_ac_kWh(subIdx));
        subIdx = subIdx(ord);

        dValue = [NaN; diff(T.combinedPeriodNPV_HUF(subIdx))];
        dE = [NaN; diff(T.E_BESS_ac_kWh(subIdx))];

        T.marginalStorageValueAc_HUF_per_kWh(subIdx) = ...
            dValue ./ max(dE, eps);
    end

    T.marginalStorageValueDc_MHUF_per_MWh = ...
        T.marginalStorageValueDc_HUF_per_kWh ./ 1000;

    T.marginalStorageValueAc_MHUF_per_MWh = ...
        T.marginalStorageValueAc_HUF_per_kWh ./ 1000;

    T.marginalStorageValue_HUF_per_kWh = ...
        0.5 .* ( ...
            T.marginalStorageValueDc_HUF_per_kWh + ...
            T.marginalStorageValueAc_HUF_per_kWh);

    onlyDc = ...
        isfinite(T.marginalStorageValueDc_HUF_per_kWh) & ...
        ~isfinite(T.marginalStorageValueAc_HUF_per_kWh);

    onlyAc = ...
        ~isfinite(T.marginalStorageValueDc_HUF_per_kWh) & ...
        isfinite(T.marginalStorageValueAc_HUF_per_kWh);

    T.marginalStorageValue_HUF_per_kWh(onlyDc) = ...
        T.marginalStorageValueDc_HUF_per_kWh(onlyDc);

    T.marginalStorageValue_HUF_per_kWh(onlyAc) = ...
        T.marginalStorageValueAc_HUF_per_kWh(onlyAc);

    T.marginalStorageValue_MHUF_per_MWh = ...
        T.marginalStorageValue_HUF_per_kWh ./ 1000;
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

function T = local_add_hybrid_axis_columns(T)

    T.E_BESS_total_kWh = T.E_BESS_kWh;
    T.E_BESS_total_MWh = T.E_BESS_total_kWh ./ 1000;

    T.bessAcShare_pct = ...
        100 .* T.E_BESS_ac_kWh ./ max(T.E_BESS_total_kWh, eps);

    zeroBessMask = abs(T.E_BESS_total_kWh) <= 1e-12;
    T.bessAcShare_pct(zeroBessMask) = 0;

    T.bessDcShare_pct = 100 - T.bessAcShare_pct;
end

function figSpecs = local_apply_hybrid_total_share_axes(figSpecs)

    for f = 1:numel(figSpecs)

        for p = 1:numel(figSpecs(f).plots)

            figSpecs(f).plots(p).x = "E_BESS_total_MWh";
            figSpecs(f).plots(p).y = "bessAcShare_pct";

            figSpecs(f).plots(p).xlabel = ...
                "Teljes BESS kapacitas [MWh]";

            figSpecs(f).plots(p).ylabel = ...
                "AC-csatolt BESS reszaranya [%]";
        end
    end
end


function figSpecs = local_apply_hybrid_heatmap_styles(figSpecs)

    for p = 1:numel(figSpecs(1).plots)

        figSpecs(1).plots(p).heatmapStyle = "soft_points";
        figSpecs(1).plots(p).colormapName = "parula";
        figSpecs(1).plots(p).markerSize = 360;
        figSpecs(1).plots(p).showContour = false;
        figSpecs(1).plots(p).hideLegend = true;
    end

    for p = 1:numel(figSpecs(2).plots)

        figSpecs(2).plots(p).heatmapStyle = "contour_points";
        figSpecs(2).plots(p).colormapName = "turbo";
        figSpecs(2).plots(p).markerSize = 300;
        figSpecs(2).plots(p).showContour = true;
        figSpecs(2).plots(p).contourLevels = 8;
        figSpecs(2).plots(p).hideLegend = true;
    end

    for p = 1:numel(figSpecs(3).plots)

        figSpecs(3).plots(p).heatmapStyle = "contour_points";
        figSpecs(3).plots(p).colormapName = "parula";
        figSpecs(3).plots(p).markerSize = 300;
        figSpecs(3).plots(p).showContour = true;
        figSpecs(3).plots(p).contourLevels = 8;
        figSpecs(3).plots(p).hideLegend = true;
    end
end

function T = local_append_single_coupling_candidates(T, data, coupling)

    coupling = lower(string(coupling));
    dataFields = string(fieldnames(data));

    if ~ismember(coupling, dataFields)
        return;
    end

    item = data.(char(coupling));
    itemFields = string(fieldnames(item));

    if ~ismember("candidateTable", itemFields)
        return;
    end

    S = item.candidateTable;
    S = S(logical(S.wasSimulated) & ~logical(S.hasError), :);

    if height(S) == 0
        return;
    end

    S = local_convert_single_coupling_to_hybrid_table(S, coupling);

    T = local_append_table_like_reference(T, S);
end


function S = local_convert_single_coupling_to_hybrid_table(S, coupling)

    coupling = lower(string(coupling));

    if ~ismember('BESS_PV_ratio', S.Properties.VariableNames)
        error('Single coupling table missing BESS_PV_ratio.');
    end

    if ~ismember('E_BESS_kWh', S.Properties.VariableNames)
        error('Single coupling table missing E_BESS_kWh.');
    end

    if ~ismember('P_BESS_kW', S.Properties.VariableNames)
        error('Single coupling table missing P_BESS_kW.');
    end

    n = height(S);

    S.sourceCoupling = repmat(coupling, n, 1);

    switch coupling

        case "dc"

            S.BESS_PV_ratio_dc = S.BESS_PV_ratio;
            S.BESS_PV_ratio_ac = zeros(n, 1);
            S.BESS_PV_ratio_total = S.BESS_PV_ratio;

            S.E_BESS_dc_kWh = S.E_BESS_kWh;
            S.E_BESS_ac_kWh = zeros(n, 1);

            S.P_BESS_dc_kW = S.P_BESS_kW;
            S.P_BESS_ac_kW = zeros(n, 1);

            S.finalSoHDc = S.finalSoH;
            S.finalSoHAc = NaN(n, 1);

        case "ac"

            S.BESS_PV_ratio_dc = zeros(n, 1);
            S.BESS_PV_ratio_ac = S.BESS_PV_ratio;
            S.BESS_PV_ratio_total = S.BESS_PV_ratio;

            S.E_BESS_dc_kWh = zeros(n, 1);
            S.E_BESS_ac_kWh = S.E_BESS_kWh;

            S.P_BESS_dc_kW = zeros(n, 1);
            S.P_BESS_ac_kW = S.P_BESS_kW;

            S.finalSoHDc = NaN(n, 1);
            S.finalSoHAc = S.finalSoH;

        otherwise

            error('Unsupported single coupling mode: %s', coupling);
    end

    S.isConvertedSingleCoupling = true(n, 1);
end


function T = local_append_table_like_reference(T, S)

    refVars = T.Properties.VariableNames;

    S = local_add_missing_columns_like_reference(S, T);
    S = S(:, refVars);

    T = [T; S];
end


function S = local_add_missing_columns_like_reference(S, refT)

    refVars = refT.Properties.VariableNames;

    for i = 1:numel(refVars)

        v = refVars{i};

        if ismember(v, S.Properties.VariableNames)
            continue;
        end

        refCol = refT.(v);

        if isnumeric(refCol)
            S.(v) = NaN(height(S), 1);

        elseif islogical(refCol)
            S.(v) = false(height(S), 1);

        elseif isstring(refCol)
            S.(v) = strings(height(S), 1);

        elseif iscell(refCol)
            S.(v) = cell(height(S), 1);

        else
            S.(v) = NaN(height(S), 1);
        end
    end
end