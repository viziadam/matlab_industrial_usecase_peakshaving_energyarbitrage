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

    % ---------------------------------------------------------------------
    % Hybrid economic assumptions
    % ---------------------------------------------------------------------
    % Fajlagos BESS CAPEX ertekek kulon AC- es DC-csatolt BESS agra.
    % Mertekegyseg: HUF/kWh
    %
    % Ezeket itt lehet gyorsan valtoztatni erzekenysegvizsgalathoz.
    %
    % Megjegyzes:
    %   A teljesitmeny oldali CAPEX tovabbra is a cfg.cost.bess_power_huf_per_kW
    %   erteket hasznalja, de a kapacitas oldali CAPEX mar kulon DC es AC.
    eur_to_huf = 400;
    capexDC_eur_per_kWh = 280;
    capexAC_eur_per_kWh = 280;
    capexDc_HUF_per_kWh = capexDC_eur_per_kWh*eur_to_huf;
    capexAc_HUF_per_kWh = capexAC_eur_per_kWh*eur_to_huf;

    costPars = struct();
    costPars.capexDc_HUF_per_kWh = capexDc_HUF_per_kWh;
    costPars.capexAc_HUF_per_kWh = capexAc_HUF_per_kWh;

    data = local_prepare_hybrid_columns(data, cfg, costPars);

    figSpecs = struct([]);

    % =====================================================================
    % FIGURE 1 - AKKUMULATOR ALLAPOTA ES IGENYBEVETELE
    % =====================================================================

    figSpecs(1).name = "hybrid_akkumulator_allapot_es_igenybevetel";
    figSpecs(1).layout = [1 2];

    figSpecs(1).plots(1).type = "heatmap";
    figSpecs(1).plots(1).coupling = "hybrid";
    figSpecs(1).plots(1).x = "BESS_PV_ratio_total";
    figSpecs(1).plots(1).y = "bessAcShare_pct";
    figSpecs(1).plots(1).z = "finalSoH_pct";
    figSpecs(1).plots(1).title = "Akkumulator vegso egeszsegi allapota";
    figSpecs(1).plots(1).xlabel = "Teljes BESS/PV arany [kWh/kWp]";
    figSpecs(1).plots(1).ylabel = "AC-csatolt BESS reszaranya [%]";
    figSpecs(1).plots(1).colorLabel = "SoH [%]";

    figSpecs(1).plots(2).type = "heatmap";
    figSpecs(1).plots(2).coupling = "hybrid";
    figSpecs(1).plots(2).x = "BESS_PV_ratio_total";
    figSpecs(1).plots(2).y = "bessAcShare_pct";
    figSpecs(1).plots(2).z = "equivalentFullCycles_per_year";
    figSpecs(1).plots(2).title = "Ekvivalens teljes ciklusszam evente";
    figSpecs(1).plots(2).xlabel = "Teljes BESS/PV arany [kWh/kWp]";
    figSpecs(1).plots(2).ylabel = "AC-csatolt BESS reszaranya [%]";
    figSpecs(1).plots(2).colorLabel = "Ciklus/ev";

    % =====================================================================
    % FIGURE 2 - GAZDASAGI MUTATOK
    % =====================================================================

    figSpecs(2).name = "hybrid_gazdasagi_mutatok";
    figSpecs(2).layout = [1 2];

    figSpecs(2).plots(1).type = "heatmap";
    figSpecs(2).plots(1).coupling = "hybrid";
    figSpecs(2).plots(1).x = "BESS_PV_ratio_total";
    figSpecs(2).plots(1).y = "bessAcShare_pct";
    figSpecs(2).plots(1).z = "netPresentValue_MHUF";
    figSpecs(2).plots(1).title = "Netto jelenertek";
    figSpecs(2).plots(1).xlabel = "Teljes BESS/PV arany [kWh/kWp]";
    figSpecs(2).plots(1).ylabel = "AC-csatolt BESS reszaranya [%]";
    figSpecs(2).plots(1).colorLabel = "NPV [M HUF]";

    % figSpecs(2).plots(2).type = "heatmap";
    % figSpecs(2).plots(2).coupling = "hybrid";
    % figSpecs(2).plots(2).x = "BESS_PV_ratio_total";
    % figSpecs(2).plots(2).y = "bessAcShare_pct";
    % figSpecs(2).plots(2).z = "bessCapexOpexTotal_MHUF";
    % figSpecs(2).plots(2).title = "BESS beruhazasi es uzemeltetesi koltseg";
    % figSpecs(2).plots(2).xlabel = "Teljes BESS/PV arany [kWh/kWp]";
    % figSpecs(2).plots(2).ylabel = "AC-csatolt BESS reszaranya [%]";
    % figSpecs(2).plots(2).colorLabel = "Koltseg [M HUF]";

    figSpecs(2).plots(2).type = "heatmap";
    figSpecs(2).plots(2).coupling = "hybrid";
    figSpecs(2).plots(2).x = "BESS_PV_ratio_total";
    figSpecs(2).plots(2).y = "bessAcShare_pct";
    figSpecs(2).plots(2).z = "storageServiceCost_HUF_per_kWh";
    figSpecs(2).plots(2).title = "Fajlagos tarolasi koltseg";
    figSpecs(2).plots(2).xlabel = "Teljes BESS/PV arany [kWh/kWp]";
    figSpecs(2).plots(2).ylabel = "AC-csatolt BESS reszaranya [%]";
    figSpecs(2).plots(2).colorLabel = "HUF/kWh";

    % =====================================================================
    % FIGURE 3 - HALOZATI PROFILMINOSEG
    % =====================================================================

    figSpecs(3).name = "hybrid_halozati_profilminoseg";
    figSpecs(3).layout = [1 1];

    figSpecs(3).plots(1).type = "heatmap";
    figSpecs(3).plots(1).coupling = "hybrid";
    figSpecs(3).plots(1).x = "BESS_PV_ratio_total";
    figSpecs(3).plots(1).y = "bessAcShare_pct";
    figSpecs(3).plots(1).z = "residualLoadVariabilityReduction_pct";
    figSpecs(3).plots(1).title = "Marado halozati terheles ingadozasanak csokkenese";
    figSpecs(3).plots(1).xlabel = "Teljes BESS/PV arany [kWh/kWp]";
    figSpecs(3).plots(1).ylabel = "AC-csatolt BESS reszaranya [%]";
    figSpecs(3).plots(1).colorLabel = "Csokkenes [%]";

    % =====================================================================
    % FIGURE 4 - MARGINALIS HASZON
    % =====================================================================

    figSpecs(4).name = "hybrid_marginalis_haszon";
    figSpecs(4).layout = [1 2];

    figSpecs(4).plots(1).type = "heatmap";
    figSpecs(4).plots(1).coupling = "hybrid";
    figSpecs(4).plots(1).x = "BESS_PV_ratio_total";
    figSpecs(4).plots(1).y = "bessAcShare_pct";
    figSpecs(4).plots(1).z = "marginalStorageValueDc_MHUF_per_kWh";
    figSpecs(4).plots(1).title = "DC-csatolt BESS marginalis haszna";
    figSpecs(4).plots(1).xlabel = "Teljes BESS/PV arany [kWh/kWp]";
    figSpecs(4).plots(1).ylabel = "AC-csatolt BESS reszaranya [%]";
    figSpecs(4).plots(1).colorLabel = "ezer HUF/kWh";

    figSpecs(4).plots(2).type = "heatmap";
    figSpecs(4).plots(2).coupling = "hybrid";
    figSpecs(4).plots(2).x = "BESS_PV_ratio_total";
    figSpecs(4).plots(2).y = "bessAcShare_pct";
    figSpecs(4).plots(2).z = "marginalStorageValueAc_MHUF_per_kWh";
    figSpecs(4).plots(2).title = "AC-csatolt BESS marginalis haszna";
    figSpecs(4).plots(2).xlabel = "Teljes BESS/PV arany [kWh/kWp]";
    figSpecs(4).plots(2).ylabel = "AC-csatolt BESS reszaranya [%]";
    figSpecs(4).plots(2).colorLabel = "ezer HUF/kWh";

    local_save_hybrid_best_candidate_table(data.hybrid.candidateTable, opts);
    local_save_hybrid_best_candidate_cost_bridge_figure(data.hybrid.candidateTable, opts);

    figSpecs = local_apply_hybrid_total_share_axes(figSpecs);
    figSpecs = local_apply_hybrid_heatmap_styles(figSpecs);
