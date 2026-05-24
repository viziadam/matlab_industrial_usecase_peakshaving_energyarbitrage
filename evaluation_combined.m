function out = evaluation_combined(cfg, opts)
% EVALUATION_COMBINED
% User-editable evaluation entry point for combined mode.
% Here combined means peak shaving + energy arbitrage together.
% This function only loads saved result data and builds optional template plots.

    if nargin < 2 || isempty(opts)
        opts = struct();
    end

    out = evaluation_mode_template("combined", cfg, opts);

    % ------------------------------------------------------------------
    % Example: extract all AC/DC objective costs for all BESS sizes
    % ------------------------------------------------------------------
    if isfield(out.data, 'dc') && isfield(out.data.dc, 'candidateTable')
        out.examples.dcObjectiveCost = eval_get_metric(out, "dc", "objectiveCost_HUF");
    end

    if isfield(out.data, 'ac') && isfield(out.data.ac, 'candidateTable')
        out.examples.acObjectiveCost = eval_get_metric(out, "ac", "objectiveCost_HUF");
    end

    % ------------------------------------------------------------------
    % User area
    % Add your own combined-specific plots and calculations here.
    % Examples:
    %   values = eval_get_metric(out, "dc", "energyCost_HUF");
    %   values = eval_get_metric(out, "ac", "contractCost_HUF");
    % ------------------------------------------------------------------
end
