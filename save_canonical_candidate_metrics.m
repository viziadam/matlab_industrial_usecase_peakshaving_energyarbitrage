function [candidateMetricsImportant, candidateMetricsDetailed] = save_canonical_candidate_metrics(DB, cfg)
% SAVE_CANONICAL_CANDIDATE_METRICS
%
% Egységes candidate-szintű kiértékelési cache mentése.
%
% Mentett táblák:
%   candidateMetricsImportant
%       - dolgozati / gyors kiértékelési metrikák
%
%   candidateMetricsDetailed
%       - teljes candidateTable minden oszloppal, plusz egységesített
%         AC/DC BESS split metrikák
%
%   candidateMetrics
%       - kompatibilitási alias, ugyanaz mint candidateMetricsDetailed

    if ~isfield(DB, 'candidateTable') || isempty(DB.candidateTable)
        error('DB.candidateTable is missing or empty.');
    end

    T = DB.candidateTable;

    coupling = lower(string(cfg.system.bessCoupling));
    objectiveMode = lower(string(cfg.dispatch.objectiveMode));

    cacheDir = fullfile(cfg.paths.results, 'evaluation_cache');

    if ~exist(cacheDir, 'dir')
        mkdir(cacheDir);
    end

    matPath = fullfile(cacheDir, sprintf( ...
        'candidate_metrics_%s_%s.mat', coupling, objectiveMode));

    csvImportantPath = fullfile(cacheDir, sprintf( ...
        'candidate_metrics_important_%s_%s.csv', coupling, objectiveMode));

    csvDetailedPath = fullfile(cacheDir, sprintf( ...
        'candidate_metrics_detailed_%s_%s.csv', coupling, objectiveMode));

    rowsToSave = local_get_rows_to_save(T);

    if isempty(rowsToSave)
        fprintf('\nNo simulated candidate rows found for canonical metric cache.\n');
        candidateMetricsImportant = table();
        candidateMetricsDetailed = table();
        candidateMetrics = candidateMetricsDetailed; %#ok<NASGU>
        save(matPath, ...
            'candidateMetrics', ...
            'candidateMetricsImportant', ...
            'candidateMetricsDetailed', ...
            '-v7.3');
        return;
    end

    newDetailed = local_build_detailed_table(T, rowsToSave, coupling, objectiveMode, cfg);
    newImportant = local_build_important_table(newDetailed);

    if exist(matPath, 'file')
        S = load(matPath);

        if isfield(S, 'candidateMetricsDetailed')
            oldDetailed = S.candidateMetricsDetailed;
        elseif isfield(S, 'candidateMetrics')
            oldDetailed = S.candidateMetrics;
        else
            oldDetailed = table();
        end

        if isfield(S, 'candidateMetricsImportant')
            oldImportant = S.candidateMetricsImportant;
        else
            oldImportant = table();
        end
    else
        oldDetailed = table();
        oldImportant = table();
    end

    candidateMetricsDetailed = local_upsert_metrics(oldDetailed, newDetailed);
    candidateMetricsImportant = local_upsert_metrics(oldImportant, newImportant);

    candidateMetrics = candidateMetricsDetailed; %#ok<NASGU>

    save(matPath, ...
        'candidateMetrics', ...
        'candidateMetricsImportant', ...
        'candidateMetricsDetailed', ...
        '-v7.3');

    writetable(candidateMetricsImportant, csvImportantPath);
    writetable(candidateMetricsDetailed, csvDetailedPath);

    fprintf('\nCanonical candidate metric cache saved:\n%s\n', matPath);
end


function rowsToSave = local_get_rows_to_save(T)

    n = height(T);

    if ismember('wasSimulated', T.Properties.VariableNames)
        rowsToSave = find(T.wasSimulated == true);
    else
        rowsToSave = (1:n).';
    end

    if ismember('hasError', T.Properties.VariableNames)
        rowsToSave = rowsToSave(T.hasError(rowsToSave) == false);
    end

    rowsToSave = rowsToSave(:);
end