end


function data = local_prepare_hybrid_columns(data, cfg, costPars)

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
    T = local_add_hybrid_basic_economics(T, cfg, costPars);
    T = local_add_hybrid_reference_metrics(T, cfg);
    T = local_add_hybrid_profile_quality_metrics(T, data);
    T = local_add_hybrid_operational_lifetime_metrics(T, cfg);
    T = local_add_hybrid_sizing_value_metrics(T);

    data.hybrid.candidateTable = T;
end


function T = local_add_hybrid_basic_economics(T, cfg, costPars)

    simYears = cfg.analysis.simYears;

    capexBessEnergyDc_HUF = ...
        T.E_BESS_dc_kWh .* costPars.capexDc_HUF_per_kWh;

    capexBessEnergyAc_HUF = ...
        T.E_BESS_ac_kWh .* costPars.capexAc_HUF_per_kWh;

    capexBessEnergy_HUF = ...
        capexBessEnergyDc_HUF + ...
        capexBessEnergyAc_HUF;

    capexBessPower_HUF = ...
        T.P_BESS_kW .* cfg.cost.bess_power_huf_per_kW;

    capexBess_HUF = ...
        capexBessEnergy_HUF + ...
        capexBessPower_HUF;

    opexBessAnnual_HUF = ...
        capexBess_HUF .* cfg.cost.bess_opex_frac_per_year;

    finalSoH = T.finalSoH;
    finalSoH(~isfinite(finalSoH)) = 1;

    deltaSoHTotal = max(0, 1 - finalSoH);
    deltaSoHAnnualEq = deltaSoHTotal ./ simYears;

    eolWindow = cfg.cost.bess_eol_soh_window;

    bessSohCapexAnnual_HUF = ...
        (deltaSoHAnnualEq ./ eolWindow) .* capexBess_HUF;

    bessAnnualCapexOpex_HUF = ...
        bessSohCapexAnnual_HUF + ...
        opexBessAnnual_HUF;

    bessCapexOpexTotal_HUF = ...
        simYears .* bessAnnualCapexOpex_HUF;

    T.capexDc_HUF_per_kWh = ...
        costPars.capexDc_HUF_per_kWh .* ones(height(T), 1);

    T.capexAc_HUF_per_kWh = ...
        costPars.capexAc_HUF_per_kWh .* ones(height(T), 1);

    T.bessCapexEnergyDc_HUF = capexBessEnergyDc_HUF;
    T.bessCapexEnergyAc_HUF = capexBessEnergyAc_HUF;
    T.bessCapexEnergy_HUF = capexBessEnergy_HUF;
    T.bessCapexPower_HUF = capexBessPower_HUF;

    T.finalSoH_pct = 100 .* finalSoH;
    T.deltaSoHTotal = deltaSoHTotal;

    T.bessCapex_HUF = capexBess_HUF;
    T.bessOpexAnnual_HUF = opexBessAnnual_HUF;
    T.bessSohCapexAnnual_HUF = bessSohCapexAnnual_HUF;
    T.bessAnnualCapexOpex_HUF = bessAnnualCapexOpex_HUF;
    T.bessCapexOpexTotal_HUF = bessCapexOpexTotal_HUF;

    T.bessCapex_MHUF = T.bessCapex_HUF ./ 1e6;
    T.bessCapexEnergyDc_MHUF = T.bessCapexEnergyDc_HUF ./ 1e6;
    T.bessCapexEnergyAc_MHUF = T.bessCapexEnergyAc_HUF ./ 1e6;
    T.bessCapexPower_MHUF = T.bessCapexPower_HUF ./ 1e6;
    T.bessCapexOpexTotal_MHUF = T.bessCapexOpexTotal_HUF ./ 1e6;

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

    T.netPresentValue_HUF = T.combinedPeriodNPV_HUF;
    T.netPresentValue_MHUF = T.combinedPeriodNPV_MHUF;

    T.totalOperationalSaving_MHUF = ...
        T.operationalSavingVsZero_HUF ./ 1e6;

    T.annualNetSaving_MHUF_per_year = ...
        T.combinedAnnualNetSaving_HUF ./ 1e6;

    T.discountFactor = ...
        discountFactor .* ones(height(T), 1);

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

    T.marginalStorageValueDc_MHUF_per_kWh = ...
        T.marginalStorageValueDc_HUF_per_kWh ./ 1000;

    T.marginalStorageValueAc_MHUF_per_kWh = ...
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

    T.marginalStorageValue_MHUF_per_kWh = ...
        T.marginalStorageValue_HUF_per_kWh ./ 1e6;
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

            figSpecs(f).plots(p).x = "BESS_PV_ratio_total";
            figSpecs(f).plots(p).y = "bessAcShare_pct";

            figSpecs(f).plots(p).xlabel = ...
                "Teljes BESS/PV arany [kWh/kWp]";

            figSpecs(f).plots(p).ylabel = ...
                "AC-csatolt BESS reszaranya [%]";
        end
    end
