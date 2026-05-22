function candidateMetrics = load_canonical_candidate_metrics(cfgBase, objectiveMode, coupling, candidateList)
% LOAD_CANONICAL_CANDIDATE_METRICS
%
% Betölti az egységes candidate-szintű kiértékelési cache-t.
%
% A függvény robusztus arra az esetre, ha:
%   cfgBase.paths.results = .../results
% vagy:
%   cfgBase.paths.results = .../results/energy_only
%
% Használható:
%   - csak DC kiértékeléshez,
%   - csak AC kiértékeléshez,
%   - AC/DC összehasonlításhoz,
%   - diagnosztikai vagy teljes futás után.

    if nargin < 4
        candidateList = [];
    end

    objectiveMode = lower(string(objectiveMode));
    coupling = lower(string(coupling));

    modeResultsDir = local_resolve_mode_results_dir(cfgBase, objectiveMode);

    cachePath = fullfile( ...
        modeResultsDir, ...
        'evaluation_cache', ...
        sprintf('candidate_metrics_%s_%s.mat', coupling, objectiveMode));

    if ~exist(cachePath, 'file')
        error('Canonical candidate metric cache not found: %s', cachePath);
    end

    S = load(cachePath, 'candidateMetrics');

    if ~isfield(S, 'candidateMetrics')
        error('File does not contain candidateMetrics variable: %s', cachePath);
    end

    candidateMetrics = S.candidateMetrics;

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