function M = local_build_detailed_table(T, rows, coupling, objectiveMode, cfg)

    M = T(rows, :);

    n = height(M);

    if ~ismember('objectiveMode', M.Properties.VariableNames)
        M.objectiveMode = repmat(objectiveMode, n, 1);
    end

    if ~ismember('coupling', M.Properties.VariableNames)
        M.coupling = repmat(coupling, n, 1);
    end

    if ~ismember('candidateIndex', M.Properties.VariableNames)
        M.candidateIndex = rows(:);
    end

    if ~ismember('candidateID', M.Properties.VariableNames)
        M.candidateID = strings(n, 1);

        for i = 1:n
            M.candidateID(i) = sprintf('candidate_%06d', rows(i));
        end
    else
        M.candidateID = string(M.candidateID);
    end

    M.objectiveMode = string(M.objectiveMode);
    M.coupling = string(M.coupling);

    M = local_add_consistency_metrics(M, cfg);
    M = local_add_canonical_bess_split_metrics(M);
end


function M = local_build_important_table(D)

    keepCols = { ...
        'objectiveMode', ...
        'coupling', ...
        'candidateIndex', ...
        'candidateID', ...
        'BESS_PV_ratio', ...
        'BESS_PV_ratio_dc', ...
        'BESS_PV_ratio_ac', ...
        'BESS_PV_ratio_total', ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'E_BESS_dc_kWh', ...
        'P_BESS_dc_kW', ...
        'E_BESS_ac_kWh', ...
        'P_BESS_ac_kW', ...
        'bestContract_kW', ...
        'finalSoC', ...
        'finalSoH', ...
        'finalSoH_pct', ...
        'finalSoCDc', ...
        'finalSoCAc', ...
        'finalSoHDc', ...
        'finalSoHAc', ...
        'loadEnergy_kWh', ...
        'pvEnergyAvailable_kWh', ...
        'gridImportNoBess_kWh', ...
        'gridImport_kWh', ...
        'gridImportReduction_kWh', ...
        'gridImportReduction_pct', ...
        'gridToLoad_kWh', ...
        'pvToLoad_kWh', ...
        'bessToLoad_kWh', ...
        'bessDcToLoad_kWh', ...
        'bessAcToLoad_kWh', ...
        'gridToBess_kWh', ...
        'gridToBessDc_kWh', ...
        'gridToBessAc_kWh', ...
        'gridToBessStored_kWh', ...
        'gridToBessStoredDc_kWh', ...
        'gridToBessStoredAc_kWh', ...
        'gridToBessLoss_kWh', ...
        'gridToBessLossDc_kWh', ...
        'gridToBessLossAc_kWh', ...
        'pvToBess_kWh', ...
        'pvToBessDc_kWh', ...
        'pvToBessAc_kWh', ...
        'pvToBessStored_kWh', ...
        'pvToBessStoredDc_kWh', ...
        'pvToBessStoredAc_kWh', ...
        'pvToBessLoss_kWh', ...
        'pvToBessLossDc_kWh', ...
        'pvToBessLossAc_kWh', ...
        'bessCharge_kWh', ...
        'bessChargeDc_kWh', ...
        'bessChargeAc_kWh', ...
        'bessDischarge_kWh', ...
        'bessDischargeDc_kWh', ...
        'bessDischargeAc_kWh', ...
        'bessThroughput_kWh', ...
        'bessThroughputDc_kWh', ...
        'bessThroughputAc_kWh', ...
        'bessDischargeBeforeConversion_kWh', ...
        'bessDischargeBeforeConversionDc_kWh', ...
        'bessDischargeBeforeConversionAc_kWh', ...
        'bessToLoadConversionLoss_kWh', ...
        'bessToLoadConversionLossDc_kWh', ...
        'bessToLoadConversionLossAc_kWh', ...
        'centralInverterLoss_kWh', ...
        'centralInvDcToAcLoss_kWh', ...
        'centralInvAcToDcLoss_kWh', ...
        'dcdcLoss_kWh', ...
        'dcdcLossDc_kWh', ...
        'dcdcLossAc_kWh', ...
        'dcdcChargeLoss_kWh', ...
        'dcdcChargeLossDc_kWh', ...
        'dcdcChargeLossAc_kWh', ...
        'dcdcDischargeLoss_kWh', ...
        'dcdcDischargeLossDc_kWh', ...
        'dcdcDischargeLossAc_kWh', ...
        'pcsbInverterLoss_kWh', ...
        'pcsbInverterLossDc_kWh', ...
        'pcsbInverterLossAc_kWh', ...
        'pcsbChargeLoss_kWh', ...
        'pcsbChargeLossDc_kWh', ...
        'pcsbChargeLossAc_kWh', ...
        'pcsbDischargeLoss_kWh', ...
        'pcsbDischargeLossDc_kWh', ...
        'pcsbDischargeLossAc_kWh', ...
        'bessInternalLoss_kWh', ...
        'bessInternalLossDc_kWh', ...
        'bessInternalLossAc_kWh', ...
        'bessInternalChargeLoss_kWh', ...
        'bessInternalChargeLossDc_kWh', ...
        'bessInternalChargeLossAc_kWh', ...
        'bessInternalDischargeLoss_kWh', ...
        'bessInternalDischargeLossDc_kWh', ...
        'bessInternalDischargeLossAc_kWh', ...
        'totalConverterLoss_kWh', ...
        'curtailment_kWh', ...
        'energyCostNoBess_HUF', ...
        'energyCost_HUF', ...
        'energyCostSaving_HUF', ...
        'degradationCost_HUF', ...
        'degradationCostCorrected_HUF', ...
        'overrunCost_HUF', ...
        'contractCost_HUF', ...
        'objectiveCost_HUF', ...
        'gridToBessChargeEfficiency_pct', ...
        'gridToBessChargeEfficiencyDc_pct', ...
        'gridToBessChargeEfficiencyAc_pct', ...
        'pvToBessChargeEfficiency_pct', ...
        'pvToBessChargeEfficiencyDc_pct', ...
        'pvToBessChargeEfficiencyAc_pct', ...
        'bessDischargeToLoadEfficiency_pct', ...
        'bessDischargeToLoadEfficiencyDc_pct', ...
        'bessDischargeToLoadEfficiencyAc_pct', ...
        'gridToBessToLoadEfficiency_pct', ...
        'pvToBessToLoadEfficiency_pct', ...
        'maxLoadPeak_kW', ...
        'maxPVPeak_kW', ...
        'maxGridImportPeak_kW', ...
        'maxGridImportNoBessPeak_kW', ...
        'maxBessChargePeak_kW', ...
        'maxBessDischargePeak_kW', ...
        'equivalentCycles', ...
        'equivalentCyclesDc', ...
        'equivalentCyclesAc' ...
    };

    M = table();

    for i = 1:numel(keepCols)
        col = keepCols{i};

        if ismember(col, D.Properties.VariableNames)
            M.(col) = D.(col);
        end
    end