end


function figSpecs = local_apply_hybrid_heatmap_styles(figSpecs)

    for f = 1:numel(figSpecs)

        for p = 1:numel(figSpecs(f).plots)

            figSpecs(f).plots(p).heatmapStyle = "soft_points";
            figSpecs(f).plots(p).colormapName = "turbo";

            figSpecs(f).plots(p).markerSize = 420;
            figSpecs(f).plots(p).showContour = false;

            figSpecs(f).plots(p).showValueLabels = true;
            figSpecs(f).plots(p).valueLabelFmt = "%.1f";

            figSpecs(f).plots(p).yTicks = 0:20:100;
            figSpecs(f).plots(p).yLim = [-6 106];

            figSpecs(f).plots(p).xPadFrac = 0.06;
            figSpecs(f).plots(p).hideLegend = true;
        end
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

function local_save_hybrid_best_candidate_table(T, opts)

    pureDcMask = ...
        abs(T.bessAcShare_pct - 0) < 1e-9 & ...
        T.E_BESS_total_kWh > 0;

    pureAcMask = ...
        abs(T.bessAcShare_pct - 100) < 1e-9 & ...
        T.E_BESS_total_kWh > 0;

    mixedMask = ...
        T.bessAcShare_pct > 0 & ...
        T.bessAcShare_pct < 100 & ...
        T.E_BESS_total_kWh > 0;

    bestRows = table();

    bestRows = [bestRows; ...
        local_pick_best_candidate_row(T, pureDcMask, "Legjobb DC-csatolt rendszer")];

    bestRows = [bestRows; ...
        local_pick_best_candidate_row(T, pureAcMask, "Legjobb AC-csatolt rendszer")];

    bestRows = [bestRows; ...
        local_pick_best_candidate_row(T, mixedMask, "Legjobb AC+DC kevert rendszer")];

    outDir = opts.outputFolder;

    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    csvPath = fullfile(outDir, 'hybrid_best_candidates_summary.csv');
    xlsxPath = fullfile(outDir, 'hybrid_best_candidates_summary.xlsx');
    matPath = fullfile(outDir, 'hybrid_best_candidates_summary.mat');

    writetable(bestRows, csvPath);
    writetable(bestRows, xlsxPath);
    save(matPath, 'bestRows', '-v7.3');

    fprintf('\nHybrid best candidate summary saved:\n');
    fprintf('%s\n', csvPath);
    fprintf('%s\n', xlsxPath);
    fprintf('%s\n', matPath);
