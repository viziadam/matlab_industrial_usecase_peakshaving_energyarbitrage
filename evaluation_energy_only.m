function out = evaluation_energy_only(cfg, opts)
% EVALUATION_ENERGY_ONLY
% User-editable evaluation entry point for energy_only mode.
% This function only loads saved result data and builds optional template plots.

    if nargin < 2 || isempty(opts)
        opts = struct();
    end

    out = evaluation_mode_template("energy_only", cfg, opts);

    % ------------------------------------------------------------------
    % Example: extract all DC finalSoH values for all BESS sizes
    % ------------------------------------------------------------------
    if isfield(out.data, 'dc') && isfield(out.data.dc, 'candidateTable')
        out.examples.dcFinalSoH = eval_get_metric(out, "dc", "finalSoH");
    end

    % ------------------------------------------------------------------
    % User area
    % Add your own energy_only-specific plots and calculations here.
    % Examples:
    %   values = eval_get_metric(out, "dc", "gridImport_kWh");
    %   values = eval_get_metric(out, "ac", "energyCost_HUF");
    % ------------------------------------------------------------------
end