end


function T = local_add_consistency_metrics(T, cfg)

    if ismember('finalSoH', T.Properties.VariableNames)
        T.finalSoH_pct = T.finalSoH;

        mask = isfinite(T.finalSoH_pct) & T.finalSoH_pct <= 1.5;
        T.finalSoH_pct(mask) = 100 .* T.finalSoH_pct(mask);
    end

    if all(ismember({'gridImportNoBess_kWh', 'gridImport_kWh'}, T.Properties.VariableNames))
        T.gridImportReduction_kWh = T.gridImportNoBess_kWh - T.gridImport_kWh;
        T.gridImportReduction_pct = 100 .* local_safe_divide( ...
            T.gridImportReduction_kWh, ...
            T.gridImportNoBess_kWh);
    end

    if all(ismember({'gridToBessStored_kWh', 'gridToBess_kWh'}, T.Properties.VariableNames))
        T.gridToBessChargeEfficiency_pct = 100 .* local_safe_divide( ...
            T.gridToBessStored_kWh, ...
            T.gridToBess_kWh);
    end

    if all(ismember({'pvToBessStored_kWh', 'pvToBess_kWh'}, T.Properties.VariableNames))
        T.pvToBessChargeEfficiency_pct = 100 .* local_safe_divide( ...
            T.pvToBessStored_kWh, ...
            T.pvToBess_kWh);
    end

    if all(ismember({'bessToLoad_kWh', 'bessDischargeBeforeConversion_kWh'}, T.Properties.VariableNames))
        T.bessDischargeToLoadEfficiency_pct = 100 .* local_safe_divide( ...
            T.bessToLoad_kWh, ...
            T.bessDischargeBeforeConversion_kWh);
    end

    if all(ismember({'gridToBessChargeEfficiency_pct', 'bessDischargeToLoadEfficiency_pct'}, T.Properties.VariableNames))
        T.gridToBessToLoadEfficiency_pct = ...
            T.gridToBessChargeEfficiency_pct .* ...
            T.bessDischargeToLoadEfficiency_pct ./ 100;
    end

    if all(ismember({'pvToBessChargeEfficiency_pct', 'bessDischargeToLoadEfficiency_pct'}, T.Properties.VariableNames))
        T.pvToBessToLoadEfficiency_pct = ...
            T.pvToBessChargeEfficiency_pct .* ...
            T.bessDischargeToLoadEfficiency_pct ./ 100;
    end

    if all(ismember({'centralInvDcToAcLoss_kWh', ...
                     'centralInvAcToDcLoss_kWh', ...
                     'dcdcChargeLoss_kWh', ...
                     'dcdcDischargeLoss_kWh', ...
                     'pcsbChargeLoss_kWh', ...
                     'pcsbDischargeLoss_kWh'}, T.Properties.VariableNames))

        T.totalConverterLossFromSplit_kWh = ...
            T.centralInvDcToAcLoss_kWh + ...
            T.centralInvAcToDcLoss_kWh + ...
            T.dcdcChargeLoss_kWh + ...
            T.dcdcDischargeLoss_kWh + ...
            T.pcsbChargeLoss_kWh + ...
            T.pcsbDischargeLoss_kWh;
    end

    if all(ismember({'E_BESS_kWh', 'P_BESS_kW'}, T.Properties.VariableNames))

        costPars = local_get_bess_cost_parameters_from_cfg(cfg);

        T.capexBESSEnergy_HUF = ...
            T.E_BESS_kWh .* costPars.bess_huf_per_kWh;

        T.capexBESSPower_HUF = ...
            T.P_BESS_kW .* costPars.bess_power_huf_per_kW;

        T.capexBESS_HUF = ...
            T.capexBESSEnergy_HUF + ...
            T.capexBESSPower_HUF;
    end

    if all(ismember({'finalSoH', 'capexBESS_HUF'}, T.Properties.VariableNames))

        costPars = local_get_bess_cost_parameters_from_cfg(cfg);

        T.degradationCostCorrected_HUF = ...
            max(0, (1 - T.finalSoH) ./ costPars.bess_eol_soh_window) .* ...
            T.capexBESS_HUF;

        noBessMask = false(height(T), 1);

        if ismember('E_BESS_kWh', T.Properties.VariableNames)
            noBessMask = noBessMask | T.E_BESS_kWh <= 0;
        end

        if ismember('P_BESS_kW', T.Properties.VariableNames)
            noBessMask = noBessMask | T.P_BESS_kW <= 0;
        end

        T.degradationCostCorrected_HUF(noBessMask) = NaN;
    end
