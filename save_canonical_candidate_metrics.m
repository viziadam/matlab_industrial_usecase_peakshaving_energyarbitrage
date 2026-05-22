function candidateMetrics = save_canonical_candidate_metrics(DB, cfg)
% SAVE_CANONICAL_CANDIDATE_METRICS
%
% Egységes, candidate-szintű kiértékelési cache mentése.
%
% Cél:
%   - diagnosztikai és teljes futás esetén is ugyanabba a formába menteni
%     az AC/DC/hybrid candidate eredményeket,
%   - később a plotok ebből dolgozzanak, ne közvetlenül a nyers
%     candidateTable-ből,
%   - ha csak a kiértékelés/plot változik, ne kelljen újraszimulálni.
%
% Mentési hely:
%   results/<mode>/evaluation_cache/candidate_metrics_<coupling>_<mode>.mat
%   results/<mode>/evaluation_cache/candidate_metrics_<coupling>_<mode>.csv

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

    csvPath = fullfile(cacheDir, sprintf( ...
        'candidate_metrics_%s_%s.csv', coupling, objectiveMode));

    rowsToSave = local_get_rows_to_save(T);

    if isempty(rowsToSave)
        fprintf('\nNo simulated candidate rows found for canonical metric cache.\n');
        candidateMetrics = table();
        return;
    end

    newMetrics = local_build_metric_table(T, rowsToSave, coupling, objectiveMode);

    if exist(matPath, 'file')
        S = load(matPath, 'candidateMetrics');

        if isfield(S, 'candidateMetrics') && ~isempty(S.candidateMetrics)
            oldMetrics = S.candidateMetrics;
        else
            oldMetrics = table();
        end
    else
        oldMetrics = table();
    end

    candidateMetrics = local_upsert_metrics(oldMetrics, newMetrics);

    save(matPath, 'candidateMetrics', '-v7.3');
    writetable(candidateMetrics, csvPath);

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


