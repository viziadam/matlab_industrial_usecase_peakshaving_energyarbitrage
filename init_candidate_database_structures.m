function DB = init_candidate_database_structures(data, cfg)
% INIT_CANDIDATE_DATABASE_STRUCTURES
%
% Ipari grid-connected PV+BESS candidate adatbázis.
%
% Candidate tér:
%   E_BESS_kWh x P_BESS_kW
%
% A PV és inverter méret fix, cfg-ből jön.
% A kimentett alap metrikákat továbbra is a cfg.output.* listák határozzák meg.

    % =====================================================================
    % 1) Validálás
    % =====================================================================
    local_validate_data(data);
    local_validate_cfg(cfg);

    nDays = numel(data.days);
    nT = numel(data.days(1).P_load_kW);
    dt_h = data.days(1).dt_h;

    % =====================================================================
    % 2) Candidate tartományok
    % =====================================================================
    BESS_PV_ratio_vec = cfg.candidates.BESS_PV_ratio_vec(:);

    nCandidates = numel(BESS_PV_ratio_vec);

    designFields = local_get_candidate_design_fields(cfg);

    candidateTable = local_create_candidate_table(nCandidates, cfg, designFields);
    % =====================================================================
    % 3) Candidate table feltöltése
    % =====================================================================
    for idx = 1:nCandidates

        bessRatio = BESS_PV_ratio_vec(idx);

        design = struct();

        design.BESS_PV_ratio = bessRatio;

        design.P_PV_A_kW = sum(cfg.pvA.P_dc_kWp);
        design.P_PV_B_kW = sum(cfg.pvB.P_dc_kWp);
        design.P_PV_kW = design.P_PV_A_kW + design.P_PV_B_kW;

        design.P_inv_kW = cfg.dc.P_inv_kW;

        design.E_BESS_kWh = bessRatio * design.P_PV_kW;
        design.P_BESS_kW = design.E_BESS_kWh / cfg.candidates.bessDuration_h;

        candidateTable.candidateIndex(idx) = idx;
    candidateTable.candidateID(idx) = string(sprintf('CAND_%06d', idx));

        candidateTable = local_write_design_to_candidate_table( ...
            candidateTable, ...
            idx, ...
            design, ...
            designFields);
    end

    % =====================================================================
    % 4) DB struktúra
    % =====================================================================
    DB = struct();

    DB.version = "industrial_contract_peak_arbitrage_candidate_database_v1";
    DB.createdAt = datetime('now');

    DB.nCandidates = nCandidates;
    DB.nDays = nDays;
    DB.nT = nT;
    DB.dt_h = dt_h;

    DB.profileAxis = struct();
    DB.profileAxis.time_h = (0:nT-1) * dt_h;

    DB.cfgSnapshot = cfg;
    DB.candidateDesignFields = designFields;

    if isfield(data, 'info')
        DB.dataInfo = data.info;
    else
        DB.dataInfo = struct();
    end

    DB.candidateTable = candidateTable;
    DB.baseProfiles = local_build_base_profiles(data);
    DB.candidateProfiles = local_init_candidate_profiles(nCandidates, nT, cfg);

    fprintf('Industrial candidate database initialized.\n');
    fprintf('Coupling: %s\n', string(cfg.system.bessCoupling));
    fprintf('Candidate structure: BESS_PV_ratio\n');
    fprintf('BESS/PV ratio candidates: %d\n', numel(BESS_PV_ratio_vec));
    fprintf('Total candidates: %d\n', nCandidates);
    fprintf('Days: %d\n', nDays);
    fprintf('Profile length: %d\n', nT);
end


% =========================================================================
% DATA VALIDATION
% =========================================================================
function local_validate_data(data)

    if ~isfield(data, 'days')
        error('Data must contain data.days.');
    end

    if isempty(data.days)
        error('data.days is empty.');
    end

    requiredFields = {'P_load_kW', 'dt_h'};

    for f = 1:numel(requiredFields)
        if ~isfield(data.days(1), requiredFields{f})
            error('data.days(1) missing required field: %s', requiredFields{f});
        end
    end

    nT = numel(data.days(1).P_load_kW);
    dt_h = data.days(1).dt_h;

    for d = 1:numel(data.days)

        if numel(data.days(d).P_load_kW) ~= nT
            error('All days must have the same P_load_kW length. Error at day %d.', d);
        end

        if abs(data.days(d).dt_h - dt_h) > 1e-12
            error('All days must have the same dt_h. Error at day %d.', d);
        end
    end
end


% =========================================================================
% CFG VALIDATION
% =========================================================================
function local_validate_cfg(cfg)

    requiredTop = {'system', 'candidates', 'output', 'dc', 'pvA', 'pvB'};
    local_require_fields(cfg, requiredTop, 'cfg');

    local_require_fields(cfg.candidates, ...
        {'BESS_PV_ratio_vec', 'bessDuration_h', 'designFields'}, ...
        'cfg.candidates');


    local_require_fields(cfg.output, {'scalarMetrics', 'profileMetrics'}, 'cfg.output');

    local_validate_metric_definitions(cfg.output.scalarMetrics, 'scalarMetrics');
    local_validate_metric_definitions(cfg.output.profileMetrics, 'profileMetrics');

    if isfield(cfg.output, 'summaryMetrics')
        local_validate_summary_metric_definitions(cfg.output.summaryMetrics);
    end

    if isfield(cfg.output, 'derivedMetrics')
        local_validate_derived_metric_definitions(cfg.output.derivedMetrics);
    end