end


function outRow = local_pick_best_candidate_row(T, mask, categoryName)

    idxPool = find(mask & isfinite(T.netPresentValue_MHUF));

    if isempty(idxPool)
        outRow = local_empty_best_candidate_row(categoryName);
        return;
    end

    [~, bestLocalIdx] = max(T.netPresentValue_MHUF(idxPool));
    idx = idxPool(bestLocalIdx);

    outRow = table();

    outRow.Kategoria = categoryName;
    outRow.Forras_topologia = string(T.sourceCoupling(idx));

    if ismember('candidateID', T.Properties.VariableNames)
        outRow.Jelolt_azonosito = string(T.candidateID(idx));
    else
        outRow.Jelolt_azonosito = "nem_elerheto";
    end

    if ismember('candidateIndex', T.Properties.VariableNames)
        outRow.Jelolt_index = T.candidateIndex(idx);
    else
        outRow.Jelolt_index = idx;
    end

    outRow.Teljes_BESS_PV_arany_kWh_kWp = ...
        T.BESS_PV_ratio_total(idx);

    outRow.AC_csatolt_BESS_reszarany_pct = ...
        T.bessAcShare_pct(idx);

    outRow.Netto_jelenertek_MHUF = ...
        T.netPresentValue_MHUF(idx);

    outRow.BESS_koltseg_MHUF = ...
        T.bessCapexOpexTotal_MHUF(idx);

    outRow.Fajlagos_tarolasi_koltseg_HUF_kWh = ...
        T.storageServiceCost_HUF_per_kWh(idx);

    outRow.Energiakoltseg_megtakaritas_MHUF = ...
        T.energyCostSavingVsZero_MHUF(idx);

    outRow.Teljesitmenydij_megtakaritas_MHUF = ...
        T.performanceSavingVsZero_MHUF(idx);

    outRow.Eves_netto_megtakaritas_MHUF_ev = ...
        T.annualNetSaving_MHUF_per_year(idx);

    outRow.Szerzodott_teljesitmeny_csokkenes_pct = ...
        T.contractReductionVsZero_pct(idx);

    outRow.Marado_halozati_ingadozas_csokkenes_pct = ...
        T.residualLoadVariabilityReduction_pct(idx);

    outRow.Ekvivalens_teljes_ciklus_ev = ...
        T.equivalentFullCycles_per_year(idx);

    outRow.Vegso_SOH_pct = ...
        T.finalSoH_pct(idx);
