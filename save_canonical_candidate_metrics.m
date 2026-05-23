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
%       - teljes candidateTable minden oszloppal
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
end


function M = local_build_important_table(D)

    keepCols = { ...
        'objectiveMode', ...
        'coupling', ...
        'candidateIndex', ...
        'candidateID', ...
        'BESS_PV_ratio', ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'bestContract_kW', ...
        'finalSoC', ...
        'finalSoH', ...
        'finalSoH_pct', ...
        'loadEnergy_kWh', ...
        'pvEnergyAvailable_kWh', ...
        'gridImportNoBess_kWh', ...
        'gridImport_kWh', ...
        'gridImportReduction_kWh', ...
        'gridImportReduction_pct', ...
        'gridToLoad_kWh', ...
        'pvToLoad_kWh', ...
        'bessToLoad_kWh', ...
        'gridToBess_kWh', ...
        'gridToBessStored_kWh', ...
        'gridToBessLoss_kWh', ...
        'pvToBess_kWh', ...
        'pvToBessStored_kWh', ...
        'pvToBessLoss_kWh', ...
        'bessCharge_kWh', ...
        'bessDischarge_kWh', ...
        'bessThroughput_kWh', ...
        'bessDischargeBeforeConversion_kWh', ...
        'bessToLoadConversionLoss_kWh', ...
        'centralInverterLoss_kWh', ...
        'centralInvDcToAcLoss_kWh', ...
        'centralInvAcToDcLoss_kWh', ...
        'dcdcLoss_kWh', ...
        'dcdcChargeLoss_kWh', ...
        'dcdcDischargeLoss_kWh', ...
        'pcsbInverterLoss_kWh', ...
        'pcsbChargeLoss_kWh', ...
        'pcsbDischargeLoss_kWh', ...
        'bessInternalLoss_kWh', ...
        'bessInternalChargeLoss_kWh', ...
        'bessInternalDischargeLoss_kWh', ...
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
        'pvToBessChargeEfficiency_pct', ...
        'bessDischargeToLoadEfficiency_pct', ...
        'gridToBessToLoadEfficiency_pct', ...
        'pvToBessToLoadEfficiency_pct', ...
        'maxLoadPeak_kW', ...
        'maxPVPeak_kW', ...
        'maxGridImportPeak_kW', ...
        'maxGridImportNoBessPeak_kW', ...
        'maxBessChargePeak_kW', ...
        'maxBessDischargePeak_kW', ...
        'equivalentCycles' ...
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