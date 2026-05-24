function figs = eval_plot_batch(data, specs, opts)
% EVAL_PLOT_BATCH
% Plot multiple evaluation plot specs. Each spec is rendered with
% eval_plot_generic. The function can place several plots into separate
% figures by grouping specs, or save each plot individually.
%
% Example:
%   modeData = eval_load_result_pair(cfg, "combined", ["dc", "ac"]);
%   specs = eval_plot_examples();
%   opts = struct();
%   opts.outputFolder = fullfile(cfg.paths.figures, "custom_batch");
%   opts.saveFigure = true;
%   figs = eval_plot_batch(modeData, specs, opts);

    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    opts = local_set_default(opts, 'outputFolder', fullfile(pwd, 'evaluation_figures'));
    opts = local_set_default(opts, 'saveFigure', true);
    opts = local_set_default(opts, 'closeAfterSave', false);
    opts = local_set_default(opts, 'couplings', ["dc", "ac"]);

    figs = struct();

    if isempty(specs)
        return;
    end

    for k = 1:numel(specs)
        spec = specs(k);

        if ~isfield(spec, 'name') || isempty(spec.name)
            spec.name = sprintf('evaluation_plot_%02d', k);
        end

        fig = eval_plot_generic(data, spec, opts);
        figs.(matlab.lang.makeValidName(char(spec.name))) = fig;
    end
end


function S = local_set_default(S, fieldName, defaultValue)
    if ~isfield(S, fieldName) || isempty(S.(fieldName))
        S.(fieldName) = defaultValue;
    end
end