end


function T = local_add_canonical_bess_split_metrics(T)
% LOCAL_ADD_CANONICAL_BESS_SPLIT_METRICS
% Adds a canonical AC/DC split layer for BESS-related candidate metrics.
% Hybrid simulations already contain several native split fields; missing
% split fields are derived from the available aggregate and split quantities.
% For single-coupling runs this also creates the same columns, with the
% inactive side set to zero. This makes later AC/DC/hybrid comparison simple.

    n = height(T);

    if ~ismember('coupling', T.Properties.VariableNames)
        T.coupling = repmat("unknown", n, 1);
    end

    coupling = lower(string(T.coupling));
    isDc = coupling == "dc";
    isAc = coupling == "ac";
    isHybrid = coupling == "hybrid";

    % ------------------------------------------------------------------
    % Size/design split aliases
    % ------------------------------------------------------------------
    T = local_fill_split_pair(T, 'E_BESS_kWh', 'E_BESS_dc_kWh', 'E_BESS_ac_kWh', isDc, isAc, isHybrid);
    T = local_fill_split_pair(T, 'P_BESS_kW', 'P_BESS_dc_kW', 'P_BESS_ac_kW', isDc, isAc, isHybrid);
    T = local_fill_split_pair(T, 'BESS_PV_ratio', 'BESS_PV_ratio_dc', 'BESS_PV_ratio_ac', isDc, isAc, isHybrid);

    if ~ismember('BESS_PV_ratio_total', T.Properties.VariableNames)
        if all(ismember({'BESS_PV_ratio_dc', 'BESS_PV_ratio_ac'}, T.Properties.VariableNames))
            T.BESS_PV_ratio_total = T.BESS_PV_ratio_dc + T.BESS_PV_ratio_ac;
        elseif ismember('BESS_PV_ratio', T.Properties.VariableNames)
            T.BESS_PV_ratio_total = T.BESS_PV_ratio;
        else
            T.BESS_PV_ratio_total = NaN(n, 1);
        end
    end

    % ------------------------------------------------------------------
    % Direct BESS energy split fields
    % ------------------------------------------------------------------
    T = local_fill_split_pair(T, 'gridToBess_kWh', 'gridToBessDc_kWh', 'gridToBessAc_kWh', isDc, isAc, isHybrid);
    T = local_fill_split_pair(T, 'pvToBess_kWh', 'pvToBessDc_kWh', 'pvToBessAc_kWh', isDc, isAc, isHybrid);
    T = local_fill_split_pair(T, 'bessToLoad_kWh', 'bessDcToLoad_kWh', 'bessAcToLoad_kWh', isDc, isAc, isHybrid);
    T = local_fill_split_pair(T, 'bessCharge_kWh', 'bessChargeDc_kWh', 'bessChargeAc_kWh', isDc, isAc, isHybrid);
    T = local_fill_split_pair(T, 'bessDischarge_kWh', 'bessDischargeDc_kWh', 'bessDischargeAc_kWh', isDc, isAc, isHybrid);

    T.bessThroughputDc_kWh = local_col(T, 'bessChargeDc_kWh', n) + local_col(T, 'bessDischargeDc_kWh', n);
    T.bessThroughputAc_kWh = local_col(T, 'bessChargeAc_kWh', n) + local_col(T, 'bessDischargeAc_kWh', n);

    if ~ismember('bessThroughput_kWh', T.Properties.VariableNames)
        T.bessThroughput_kWh = T.bessThroughputDc_kWh + T.bessThroughputAc_kWh;
    end

    % ------------------------------------------------------------------
    % Charge-source stored/loss split fields
    % ------------------------------------------------------------------
    [T.gridToBessStoredDc_kWh, T.gridToBessStoredAc_kWh] = local_split_source_stored( ...
        local_col(T, 'gridToBessStored_kWh', n), ...
        local_col(T, 'gridToBessDc_kWh', n), ...
        local_col(T, 'gridToBessAc_kWh', n), ...
        local_col(T, 'bessChargeDc_kWh', n), ...
        local_col(T, 'bessChargeAc_kWh', n), ...
        isDc, isAc, isHybrid);

    [T.pvToBessStoredDc_kWh, T.pvToBessStoredAc_kWh] = local_split_source_stored( ...
        local_col(T, 'pvToBessStored_kWh', n), ...
        local_col(T, 'pvToBessDc_kWh', n), ...
        local_col(T, 'pvToBessAc_kWh', n), ...
        local_col(T, 'bessChargeDc_kWh', n), ...
        local_col(T, 'bessChargeAc_kWh', n), ...
        isDc, isAc, isHybrid);

    T.gridToBessLossDc_kWh = max(local_col(T, 'gridToBessDc_kWh', n) - T.gridToBessStoredDc_kWh, 0);
    T.gridToBessLossAc_kWh = max(local_col(T, 'gridToBessAc_kWh', n) - T.gridToBessStoredAc_kWh, 0);
    T.pvToBessLossDc_kWh = max(local_col(T, 'pvToBessDc_kWh', n) - T.pvToBessStoredDc_kWh, 0);
    T.pvToBessLossAc_kWh = max(local_col(T, 'pvToBessAc_kWh', n) - T.pvToBessStoredAc_kWh, 0);

    % ------------------------------------------------------------------
    % Discharge-side split fields
    % ------------------------------------------------------------------
    T = local_fill_split_pair(T, 'bessDischargeBeforeConversion_kWh', ...
        'bessDischargeBeforeConversionDc_kWh', 'bessDischargeBeforeConversionAc_kWh', ...
        isDc, isAc, isHybrid);

    if all(ismember({'bessDischargeDc_kWh', 'bessDischargeAc_kWh'}, T.Properties.VariableNames))
        T.bessDischargeBeforeConversionDc_kWh(isHybrid) = T.bessDischargeDc_kWh(isHybrid);
        T.bessDischargeBeforeConversionAc_kWh(isHybrid) = T.bessDischargeAc_kWh(isHybrid);
    end

    T.bessToLoadConversionLossDc_kWh = max(T.bessDischargeBeforeConversionDc_kWh - local_col(T, 'bessDcToLoad_kWh', n), 0);
    T.bessToLoadConversionLossAc_kWh = max(T.bessDischargeBeforeConversionAc_kWh - local_col(T, 'bessAcToLoad_kWh', n), 0);

    if ismember('bessToLoadConversionLoss_kWh', T.Properties.VariableNames)
        totalDerived = T.bessToLoadConversionLossDc_kWh + T.bessToLoadConversionLossAc_kWh;
        missingDerived = ~isfinite(totalDerived) | totalDerived <= 1e-12;
        sourceLoss = T.bessToLoadConversionLoss_kWh;
        T.bessToLoadConversionLossDc_kWh(isDc & missingDerived) = sourceLoss(isDc & missingDerived);
        T.bessToLoadConversionLossAc_kWh(isAc & missingDerived) = sourceLoss(isAc & missingDerived);
    else
        T.bessToLoadConversionLoss_kWh = T.bessToLoadConversionLossDc_kWh + T.bessToLoadConversionLossAc_kWh;
    end

    % ------------------------------------------------------------------
    % Converter split fields by physical side
    % ------------------------------------------------------------------
    T.dcdcLossDc_kWh = local_col(T, 'dcdcLoss_kWh', n);
    T.dcdcLossAc_kWh = zeros(n, 1);
    T.dcdcChargeLossDc_kWh = local_col(T, 'dcdcChargeLoss_kWh', n);
    T.dcdcChargeLossAc_kWh = zeros(n, 1);
    T.dcdcDischargeLossDc_kWh = local_col(T, 'dcdcDischargeLoss_kWh', n);
    T.dcdcDischargeLossAc_kWh = zeros(n, 1);

    T.pcsbInverterLossDc_kWh = zeros(n, 1);
    T.pcsbInverterLossAc_kWh = local_col(T, 'pcsbInverterLoss_kWh', n);
    T.pcsbChargeLossDc_kWh = zeros(n, 1);
    T.pcsbChargeLossAc_kWh = local_col(T, 'pcsbChargeLoss_kWh', n);
    T.pcsbDischargeLossDc_kWh = zeros(n, 1);
    T.pcsbDischargeLossAc_kWh = local_col(T, 'pcsbDischargeLoss_kWh', n);

    % ------------------------------------------------------------------
    % Internal BESS loss split fields
    % ------------------------------------------------------------------
    T = local_fill_split_pair(T, 'bessInternalLoss_kWh', ...
        'bessInternalLossDc_kWh', 'bessInternalLossAc_kWh', isDc, isAc, isHybrid);

    [T.bessInternalChargeLossDc_kWh, T.bessInternalChargeLossAc_kWh] = local_split_internal_loss_by_energy( ...
        local_col(T, 'bessInternalChargeLoss_kWh', n), ...
        local_col(T, 'bessInternalLossDc_kWh', n), ...
        local_col(T, 'bessInternalLossAc_kWh', n), ...
        local_col(T, 'bessChargeDc_kWh', n), ...
        local_col(T, 'bessChargeAc_kWh', n), ...
        isDc, isAc, isHybrid);

    [T.bessInternalDischargeLossDc_kWh, T.bessInternalDischargeLossAc_kWh] = local_split_internal_loss_by_energy( ...
        local_col(T, 'bessInternalDischargeLoss_kWh', n), ...
        local_col(T, 'bessInternalLossDc_kWh', n), ...
        local_col(T, 'bessInternalLossAc_kWh', n), ...
        local_col(T, 'bessDischargeDc_kWh', n), ...
        local_col(T, 'bessDischargeAc_kWh', n), ...
        isDc, isAc, isHybrid);

    % ------------------------------------------------------------------
    % Split efficiencies and equivalent cycles
    % ------------------------------------------------------------------
    T.gridToBessChargeEfficiencyDc_pct = 100 .* local_safe_divide(T.gridToBessStoredDc_kWh, local_col(T, 'gridToBessDc_kWh', n));
    T.gridToBessChargeEfficiencyAc_pct = 100 .* local_safe_divide(T.gridToBessStoredAc_kWh, local_col(T, 'gridToBessAc_kWh', n));
    T.pvToBessChargeEfficiencyDc_pct = 100 .* local_safe_divide(T.pvToBessStoredDc_kWh, local_col(T, 'pvToBessDc_kWh', n));
    T.pvToBessChargeEfficiencyAc_pct = 100 .* local_safe_divide(T.pvToBessStoredAc_kWh, local_col(T, 'pvToBessAc_kWh', n));
    T.bessDischargeToLoadEfficiencyDc_pct = 100 .* local_safe_divide(local_col(T, 'bessDcToLoad_kWh', n), T.bessDischargeBeforeConversionDc_kWh);
    T.bessDischargeToLoadEfficiencyAc_pct = 100 .* local_safe_divide(local_col(T, 'bessAcToLoad_kWh', n), T.bessDischargeBeforeConversionAc_kWh);

    T.equivalentCyclesDc = local_safe_divide(T.bessThroughputDc_kWh, 2 .* local_col(T, 'E_BESS_dc_kWh', n));
    T.equivalentCyclesAc = local_safe_divide(T.bessThroughputAc_kWh, 2 .* local_col(T, 'E_BESS_ac_kWh', n));
