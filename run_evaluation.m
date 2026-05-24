function evalResult = run_evaluation(mode, opts)
% RUN_EVALUATION
%
% Kozponti evaluation indito.
%
% Hasznalat:
%   run_evaluation()
%   run_evaluation("energy_only")
%   run_evaluation("peak_only")
%   run_evaluation("combined")
%   run_evaluation("all")
%
% Alapertelmezett mentési hely:
%   thesis_figures/<mode>/
%
% A fajlnevek tovabbra is a figSpecs(f).name alapjan jonnek letre.

    if nargin < 1 || strlength(string(mode)) == 0
        mode = "combined";
    end

    if nargin < 2 || isempty(opts)
        opts = struct();
    end

    opts = local_set_default(opts, 'couplings', ["dc", "ac"]);
    opts = local_set_default(opts, 'candidateList', []);
    opts = local_set_default(opts, 'save', true);
    opts = local_set_default(opts, 'close', false);
    opts = local_set_default(opts, 'figSize', [100 80 1450 900]);

    mode = lower(string(mode));
    basePath = fileparts(mfilename('fullpath'));

    if mode == "all"
        modesToRun = ["energy_only", "peak_only", "combined"];
    else
        modesToRun = mode;
    end

    evalResult = struct();
    evalResult.modes = modesToRun;
    evalResult.results = struct();

    for k = 1:numel(modesToRun)

        currentMode = modesToRun(k);

        fprintf('\n====================================================\n');
        fprintf('EVALUATION MODE: %s\n', currentMode);
        fprintf('====================================================\n');

        evalResult.results.(char(currentMode)) = ...
            local_run_single_mode(basePath, currentMode, opts);
    end
end


function result = local_run_single_mode(basePath, mode, opts)

    allowedModes = ["energy_only", "peak_only", "combined"];

    if ~any(mode == allowedModes)
        error('Invalid evaluation mode: %s', mode);
    end

    cfg = create_configurations(basePath);
    cfg.dispatch.objectiveMode = mode;

    data = local_load_mode_data(cfg, mode, opts);

    switch mode

        case "energy_only"
            [figSpecs, data] = evaluation_energy_only(data, cfg, opts);

        case "peak_only"
            [figSpecs, data] = evaluation_peak_only(data, cfg, opts);

        case "combined"
            [figSpecs, data] = evaluation_combined(data, cfg, opts);
    end

    outputFolder = local_output_folder(basePath, mode, opts);

    plotOpts = opts;
    plotOpts.outputFolder = outputFolder;

    figs = eval_build_figures(data, figSpecs, plotOpts);

    result = struct();
    result.mode = mode;
    result.cfg = cfg;
    result.data = data;
    result.figSpecs = figSpecs;
    result.figures = figs;
    result.outputFolder = outputFolder;

    fprintf('\nEvaluation finished for mode: %s\n', mode);
    fprintf('Output folder: %s\n', outputFolder);
end


function data = local_load_mode_data(cfg, mode, opts)

    couplings = lower(string(opts.couplings));

    data = struct();
    data.mode = mode;

    for i = 1:numel(couplings)

        coupling = couplings(i);
        resultPath = local_find_result_file(cfg, mode, coupling);

        S = load(resultPath);

        if isfield(S, 'configurationDatabase')
            DB = S.configurationDatabase;
        elseif isfield(S, 'DB')
            DB = S.DB;
        else
            error('Result file does not contain configurationDatabase or DB: %s', resultPath);
        end

        T = DB.candidateTable;

        if ~isempty(opts.candidateList)
            T = local_filter_candidates(T, opts.candidateList);
        end

        T.coupling = repmat(coupling, height(T), 1);

        item = struct();
        item.resultPath = resultPath;
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


function resultPath = local_find_result_file(cfg, mode, coupling)

    mode = lower(string(mode));
    coupling = lower(string(coupling));

    resultRoot = cfg.paths.results;

    if coupling == "dc"

        fileNames = [
            "results_dc_" + mode + ".mat"
            "results_dccoupled.mat"
        ];

    elseif coupling == "ac"

        fileNames = [
            "results_ac_" + mode + ".mat"
            "results_accoupled.mat"
        ];

    else
        error('Unknown coupling: %s', coupling);
    end

    candidates = strings(0, 1);

    for i = 1:numel(fileNames)

        candidates(end+1, 1) = ...
            fullfile(resultRoot, char(mode), char(fileNames(i)));

        candidates(end+1, 1) = ...
            fullfile(resultRoot, char(fileNames(i)));
    end

    for i = 1:numel(candidates)
        if isfile(candidates(i))
            resultPath = candidates(i);
            return;
        end
    end

    error('Missing saved result file for mode=%s, coupling=%s.', mode, coupling);
end


function T = local_filter_candidates(T, candidateList)

    candidateList = candidateList(:);

    if ismember('candidateIndex', T.Properties.VariableNames)
        T = T(ismember(T.candidateIndex, candidateList), :);
    else
        T = T(candidateList, :);
    end
end


function outputFolder = local_output_folder(basePath, mode, opts)

    if isfield(opts, 'outputFolder') && ~isempty(opts.outputFolder)
        outputFolder = fullfile(opts.outputFolder, char(mode));
        return;
    end

    outputFolder = fullfile(basePath, 'thesis_figures', char(mode));
end


function S = local_set_default(S, fieldName, defaultValue)

    if ~isfield(S, fieldName) || isempty(S.(fieldName))
        S.(fieldName) = defaultValue;
    end
end