function M = local_build_metric_table(T, rows, coupling, objectiveMode)

    n = numel(rows);

    M = table();
    M.objectiveMode = repmat(objectiveMode, n, 1);
    M.coupling = repmat(coupling, n, 1);
    M.candidateIndex = rows(:);

    M.candidateID = strings(n, 1);

    for i = 1:n
        r = rows(i);

        if ismember('candidateID', T.Properties.VariableNames)
            M.candidateID(i) = string(T.candidateID(r));
        else
            M.candidateID(i) = sprintf('candidate_%06d', r);
        end
    end

    % ---------------------------------------------------------------------
    % Design / sizing
    % ---------------------------------------------------------------------
    M.P_PV_kW = local_metric(T, rows, {'P_PV_kW'});
    M.P_inv_kW = local_metric(T, rows, {'P_inv_kW'});
    M.E_BESS_kWh = local_metric(T, rows, {'E_BESS_kWh'});
    M.P_BESS_kW = local_metric(T, rows, {'P_BESS_kW'});
    M.BESS_PV_ratio = local_metric(T, rows, {'BESS_PV_ratio'});

    % ---------------------------------------------------------------------
    % Main energy metrics
    % ---------------------------------------------------------------------
    M.gridImportNoBess_kWh = local_metric(T, rows, { ...
        'gridImportNoBess_kWh', ...
        'gridImportBase_kWh'});

    M.gridImport_kWh = local_metric(T, rows, { ...
        'gridImport_kWh', ...
        'gridEnergyImport_kWh'});

    M.gridToLoad_kWh = local_metric(T, rows, {'gridToLoad_kWh'});
    M.pvToLoad_kWh = local_metric(T, rows, {'pvToLoad_kWh'});
    M.bessToLoad_kWh = local_metric(T, rows, {'bessToLoad_kWh'});

    M.gridToBess_kWh = local_metric(T, rows, {'gridToBess_kWh'});
    M.gridToBessStored_kWh = local_metric(T, rows, {'gridToBessStored_kWh'});
    M.pvToBess_kWh = local_metric(T, rows, {'pvToBess_kWh'});
    M.pvToBessStored_kWh = local_metric(T, rows, {'pvToBessStored_kWh'});

    M.bessCharge_kWh = local_metric(T, rows, {'bessCharge_kWh'});
    M.bessDischarge_kWh = local_metric(T, rows, {'bessDischarge_kWh'});
    M.bessThroughput_kWh = local_metric(T, rows, {'bessThroughput_kWh'});
    M.bessDischargeBeforeConversion_kWh = local_metric(T, rows, {'bessDischargeBeforeConversion_kWh'});

    % ---------------------------------------------------------------------
    % Loss metrics
    % ---------------------------------------------------------------------
    M.gridToBessLoss_kWh = local_metric(T, rows, {'gridToBessLoss_kWh'});
    M.pvToBessLoss_kWh = local_metric(T, rows, {'pvToBessLoss_kWh'});
    M.bessToLoadConversionLoss_kWh = local_metric(T, rows, {'bessToLoadConversionLoss_kWh'});

    M.centralInverterLoss_kWh = local_metric(T, rows, {'centralInverterLoss_kWh'});
    M.dcdcLoss_kWh = local_metric(T, rows, {'dcdcLoss_kWh'});
    M.pcsbInverterLoss_kWh = local_metric(T, rows, {'pcsbInverterLoss_kWh'});
    M.bessInternalLoss_kWh = local_metric(T, rows, {'bessInternalLoss_kWh'});

    M.totalConverterLoss_kWh = local_sum_columns([ ...
        M.centralInverterLoss_kWh, ...
        M.dcdcLoss_kWh, ...
        M.pcsbInverterLoss_kWh]);

    M.trackedPathConverterLoss_kWh = local_sum_columns([ ...
        M.gridToBessLoss_kWh, ...
        M.pvToBessLoss_kWh, ...
        M.bessToLoadConversionLoss_kWh]);

    M.otherConverterLoss_kWh = max( ...
        M.totalConverterLoss_kWh - M.trackedPathConverterLoss_kWh, ...
        0);

    % ---------------------------------------------------------------------
    % Technical indicators
    % ---------------------------------------------------------------------
    M.equivalentCycles = local_metric(T, rows, { ...
        'equivalentCycles', ...
        'equivalentCycleCount', ...
        'bessEquivalentCycles'});

    missingCycles = ~isfinite(M.equivalentCycles);

    M.equivalentCycles(missingCycles) = local_safe_divide( ...
        M.bessThroughput_kWh(missingCycles), ...
        2 .* M.E_BESS_kWh(missingCycles));

    M.equivalentCycles(~isfinite(M.equivalentCycles)) = 0;

    M.finalSoH_pct = local_metric(T, rows, { ...
        'finalSoH', ...
        'SOH_end', ...
        'SoH_final', ...
        'finalSOH'});

    sohFractionMask = isfinite(M.finalSoH_pct) & M.finalSoH_pct <= 1.5;
    M.finalSoH_pct(sohFractionMask) = 100 .* M.finalSoH_pct(sohFractionMask);

    % ---------------------------------------------------------------------
    % Cost metrics
    % ---------------------------------------------------------------------
    M.energyCostNoBess_HUF = local_metric(T, rows, {'energyCostNoBess_HUF'});
    M.energyCost_HUF = local_metric(T, rows, {'energyCost_HUF'});
    M.energyCostSaving_HUF = M.energyCostNoBess_HUF - M.energyCost_HUF;

    M.degradationCost_HUF = local_zero_if_nan(local_metric(T, rows, {'degradationCost_HUF'}));
    M.overrunCost_HUF = local_zero_if_nan(local_metric(T, rows, {'overrunCost_HUF'}));
    M.contractCost_HUF = local_zero_if_nan(local_metric(T, rows, {'contractCost_HUF'}));

    M.costBalance_HUF = ...
        local_zero_if_nan(M.energyCostSaving_HUF) ...
        - M.degradationCost_HUF ...
        - M.overrunCost_HUF ...
        - M.contractCost_HUF;

    % ---------------------------------------------------------------------
    % Import-price based value metrics
    % ---------------------------------------------------------------------
    M.gridToBessImportCost_HUF = local_metric(T, rows, {'gridToBessImportCost_HUF'});
    M.gridToBessStoredImportEquivCost_HUF = local_metric(T, rows, {'gridToBessStoredImportEquivCost_HUF'});
    M.bessStoredImportEquivCost_HUF = local_metric(T, rows, {'bessStoredImportEquivCost_HUF'});
    M.bessDischargeBeforeConversionImportEquivCost_HUF = local_metric(T, rows, {'bessDischargeBeforeConversionImportEquivCost_HUF'});
    M.bessToLoadImportEquivCost_HUF = local_metric(T, rows, {'bessToLoadImportEquivCost_HUF'});

    M.gridToBessChargeLossValue_HUF = ...
        M.gridToBessImportCost_HUF ...
        - M.gridToBessStoredImportEquivCost_HUF;

    M.bessDischargePathLossValue_HUF = ...
        M.bessDischargeBeforeConversionImportEquivCost_HUF ...
        - M.bessToLoadImportEquivCost_HUF;

    % ---------------------------------------------------------------------
    % Derived ratios
    % ---------------------------------------------------------------------
    M.gridImportReduction_kWh = M.gridImportNoBess_kWh - M.gridImport_kWh;

    M.gridImport_pct_of_noBess = 100 .* local_safe_divide( ...
        M.gridImport_kWh, ...
        M.gridImportNoBess_kWh);

    M.gridImportReduction_pct = 100 .* local_safe_divide( ...
        M.gridImportReduction_kWh, ...
        M.gridImportNoBess_kWh);

    M.gridToBess_pct_of_noBess = 100 .* local_safe_divide( ...
        M.gridToBess_kWh, ...
        M.gridImportNoBess_kWh);

    M.gridToBess_charge_eff_pct = 100 .* local_safe_divide( ...
        M.gridToBessStored_kWh, ...
        M.gridToBess_kWh);

    M.bessDischarge_to_load_eff_pct = 100 .* local_safe_divide( ...
        M.bessToLoad_kWh, ...
        M.bessDischargeBeforeConversion_kWh);

    M.overall_gridToBess_to_load_eff_pct = ...
        M.gridToBess_charge_eff_pct ...
        .* M.bessDischarge_to_load_eff_pct ./ 100;
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
        elseif isstring(T2.(name))
            T1.(name) = strings(height(T1), 1);
        else
            T1.(name) = repmat(missing, height(T1), 1);
        end
    end

    T1 = T1(:, T2.Properties.VariableNames);