end


function T = local_fill_split_pair(T, totalName, dcName, acName, isDc, isAc, isHybrid)

    n = height(T);
    total = local_col(T, totalName, n);

    if ~ismember(dcName, T.Properties.VariableNames)
        T.(dcName) = NaN(n, 1);
    end

    if ~ismember(acName, T.Properties.VariableNames)
        T.(acName) = NaN(n, 1);
    end

    dc = T.(dcName);
    ac = T.(acName);

    dc(isDc) = total(isDc);
    ac(isDc) = 0;

    dc(isAc) = 0;
    ac(isAc) = total(isAc);

    missingHybridDc = isHybrid & (~isfinite(dc));
    missingHybridAc = isHybrid & (~isfinite(ac));
    dc(missingHybridDc) = 0;
    ac(missingHybridAc) = 0;

    T.(dcName) = dc;
    T.(acName) = ac;
end


function [storedDc, storedAc] = local_split_source_stored(totalStored, sourceDc, sourceAc, chargeDc, chargeAc, isDc, isAc, isHybrid)

    n = numel(totalStored);
    storedDc = NaN(n, 1);
    storedAc = NaN(n, 1);

    storedDc(isDc) = totalStored(isDc);
    storedAc(isDc) = 0;
    storedDc(isAc) = 0;
    storedAc(isAc) = totalStored(isAc);

    denom = sourceDc + sourceAc;
    splitMask = isHybrid & isfinite(totalStored) & denom > 1e-12;
    storedDc(splitMask) = totalStored(splitMask) .* sourceDc(splitMask) ./ denom(splitMask);
    storedAc(splitMask) = totalStored(splitMask) .* sourceAc(splitMask) ./ denom(splitMask);

    noSourceMask = isHybrid & ~(denom > 1e-12);
    chargeDenom = chargeDc + chargeAc;
    chargeMask = noSourceMask & isfinite(totalStored) & chargeDenom > 1e-12;
    storedDc(chargeMask) = totalStored(chargeMask) .* chargeDc(chargeMask) ./ chargeDenom(chargeMask);
    storedAc(chargeMask) = totalStored(chargeMask) .* chargeAc(chargeMask) ./ chargeDenom(chargeMask);

    zeroMask = isHybrid & (~isfinite(storedDc) | ~isfinite(storedAc));
    storedDc(zeroMask) = 0;
    storedAc(zeroMask) = 0;
