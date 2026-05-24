function out = evaluation_peak_only(cfg, opts)
% EVALUATION_PEAK_ONLY
% User-editable evaluation entry point for peak_only mode.
% This function only loads saved result data and builds optional template plots.

    if nargin < 2 || isempty(opts)
        opts = struct();
    end

    out = evaluation_mode_template("peak_only", cfg, opts);

    % ------------------------------------------------------------------
    % Example: extract all DC bestContract_kW values for all BESS sizes
    % ------------------------------------------------------------------
    if isfield(out.data, 'dc') && isfield(out.data.dc, 'candidateTable')
        out.examples.dcBestContract = eval_get_metric(out, "dc", "bestContract_kW");
    end

    % ------------------------------------------------------------------
    % User area
    % Add your own peak_only-specific plots and calculations here.
    % Examples:
    %   values = eval_get_metric(out, "dc", "peakReduction_pct");
    %   values = eval_get_metric(out, "ac", "maxGridImportPeak_kW");
    % ------------------------------------------------------------------
end
