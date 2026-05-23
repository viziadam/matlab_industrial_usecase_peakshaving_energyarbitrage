function candidateMetrics = load_canonical_candidate_metrics(cfgBase, objectiveMode, coupling, candidateList, tableKind)
% LOAD_CANONICAL_CANDIDATE_METRICS
%
% Betolti az egységes candidate-szintu kiertekelesi cache-t.
%
% tableKind:
%   "detailed"  - teljes reszletes tabla
%   "important" - fontosabb metrikak tabla
%
% Alapertelmezett: "detailed"

    if nargin < 4
        candidateList = [];
    end

    if nargin < 5 || strlength(string(tableKind)) == 0
        tableKind = "detailed";
    end

    objectiveMode = lower(string(objectiveMode));
    coupling = lower(string(coupling));
    tableKind = lower(string(tableKind));

    modeResultsDir = local_resolve_mode_results_dir(cfgBase, objectiveMode);

    cachePath = fullfile( ...
        modeResultsDir, ...
        'evaluation_cache', ...
        sprintf('candidate_metrics_%s_%s.mat', coupling, objectiveMode));

    if ~exist(cachePath, 'file')
        error('Canonical candidate metric cache not found: %s', cachePath);
    end

    S = load(cachePath);

    switch tableKind
        case "detailed"

            if isfield(S, 'candidateMetricsDetailed')
                candidateMetrics = S.candidateMetricsDetailed;
            elseif isfield(S, 'candidateMetrics')
                candidateMetrics = S.candidateMetrics;
            else
                error('File does not contain candidateMetricsDetailed or candidateMetrics: %s', cachePath);
            end

        case "important"

            if isfield(S, 'candidateMetricsImportant')
                candidateMetrics = S.candidateMetricsImportant;
            else
                error('File does not contain candidateMetricsImportant: %s', cachePath);
            end

        otherwise
            error('Invalid tableKind: %s', tableKind);
    end

    if nargin >= 4 && ~isempty(candidateList)
        candidateList = candidateList(:);

        if ismember('candidateIndex', candidateMetrics.Properties.VariableNames)
            candidateMetrics = candidateMetrics( ...
                ismember(candidateMetrics.candidateIndex, candidateList), :);
        else
            warning('candidateMetrics does not contain candidateIndex column. Candidate filtering skipped.');
        end
    end
end


function modeResultsDir = local_resolve_mode_results_dir(cfgBase, objectiveMode)

    baseResultsDir = char(cfgBase.paths.results);
    objectiveModeChar = char(objectiveMode);

    [~, lastFolder] = fileparts(baseResultsDir);

    if strcmpi(lastFolder, objectiveModeChar)
        modeResultsDir = baseResultsDir;
    else
        modeResultsDir = fullfile(baseResultsDir, objectiveModeChar);
    end
end