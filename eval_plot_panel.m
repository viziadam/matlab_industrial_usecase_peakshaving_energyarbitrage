function figs = eval_plot_panel(data, specs, opts)
% EVAL_PLOT_PANEL
% Plot multiple evaluation plot specifications with a configurable number of
% plots in one figure.
%
% Example:
%   modeData = eval_load_result_pair(cfg, "combined", ["dc", "ac"]);
%   specs = eval_plot_examples("all");
%   opts = struct();
%   opts.plotsPerFigure = 3;
%   opts.outputFolder = fullfile(cfg.paths.figures, "panel_examples");
%   opts.saveFigure = true;
%   figs = eval_plot_panel(modeData, specs, opts);

    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    opts = local_set_default(opts, 'plotsPerFigure', 2);
    opts = local_set_default(opts, 'outputFolder', fullfile(pwd, 'evaluation_figures'));
    opts = local_set_default(opts, 'saveFigure', true);
    opts = local_set_default(opts, 'closeAfterSave', false);
    opts = local_set_default(opts, 'couplings', ["dc", "ac"]);

    figs = struct();

    if isempty(specs)
        return;
    end

    plotsPerFigure = max(1, opts.plotsPerFigure);
    nFigures = ceil(numel(specs) / plotsPerFigure);

    specIdx = 0;

    for f = 1:nFigures
        figName = sprintf('evaluation_panel_%02d', f);

        fig = figure('Name', figName, 'Position', [100, 80, 1400, 900]);
        tiledlayout(fig, plotsPerFigure, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

        for p = 1:plotsPerFigure
            specIdx = specIdx + 1;

            if specIdx > numel(specs)
                break;
            end

            targetAx = nexttile;
            local_copy_plot_to_axis(targetAx, data, specs(specIdx), opts);
        end

        figs.(figName) = fig;

        if opts.saveFigure
            if ~exist(opts.outputFolder, 'dir')
                mkdir(opts.outputFolder);
            end

            savefig(fig, fullfile(opts.outputFolder, [figName, '.fig']));

            try
                exportgraphics(fig, fullfile(opts.outputFolder, [figName, '.png']), 'Resolution', 180);
            catch
                saveas(fig, fullfile(opts.outputFolder, [figName, '.png']));
            end
        end

        if opts.closeAfterSave
            close(fig);
        end
    end
end


function local_copy_plot_to_axis(targetAx, data, spec, opts)

    tempOpts = opts;
    tempOpts.saveFigure = false;
    tempOpts.closeAfterSave = false;

    tempFig = eval_plot_generic(data, spec, tempOpts);
    sourceAx = findall(tempFig, 'Type', 'axes');

    if isempty(sourceAx)
        close(tempFig);
        return;
    end

    sourceAx = sourceAx(1);

    delete(allchild(targetAx));
    copyobj(allchild(sourceAx), targetAx);

    targetAx.XLim = sourceAx.XLim;
    targetAx.YLim = sourceAx.YLim;
    targetAx.XTick = sourceAx.XTick;
    targetAx.XTickLabel = sourceAx.XTickLabel;
    targetAx.XTickLabelRotation = sourceAx.XTickLabelRotation;

    xlabel(targetAx, sourceAx.XLabel.String);
    ylabel(targetAx, sourceAx.YLabel.String);
    title(targetAx, sourceAx.Title.String);
    grid(targetAx, 'on');

    legendLocation = 'best';

    if isfield(spec, 'legendLocation') && ~isempty(spec.legendLocation)
        legendLocation = char(spec.legendLocation);
    end

    legend(targetAx, 'Location', legendLocation);

    close(tempFig);
end


function S = local_set_default(S, fieldName, defaultValue)
    if ~isfield(S, fieldName) || isempty(S.(fieldName))
        S.(fieldName) = defaultValue;
    end
end
