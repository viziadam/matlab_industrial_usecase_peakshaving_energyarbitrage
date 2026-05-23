function DB = finalize_candidate_result(DB, candidateIndex, running, runtime_s, cfg)
% FINALIZE_CANDIDATE_RESULT
%
% Candidate futás végén:
%   1) cfg.output.scalarMetrics alapján menti az alap skalár metrikákat
%   2) cfg.output.summaryMetrics alapján menti a horizon summary metrikákat
%   3) cfg.output.profileMetrics alapján menti a napon belüli aggregált profilokat
%   4) cfg.output.derivedMetrics alapján számolja a származtatott mutatókat
%
% Így a kimentett alapmetrikák központi helye továbbra is a cfg.

    % =====================================================================
    % 0) Checks
    % =====================================================================
    if running.nDays <= 0
        error('running.nDays <= 0. Nem lehet finalize-olni.');
    end

    if candidateIndex < 1 || candidateIndex > height(DB.candidateTable)
        error('Érvénytelen candidateIndex: %d', candidateIndex);
    end

    i = candidateIndex;

    % =====================================================================
    % 1) Status
    % =====================================================================
    DB.candidateTable.wasSimulated(i) = true;
    DB.candidateTable.hasError(i) = false;
    DB.candidateTable.errorMessage(i) = "";
    DB.candidateTable.runtime_s(i) = runtime_s;

    % =====================================================================
    % 2) Scalar metrics
    % =====================================================================
    DB = local_finalize_scalar_metrics(DB, i, running, cfg);

    % =====================================================================
    % 3) Summary metrics
    % =====================================================================
    DB = local_finalize_summary_metrics(DB, i, running, cfg);

    % =====================================================================
    % 4) Profile metrics
    % =====================================================================
    DB = local_finalize_profile_metrics(DB, i, running, cfg);

    % =====================================================================
    % 5) Derived metrics
    % =====================================================================
    DB = local_finalize_derived_metrics(DB, i, cfg);
end


% =========================================================================
% SCALAR METRICS
% =========================================================================
function DB = local_finalize_scalar_metrics(DB, rowIdx, running, cfg)

    for k = 1:numel(cfg.output.scalarMetrics)

        metricName = char(cfg.output.scalarMetrics(k).name);

        if ~isfield(running.scalar, metricName)
            error('running.scalar nem tartalmazza ezt a metrikát: %s', metricName);
        end

        DB.candidateTable = local_ensure_table_numeric_column( ...
            DB.candidateTable, ...
            metricName, ...
            height(DB.candidateTable));

        DB.candidateTable.(metricName)(rowIdx) = running.scalar.(metricName);
    end
end


% =========================================================================
% SUMMARY METRICS
% =========================================================================
function DB = local_finalize_summary_metrics(DB, rowIdx, running, cfg)

    if ~isfield(cfg.output, 'summaryMetrics') || isempty(cfg.output.summaryMetrics)
        return;
    end

    for k = 1:numel(cfg.output.summaryMetrics)

        metricName = char(cfg.output.summaryMetrics(k).name);

        DB.candidateTable = local_ensure_table_numeric_column( ...
            DB.candidateTable, ...
            metricName, ...
            height(DB.candidateTable));

        if isfield(running, 'summary') && isfield(running.summary, metricName)
            DB.candidateTable.(metricName)(rowIdx) = running.summary.(metricName);
        else
            DB.candidateTable.(metricName)(rowIdx) = NaN;
        end
    end
end


