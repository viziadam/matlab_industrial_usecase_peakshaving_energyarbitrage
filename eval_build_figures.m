function figs = eval_build_figures(data, figSpecs, opts)
% EVAL_BUILD_FIGURES
% Dynamic figure builder for evaluation plots.
%
% You define only:
%   - figures
%   - layout
%   - subplot list
%   - fields to plot
%   - labels, titles, legends
%
% The plotting logic is handled here.
%
% Minimal usage:
%   figs = eval_build_figures(modeData, figSpecs);
%
% data can be:
%   - output of eval_load_result_pair
%   - out.data from evaluation_mode_template
%   - out from evaluation_mode_template

    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    opts = setdef(opts, 'outputFolder', fullfile(pwd, 'evaluation_figures'));
    opts = setdef(opts, 'save', true);
    opts = setdef(opts, 'close', false);
    opts = setdef(opts, 'couplings', ["dc", "ac"]);
    opts = setdef(opts, 'figSize', [100 80 1450 900]);

    data = unwrap_data(data);
    figs = struct();

    for f = 1:numel(figSpecs)
        fs = figSpecs(f);

        if ~isfield(fs, 'name')
            fs.name = sprintf('figure_%02d', f);
        end

        if ~isfield(fs, 'layout')
            fs.layout = [1 numel(fs.plots)];
        end

        fig = figure('Name', char(fs.name), 'Position', opts.figSize);
        tiledlayout(fig, fs.layout(1), fs.layout(2), 'TileSpacing', 'compact', 'Padding', 'compact');

        for p = 1:numel(fs.plots)
            ax = nexttile;
            eval_plot_axis(ax, data, fs.plots(p), opts);
        end

        figs.(matlab.lang.makeValidName(char(fs.name))) = fig;

        if opts.save
            if ~exist(opts.outputFolder, 'dir')
                mkdir(opts.outputFolder);
            end
            savefig(fig, fullfile(opts.outputFolder, [char(fs.name), '.fig']));
            try
                exportgraphics(fig, fullfile(opts.outputFolder, [char(fs.name), '.png']), 'Resolution', 180);
            catch
                saveas(fig, fullfile(opts.outputFolder, [char(fs.name), '.png']));
            end
        end

        if opts.close
            close(fig);
        end
    end
end

function data = unwrap_data(data)
    if isfield(data, 'data')
        data = data.data;
    end
end

function S = setdef(S, name, value)
    if ~isfield(S, name) || isempty(S.(name))
        S.(name) = value;
    end
end
