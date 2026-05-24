function figs = export_hybrid_daily_diagnostics_from_db(DB, cfg, candidateIndex)
% EXPORT_HYBRID_DAILY_DIAGNOSTICS_FROM_DB
% Creates and saves the hybrid AC/DC daily diagnostic figures from a saved DB.
%
% Usage after a diagnostic run:
%   load('results/combined/results_hybrid_combined.mat')
%   figs = export_hybrid_daily_diagnostics_from_db(DB, cfg, 5)
%
% The helper does not modify the existing AC/DC diagnostic logic.

    if nargin < 3
        error('Usage: export_hybrid_daily_diagnostics_from_db(DB, cfg, candidateIndex)');
    end

    fieldName = sprintf('candidate_%d', candidateIndex);

    if ~isfield(DB, 'diagnostics') || ~isfield(DB.diagnostics, fieldName)
        error('DB.diagnostics.%s is missing. Run diagnostic simulation first.', fieldName);
    end

    D = DB.diagnostics.(fieldName);

    if ~isfield(D, 'summary') || ~isfield(D.summary, 'full_result')
        error('Diagnostic summary/full_result is missing for candidate %d.', candidateIndex);
    end

    if ~isfield(D.summary, 'pars')
        error('Diagnostic pars is missing for candidate %d.', candidateIndex);
    end

    figs = plot_hybrid_daily_energy_flow_diagnostics(D.summary.full_result, D.summary.pars);

    outDir = fullfile(cfg.diagnostics.outputFolder, sprintf('candidate_%06d', candidateIndex), 'dispatch_diagnostics');

    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    for i = 1:numel(figs)
        if ~isgraphics(figs(i), 'figure')
            continue;
        end

        fileBase = fullfile(outDir, sprintf('hybrid_ac_dc_daily_diagnostics_%02d', i));
        savefig(figs(i), [fileBase, '.fig']);

        try
            exportgraphics(figs(i), [fileBase, '.png'], 'Resolution', 150);
        catch
            saveas(figs(i), [fileBase, '.png']);
        end
    end

    fprintf('\nHybrid AC/DC daily diagnostic figures saved:\n%s\n', outDir);
end