end


function outRow = local_empty_best_candidate_row(categoryName)

    outRow = table();

    outRow.Kategoria = categoryName;
    outRow.Forras_topologia = "nincs_talalat";
    outRow.Jelolt_azonosito = "nincs_talalat";
    outRow.Jelolt_index = NaN;

    outRow.Teljes_BESS_PV_arany_kWh_kWp = NaN;
    outRow.AC_csatolt_BESS_reszarany_pct = NaN;

    outRow.Netto_jelenertek_MHUF = NaN;
    outRow.BESS_koltseg_MHUF = NaN;
    outRow.Fajlagos_tarolasi_koltseg_HUF_kWh = NaN;
    outRow.Energiakoltseg_megtakaritas_MHUF = NaN;
    outRow.Teljesitmenydij_megtakaritas_MHUF = NaN;
    outRow.Eves_netto_megtakaritas_MHUF_ev = NaN;
    outRow.Szerzodott_teljesitmeny_csokkenes_pct = NaN;
    outRow.Marado_halozati_ingadozas_csokkenes_pct = NaN;
    outRow.Ekvivalens_teljes_ciklus_ev = NaN;
    outRow.Vegso_SOH_pct = NaN;
end




function T = local_add_hybrid_operational_lifetime_metrics(T, cfg)

    simYears = cfg.analysis.simYears;

    T.bessThroughputAnnual_kWh_per_year = ...
        T.bessThroughput_kWh ./ simYears;

    T.equivalentFullCycles_total = ...
        local_safe_divide_vec( ...
            T.bessThroughput_kWh, ...
            2 .* T.E_BESS_kWh);

    T.equivalentFullCycles_per_year = ...
        T.equivalentFullCycles_total ./ simYears;

    T.storageServiceCost_HUF_per_kWh = ...
        local_safe_divide_vec( ...
            T.bessCapexOpexTotal_HUF, ...
            T.bessThroughput_kWh);

    T.storageServiceCost_HUF_per_MWh = ...
        1000 .* T.storageServiceCost_HUF_per_kWh;

    T.lcoe_HUF_per_kWh = T.storageServiceCost_HUF_per_kWh;
    T.lcoe_HUF_per_MWh = T.storageServiceCost_HUF_per_MWh;
end