end


function [lossDc, lossAc] = local_split_internal_loss_by_energy(totalLoss, internalDc, internalAc, energyDc, energyAc, isDc, isAc, isHybrid)

    n = numel(totalLoss);
    lossDc = NaN(n, 1);
    lossAc = NaN(n, 1);

    lossDc(isDc) = totalLoss(isDc);
    lossAc(isDc) = 0;
    lossDc(isAc) = 0;
    lossAc(isAc) = totalLoss(isAc);

    denom = internalDc + internalAc;
    splitMask = isHybrid & isfinite(totalLoss) & denom > 1e-12;
    lossDc(splitMask) = totalLoss(splitMask) .* internalDc(splitMask) ./ denom(splitMask);
    lossAc(splitMask) = totalLoss(splitMask) .* internalAc(splitMask) ./ denom(splitMask);

    energyDenom = energyDc + energyAc;
    energyMask = isHybrid & (~isfinite(lossDc) | ~isfinite(lossAc)) & isfinite(totalLoss) & energyDenom > 1e-12;
    lossDc(energyMask) = totalLoss(energyMask) .* energyDc(energyMask) ./ energyDenom(energyMask);
    lossAc(energyMask) = totalLoss(energyMask) .* energyAc(energyMask) ./ energyDenom(energyMask);

    zeroMask = isHybrid & (~isfinite(lossDc) | ~isfinite(lossAc));
    lossDc(zeroMask) = 0;
    lossAc(zeroMask) = 0;