end


function key = local_make_key(T)

    key = string(T.objectiveMode) ...
        + "|" + string(T.coupling) ...
        + "|" + string(T.candidateID);
end


function values = local_metric(T, rows, names)

    values = NaN(numel(rows), 1);

    for k = 1:numel(names)
        name = names{k};

        if ismember(name, T.Properties.VariableNames)
            raw = T.(name)(rows);
            values = local_to_numeric_column(raw);
            return;
        end
    end
end


function values = local_to_numeric_column(raw)

    if isnumeric(raw) || islogical(raw)
        values = double(raw(:));
        return;
    end

    if iscell(raw)
        values = NaN(numel(raw), 1);

        for i = 1:numel(raw)
            x = raw{i};

            if isnumeric(x) && isscalar(x)
                values(i) = double(x);
            elseif isstring(x) || ischar(x)
                values(i) = str2double(x);
            end
        end

        return;
    end

    if isstring(raw) || ischar(raw)
        values = str2double(string(raw(:)));
        return;
    end

    values = NaN(numel(raw), 1);
end


function y = local_safe_divide(a, b)

    y = NaN(size(a));

    mask = isfinite(a) & isfinite(b) & abs(b) > 1e-12;
    y(mask) = a(mask) ./ b(mask);
end


function y = local_zero_if_nan(x)

    y = x;
    y(~isfinite(y)) = 0;
end


function s = local_sum_columns(X)

    X(~isfinite(X)) = 0;
    s = sum(X, 2);
end