function local_save_hybrid_best_candidate_cost_bridge_figure(T, opts)

    pureDcMask = ...
        abs(T.bessAcShare_pct - 0) < 1e-9 & ...
        T.E_BESS_total_kWh > 0;

    pureAcMask = ...
        abs(T.bessAcShare_pct - 100) < 1e-9 & ...
        T.E_BESS_total_kWh > 0;

    mixedMask = ...
        T.bessAcShare_pct > 0 & ...
        T.bessAcShare_pct < 100 & ...
        T.E_BESS_total_kWh > 0;

    idxDc = local_pick_best_candidate_index(T, pureDcMask);
    idxAc = local_pick_best_candidate_index(T, pureAcMask);
    idxMixed = local_pick_best_candidate_index(T, mixedMask);

    idxList = [idxDc, idxAc, idxMixed];

    if any(~isfinite(idxList))
        warning('Nem sikerult minden hybrid osszehasonlito abra-jeloltet kivalasztani.');
        return;
    end

    % ---------------------------------------------------------------------
    % No BESS referenciaertekek
    % ---------------------------------------------------------------------

    refContract_kW = local_first_finite(T.bestContract_kW);

    if ismember('contractCostNoBess_HUF', T.Properties.VariableNames)
        refContractCost_HUF = local_first_finite(T.contractCostNoBess_HUF);
    else
        refContractCost_HUF = local_first_finite(T.contractCost_HUF);
    end

    refEnergyCost_HUF = local_first_finite(T.energyCostNoBess_HUF);

    if ismember('overrunCostNoBess_HUF', T.Properties.VariableNames)
        refOverrunCost_HUF = local_first_finite(T.overrunCostNoBess_HUF);
    else
        refOverrunCost_HUF = 0;
    end

    refTotalCost_HUF = ...
        refEnergyCost_HUF + ...
        refContractCost_HUF + ...
        refOverrunCost_HUF;

    if ismember('gridImportNoBess_kWh', T.Properties.VariableNames)
        refGridImport_kWh = local_first_finite(T.gridImportNoBess_kWh);
    else
        error('A hybrid osszehasonlito abrahoz hianyzik a gridImportNoBess_kWh oszlop.');
    end

    % ---------------------------------------------------------------------
    % Relativ mutatok: No BESS = 100 %
    % ---------------------------------------------------------------------

    caseNames = [ ...
        "No BESS"
        "DC BESS"
        "AC BESS"
        "DC+AC BESS"];

    contractedPower_pct = NaN(4, 1);
    totalCost_pct = NaN(4, 1);
    gridEnergyUse_pct = NaN(4, 1);

    contractedPower_pct(1) = 100;
    totalCost_pct(1) = 100;
    gridEnergyUse_pct(1) = 100;

    for k = 1:numel(idxList)

        idx = idxList(k);
        row = k + 1;

        candidateTotalCost_HUF = ...
            T.energyCost_HUF(idx) + ...
            T.contractCost_HUF(idx) + ...
            T.overrunCost_HUF(idx);

        contractedPower_pct(row) = ...
            100 .* T.bestContract_kW(idx) ./ refContract_kW;

        totalCost_pct(row) = ...
            100 .* candidateTotalCost_HUF ./ refTotalCost_HUF;

        gridEnergyUse_pct(row) = ...
            100 .* T.gridImport_kWh(idx) ./ refGridImport_kWh;
    end

    Y = [ ...
        contractedPower_pct, ...
        totalCost_pct, ...
        gridEnergyUse_pct];

    % ---------------------------------------------------------------------
    % Abra
    % ---------------------------------------------------------------------

    fig = figure( ...
        'Name', 'hybrid_best_candidate_relative_comparison', ...
        'Color', 'w', ...
        'Position', [100 100 1050 520]);

    ax = axes(fig);
    hold(ax, 'on');

    b = barh(ax, Y, 'grouped');

    b(1).FaceColor = [0.0000 0.4470 0.7410];
    b(2).FaceColor = [0.8500 0.3250 0.0980];
    b(3).FaceColor = [0.4660 0.6740 0.1880];

    xline(ax, 100, '--', ...
        'No BESS referencia', ...
        'Color', [0.25 0.25 0.25], ...
        'LineWidth', 1.1, ...
        'LabelVerticalAlignment', 'bottom', ...
        'Interpreter', 'none');

    local_add_grouped_barh_value_labels(ax, Y, "%.1f%%");

    yticks(ax, 1:4);
    yticklabels(ax, caseNames);

    xlabel(ax, "Relativ ertek a No BESS esethez kepest [%]", ...
        'Interpreter', 'none');

    title(ax, ...
        "PV+BESS topologiak hatasa a halozati es koltsegmutatokra", ...
        'Interpreter', 'none');

    legend(ax, ...
        b, ...
        [ ...
            "Lekotott teljesitmeny"
            "Teljes villamosenergia-koltseg"
            "Halozati energiafelhasznalas" ...
        ], ...
        'Location', 'southoutside', ...
        'Orientation', 'horizontal', ...
        'Interpreter', 'none');

    grid(ax, 'on');
    ax.GridAlpha = 0.15;
    ax.Box = 'off';
    ax.FontSize = 10;
    ax.Layer = 'top';

    xMax = max(Y(:), [], 'omitnan');
    xlim(ax, [0, max(115, 1.15 .* xMax)]);

    hold(ax, 'off');

    outDir = opts.outputFolder;

    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    pngPath = fullfile(outDir, 'hybrid_legjobb_jeloltek_relativ_osszehasonlitas.png');
    figPath = fullfile(outDir, 'hybrid_legjobb_jeloltek_relativ_osszehasonlitas.fig');

    exportgraphics(fig, pngPath, 'Resolution', 300);
    savefig(fig, figPath);

    fprintf('\nHybrid relative comparison figure saved:\n');
    fprintf('%s\n', pngPath);
    fprintf('%s\n', figPath);
