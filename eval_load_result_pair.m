function data = eval_load_result_pair(cfg, objectiveMode, couplings)
% EVAL_LOAD_RESULT_PAIR
% Load saved result databases for one objective mode and one or more couplings.
% This helper does not change the simulation or saving logic.
%
% Example:
%   data = eval_load_result_pair(cfg, "energy_only", ["dc", "ac"]);
%   Tdc = data.dc.candidateTable;
%   Tac = data.ac.candidateTable;

    if nargin < 3 || isempty(couplings)
        couplings = ["dc", "ac"];
    end

    objectiveMode = lower(string(objectiveMode));
    couplings = lower(string(couplings));

    data = struct();
    data.objectiveMode = objectiveMode;
    data.couplings = couplings;

    for i = 1:numel(couplings)
        coupling = couplings(i);
        resultPath = local_find_result_file(cfg, objectiveMode, coupling);

        if strlength(resultPath) == 0
            warning('Result file not found for mode=%s, coupling=%s.', objectiveMode, coupling);
            continue;
        end

        DB = local_load_database(resultPath);

        if ~isfield(DB, 'candidateTable')
            error('Loaded database does not contain candidateTable: %s', resultPath);
        end

        T = DB.candidateTable;

        if ~ismember('coupling', T.Properties.VariableNames)
            T.coupling = repmat(coupling, height(T), 1);
        else
            T.coupling(:) = coupling;
        end

        item = struct();
        item.path = resultPath;
        item.DB = DB;
        item.candidateTable = T;

        if isfield(DB, 'candidateProfiles')
            item.candidateProfiles = DB.candidateProfiles;
        else
            item.candidateProfiles = struct();
        end

        data.(char(coupling)) = item;
    end
end


function resultPath = local_find_result_file(cfg, objectiveMode, coupling)

    resultPath = "";
    resultRoot = cfg.paths.results;

    switch coupling
        case "dc"
            names = ["results_dc_" + objectiveMode + ".mat", "results_dccoupled.mat"];
        case "ac"
            names = ["results_ac_" + objectiveMode + ".mat", "results_accoupled.mat"];
        case "hybrid"
            names = ["results_hybrid_" + objectiveMode + ".mat", "results_hybrid.mat"];
        otherwise
            error('Unknown coupling: %s', coupling);
    end

    candidates = strings(0, 1);

    for k = 1:numel(names)
        candidates(end+1, 1) = fullfile(resultRoot, char(objectiveMode), char(names(k))); %#ok<AGROW>
        candidates(end+1, 1) = fullfile(resultRoot, char(names(k))); %#ok<AGROW>
    end

    for k = 1:numel(candidates)
        if isfile(candidates(k))
            resultPath = candidates(k);
            return;
        end
    end
end


function DB = local_load_database(resultPath)

    S = load(resultPath);

    if isfield(S, 'configurationDatabase')
        DB = S.configurationDatabase;
    elseif isfield(S, 'DB')
        DB = S.DB;
    else
        error('MAT file does not contain configurationDatabase or DB: %s', resultPath);
    end
end
