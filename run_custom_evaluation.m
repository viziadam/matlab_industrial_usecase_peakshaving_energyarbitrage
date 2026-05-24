function out = run_custom_evaluation(mode, cfg, opts)
% RUN_CUSTOM_EVALUATION
% Lightweight dispatcher for the new editable evaluation templates.
%
% This function does not run simulations and does not change saving logic.
% It only calls the user-editable evaluation_* files.
%
% Usage:
%   out = run_custom_evaluation("energy_only");
%   out = run_custom_evaluation("peak_only");
%   out = run_custom_evaluation("combined");
%   out = run_custom_evaluation("all");

    if nargin < 1 || isempty(mode)
        mode = "combined";
    end

    if nargin < 2 || isempty(cfg)
        basePath = fileparts(mfilename('fullpath'));
        cfg = create_configurations(basePath);
    end

    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    mode = lower(string(mode));

    if mode == "all"
        modeList = ["energy_only", "peak_only", "combined"];
    else
        modeList = mode;
    end

    out = struct();
    out.createdAt = datetime('now');
    out.modeList = modeList;
    out.results = struct();

    for k = 1:numel(modeList)
        currentMode = modeList(k);

        switch currentMode
            case "energy_only"
                out.results.energy_only = evaluation_energy_only(cfg, opts);
            case "peak_only"
                out.results.peak_only = evaluation_peak_only(cfg, opts);
            case "combined"
                out.results.combined = evaluation_combined(cfg, opts);
            otherwise
                error('Unknown custom evaluation mode: %s', currentMode);
        end
    end
end