end

function local_add_grouped_barh_value_labels(ax, Y, fmt)

    nGroups = size(Y, 1);
    nBars = size(Y, 2);

    groupWidth = min(0.8, nBars / (nBars + 1.5));

    for i = 1:nGroups

        for j = 1:nBars

            value = Y(i, j);

            if ~isfinite(value)
                continue;
            end

            y = i - groupWidth / 2 + ...
                (2 * j - 1) * groupWidth / (2 * nBars);

            text(ax, value + 1.0, y, sprintf(fmt, value), ...
                'HorizontalAlignment', 'left', ...
                'VerticalAlignment', 'middle', ...
                'FontSize', 8.5, ...
                'Color', [0.15 0.15 0.15], ...
                'Interpreter', 'none');
        end
    end
end


function local_add_stacked_bar_value_labels(ax, x, yStack, fmt)

    yBottom = zeros(size(x(:)));

    for j = 1:size(yStack, 2)

        values = yStack(:, j);

        for i = 1:numel(x)

            if ~isfinite(values(i)) || abs(values(i)) < 1e-9
                continue;
            end

            y = yBottom(i) + values(i) / 2;

            text(ax, x(i), y, sprintf(fmt, values(i)), ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontSize', 8.5, ...
                'Color', [0.15 0.15 0.15], ...
                'Interpreter', 'none');
        end

        yBottom = yBottom + values;
    end
end


function idx = local_pick_best_candidate_index(T, mask)

    idxPool = find(mask & isfinite(T.netPresentValue_MHUF));

    if isempty(idxPool)
        idx = NaN;
        return;
    end

    [~, bestLocalIdx] = max(T.netPresentValue_MHUF(idxPool));
    idx = idxPool(bestLocalIdx);
end


function simYears = local_get_sim_years_from_table(T)

    if ismember('simYears', T.Properties.VariableNames)
        simYears = local_first_finite(T.simYears);
    elseif ismember('simulationYears', T.Properties.VariableNames)
        simYears = local_first_finite(T.simulationYears);
    elseif ismember('LifetimeYears', T.Properties.VariableNames)
        simYears = local_first_finite(T.LifetimeYears);
    else
        simYears = 4;
    end
end


function local_add_bar_value_labels(ax, x, value, bottom, fmt)

    for i = 1:numel(x)

        if ~isfinite(value(i)) || abs(value(i)) < 1e-9
            continue;
        end

        y = bottom(i) + value(i) / 2;

        text(ax, x(i), y, sprintf(fmt, value(i)), ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 8.5, ...
            'Color', [0.15 0.15 0.15], ...
            'Interpreter', 'none');
    end
end