function candidateMetrics = load_canonical_candidate_metrics(cfgBase, objectiveMode, coupling, candidateList)
% LOAD_CANONICAL_CANDIDATE_METRICS
%
% Betölti az egységes candidate-szintű kiértékelési cache-t.
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

    cachePath = fullfile( ...
        cfgBase.paths.results, ...
        char(objectiveMode), ...
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
        candidateMetrics = candidateMetrics( ...
            ismember(candidateMetrics.candidateIndex, candidateList), :);
    end
end