end


function x = local_col(T, colName, n)

    if ismember(colName, T.Properties.VariableNames)
        x = T.(colName);
    else
        x = NaN(n, 1);
    end

    x = x(:);

    if numel(x) ~= n
        error('Column length mismatch for %s. Expected %d, got %d.', colName, n, numel(x));
    end
end


function out = local_upsert_metrics(oldMetrics, newMetrics)

    if isempty(oldMetrics)
        out = newMetrics;
        return;
    end

    oldMetrics = local_align_table_variables(oldMetrics, newMetrics);
    newMetrics = local_align_table_variables(newMetrics, oldMetrics);

    oldKey = local_make_key(oldMetrics);
    newKey = local_make_key(newMetrics);

    keepOld = ~ismember(oldKey, newKey);

    out = [oldMetrics(keepOld, :); newMetrics];

    [~, order] = sortrows([string(out.coupling), out.candidateIndex]);
    out = out(order, :);
end


function T1 = local_align_table_variables(T1, T2)

    vars1 = string(T1.Properties.VariableNames);
    vars2 = string(T2.Properties.VariableNames);

    missingInT1 = setdiff(vars2, vars1, 'stable');

    for i = 1:numel(missingInT1)
        name = char(missingInT1(i));

        if isnumeric(T2.(name))
            T1.(name) = NaN(height(T1), 1);
        elseif islogical(T2.(name))
            T1.(name) = false(height(T1), 1);
        elseif isstring(T2.(name))
            T1.(name) = strings(height(T1), 1);
        else
            T1.(name) = cell(height(T1), 1);
        end
    end

    T1 = T1(:, T2.Properties.VariableNames);