end


function local_require_fields(S, requiredFields, structName)

    for i = 1:numel(requiredFields)
        f = requiredFields{i};

        if ~isfield(S, f)
            error('Missing required field: %s.%s', structName, f);
        end
    end
end


function local_validate_metric_definitions(metrics, metricGroupName)

    requiredFields = {'name', 'source', 'mode'};

    for i = 1:numel(requiredFields)
        if ~isfield(metrics, requiredFields{i})
            error('cfg.output.%s missing field: %s', metricGroupName, requiredFields{i});
        end
    end

    for i = 1:numel(metrics)

        if strlength(string(metrics(i).name)) == 0
            error('Empty metric name in cfg.output.%s at index %d.', metricGroupName, i);
        end

        if strlength(string(metrics(i).source)) == 0
            error('Empty metric source in cfg.output.%s at index %d.', metricGroupName, i);
        end

        if strlength(string(metrics(i).mode)) == 0
            error('Empty metric mode in cfg.output.%s at index %d.', metricGroupName, i);
        end
    end
end


function local_validate_summary_metric_definitions(metrics)

    requiredFields = {'name', 'source'};

    for i = 1:numel(requiredFields)
        if ~isfield(metrics, requiredFields{i})
            error('cfg.output.summaryMetrics missing field: %s', requiredFields{i});
        end
    end
end


function local_validate_derived_metric_definitions(metrics)

    requiredFields = {'name', 'operation', 'inputs'};

    for i = 1:numel(requiredFields)
        if ~isfield(metrics, requiredFields{i})
            error('cfg.output.derivedMetrics missing field: %s', requiredFields{i});
        end
    end
end


% =========================================================================
% DESIGN FIELD HANDLING
% =========================================================================
function designFields = local_get_candidate_design_fields(cfg)

    designFields = string(cfg.candidates.designFields(:)).';
end


function candidateTable = local_write_design_to_candidate_table( ...
    candidateTable, idx, design, designFields)

    for i = 1:numel(designFields)

        fieldName = char(designFields(i));

        if ~ismember(fieldName, candidateTable.Properties.VariableNames)
            candidateTable.(fieldName) = NaN(height(candidateTable), 1);
        end

        if ~isfield(design, fieldName)
            error('A design struktúra nem tartalmazza a következő mezőt: %s', fieldName);
        end

        candidateTable.(fieldName)(idx) = design.(fieldName);
    end
end


% =========================================================================
% CANDIDATE TABLE
% =========================================================================
function T = local_create_candidate_table(n, cfg, designFields)

    T = table();

    T.candidateIndex = NaN(n, 1);
    T.candidateID = strings(n, 1);

    for i = 1:numel(designFields)

        fieldName = char(designFields(i));

        if ~ismember(fieldName, T.Properties.VariableNames)
            T.(fieldName) = NaN(n, 1);
        end
    end

    T.wasSimulated = false(n, 1);
    T.hasError = false(n, 1);
    T.errorMessage = strings(n, 1);
    T.runtime_s = NaN(n, 1);

    localMetricNames = local_collect_all_candidate_table_metric_names(cfg);

    for i = 1:numel(localMetricNames)

        col = char(localMetricNames(i));

        if ~ismember(col, T.Properties.VariableNames)
            T.(col) = NaN(n, 1);
        end
    end
end


function metricNames = local_collect_all_candidate_table_metric_names(cfg)

    metricNames = strings(0, 1);

    if isfield(cfg.output, 'scalarMetrics')
        metricNames = [metricNames; string({cfg.output.scalarMetrics.name}).'];
    end

    if isfield(cfg.output, 'summaryMetrics')
        metricNames = [metricNames; string({cfg.output.summaryMetrics.name}).'];
    end

    if isfield(cfg.output, 'derivedMetrics')
        metricNames = [metricNames; string({cfg.output.derivedMetrics.name}).'];
    end

    metricNames = unique(metricNames, 'stable');
end


% =========================================================================
% BASE PROFILES
% =========================================================================
function baseProfiles = local_build_base_profiles(data)

    nDays = numel(data.days);
    nT = numel(data.days(1).P_load_kW);
    dt_h = data.days(1).dt_h;

    loadMat = zeros(nDays, nT);

    for d = 1:nDays
        loadMat(d, :) = data.days(d).P_load_kW(:).';
    end

    baseProfiles = struct();

    baseProfiles.time_h = (0:nT-1) * dt_h;

    baseProfiles.loadMeanProfile_kW = mean(loadMat, 1);
    baseProfiles.loadPeakProfile_kW = max(loadMat, [], 1);
    baseProfiles.loadMinProfile_kW = min(loadMat, [], 1);

    baseProfiles.totalLoadEnergy_kWh = sum(loadMat, 'all') * dt_h;
    baseProfiles.dailyLoadEnergy_kWh = sum(loadMat, 2) * dt_h;

    baseProfiles.maxDailyLoadPeak_kW = max(max(loadMat, [], 2));
    baseProfiles.meanDailyLoadPeak_kW = mean(max(loadMat, [], 2));
end


% =========================================================================
% CANDIDATE PROFILES
% =========================================================================
function profiles = local_init_candidate_profiles(nCandidates, nT, cfg)

    profiles = struct();

    for i = 1:numel(cfg.output.profileMetrics)

        metricName = char(cfg.output.profileMetrics(i).name);

        if ~isfield(profiles, metricName)
            profiles.(metricName) = NaN(nCandidates, nT);
        end
    end
end