% =========================================================================
% PROFILE METRICS
% =========================================================================
function DB = local_finalize_profile_metrics(DB, rowIdx, running, cfg)

    nCandidates = DB.nCandidates;
    nT = DB.nT;

    if ~isfield(DB, 'candidateProfiles') || isempty(DB.candidateProfiles)
        DB.candidateProfiles = struct();
    end

    for k = 1:numel(cfg.output.profileMetrics)

        metricName = char(cfg.output.profileMetrics(k).name);
        modeName = string(cfg.output.profileMetrics(k).mode);

        switch modeName

            case "meanProfile"

                if ~isfield(running.profileSum, metricName)
                    error('running.profileSum nem tartalmazza ezt a profilt: %s', metricName);
                end

                profileValue = running.profileSum.(metricName) / running.nDays;

            case "maxProfile"

                if ~isfield(running.profileMax, metricName)
                    error('running.profileMax nem tartalmazza ezt a profilt: %s', metricName);
                end

                profileValue = running.profileMax.(metricName);

            case "minProfile"

                if ~isfield(running.profileMin, metricName)
                    error('running.profileMin nem tartalmazza ezt a profilt: %s', metricName);
                end

                profileValue = running.profileMin.(metricName);

            otherwise

                error('Ismeretlen profile metric mode finalize közben: %s', modeName);
        end

        profileValue = profileValue(:).';

        if numel(profileValue) ~= nT
            error('A(z) %s profil hossza hibás. Várt: %d, kapott: %d', ...
                metricName, nT, numel(profileValue));
        end

        DB.candidateProfiles = local_ensure_profile_field( ...
            DB.candidateProfiles, ...
            metricName, ...
            nCandidates, ...
            nT);

        DB.candidateProfiles.(metricName)(rowIdx, :) = profileValue;
    end
end


% =========================================================================
% DERIVED METRICS
% =========================================================================
function DB = local_finalize_derived_metrics(DB, rowIdx, cfg)

    if ~isfield(cfg.output, 'derivedMetrics') || isempty(cfg.output.derivedMetrics)
        return;
    end

    for k = 1:numel(cfg.output.derivedMetrics)

        m = cfg.output.derivedMetrics(k);

        metricName = char(m.name);
        operation = string(m.operation);
        inputs = m.inputs;

        DB.candidateTable = local_ensure_table_numeric_column( ...
            DB.candidateTable, ...
            metricName, ...
            height(DB.candidateTable));

        value = local_compute_derived_metric( ...
            DB.candidateTable, ...
            rowIdx, ...
            operation, ...
            inputs);

        DB.candidateTable.(metricName)(rowIdx) = value;
    end
end


function value = local_compute_derived_metric(T, rowIdx, operation, inputs)

    switch operation

        case "difference"
            a = local_get_table_value(T, rowIdx, inputs{1});
            b = local_get_table_value(T, rowIdx, inputs{2});

            value = a - b;

        case "ratio"
            a = local_get_table_value(T, rowIdx, inputs{1});
            b = local_get_table_value(T, rowIdx, inputs{2});

            value = local_safe_divide(a, b);

        case "ratioPercent"
            a = local_get_table_value(T, rowIdx, inputs{1});
            b = local_get_table_value(T, rowIdx, inputs{2});

            value = 100 * local_safe_divide(a, b);

        case "productPercent"
            a = local_get_table_value(T, rowIdx, inputs{1});
            b = local_get_table_value(T, rowIdx, inputs{2});

            value = local_safe_divide(a * b, 100);

        case "percentReduction"
            baseline = local_get_table_value(T, rowIdx, inputs{1});
            actual = local_get_table_value(T, rowIdx, inputs{2});

            value = 100 * local_safe_divide(baseline - actual, baseline);

        case "sum"
            value = 0;

            for i = 1:numel(inputs)
                value = value + local_get_table_value(T, rowIdx, inputs{i});
            end

        case "equivalentCycles"
            throughput = local_get_table_value(T, rowIdx, inputs{1});
            E_BESS_kWh = local_get_table_value(T, rowIdx, inputs{2});

            value = local_safe_divide(throughput, 2 * E_BESS_kWh);

            if isempty(value) || isnan(value)
                value = 0;
            end

        otherwise
            error('Ismeretlen derived metric operation: %s', operation);
    end
end


% =========================================================================
% HELPERS
% =========================================================================
function T = local_ensure_table_numeric_column(T, colName, nRows)

    if ~ismember(colName, T.Properties.VariableNames)
        T.(colName) = NaN(nRows, 1);
    end
end


function profiles = local_ensure_profile_field(profiles, fieldName, nCandidates, nT)

    if ~isfield(profiles, fieldName)
        profiles.(fieldName) = NaN(nCandidates, nT);
    end
end


function value = local_get_table_value(T, rowIdx, colName)

    if ismember(colName, T.Properties.VariableNames)
        value = T.(colName)(rowIdx);
    else
        value = NaN;
    end

    if isempty(value)
        value = NaN;
    end
end


function y = local_safe_divide(a, b)

    if isempty(a) || isempty(b) || isnan(a) || isnan(b) || abs(b) < 1e-12
        y = NaN;
    else
        y = a / b;
    end
end