end


function key = local_make_key(T)

    key = string(T.objectiveMode) ...
        + "|" + string(T.coupling) ...
        + "|" + string(T.candidateID);
end


function y = local_safe_divide(a, b)
    y = NaN(size(a));

    mask = isfinite(a) & isfinite(b) & abs(b) > 1e-12;
    y(mask) = a(mask) ./ b(mask);
end

function costPars = local_get_bess_cost_parameters_from_cfg(cfg)

    if ~isfield(cfg, 'cost')
        error('Missing cfg.cost structure for BESS CAPEX and degradation cost evaluation.');
    end

    requiredCostFields = { ...
        'bess_huf_per_kWh', ...
        'bess_power_huf_per_kW', ...
        'bess_eol_soh_window'};

    for i = 1:numel(requiredCostFields)

        fieldName = requiredCostFields{i};

        if ~isfield(cfg.cost, fieldName)
            error('Missing cfg.cost.%s. Define it in create_configurations.m.', fieldName);
        end

        if ~isnumeric(cfg.cost.(fieldName)) || ~isscalar(cfg.cost.(fieldName))
            error('cfg.cost.%s must be a numeric scalar.', fieldName);
        end
    end

    if cfg.cost.bess_huf_per_kWh < 0
        error('cfg.cost.bess_huf_per_kWh must be non-negative.');
    end

    if cfg.cost.bess_power_huf_per_kW < 0
        error('cfg.cost.bess_power_huf_per_kW must be non-negative.');
    end

    if cfg.cost.bess_eol_soh_window <= 0
        error('cfg.cost.bess_eol_soh_window must be positive. Example: 0.2 for 100%% -> 80%% SoH.');
    end

    costPars = struct();

    costPars.bess_huf_per_kWh = cfg.cost.bess_huf_per_kWh;
    costPars.bess_power_huf_per_kW = cfg.cost.bess_power_huf_per_kW;
    costPars.bess_eol_soh_window = cfg.cost.bess_eol_soh_window;
end