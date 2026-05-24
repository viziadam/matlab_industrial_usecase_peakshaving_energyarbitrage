function allSeries = eval_get_metric_all(evalOutOrData, metricName, opts)
% EVAL_GET_METRIC_ALL
% Extract one metric dynamically for all available couplings.
%
% Example:
%   out = evaluation_energy_only(cfg);
%   allFinalSoH = eval_get_metric_all(out, "finalSoH");
%   dc_x = allFinalSoH.dc.x;
%   dc_y = allFinalSoH.dc.y;
%   ac_x = allFinalSoH.ac.x;
%   ac_y = allFinalSoH.ac.y;

    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    data = local_get_data(evalOutOrData);

    if isfield(opts, 'couplings') && ~isempty(opts.couplings)
        couplings = lower(string(opts.couplings));
    else
        couplings = local_available_couplings(data);
    end

    allSeries = struct();
    allSeries.metricName = string(metricName);
    allSeries.couplings = couplings;

    for i = 1:numel(couplings)
        coupling = couplings(i);

        if ~isfield(data, char(coupling))
            continue;
        end

        try
            allSeries.(char(coupling)) = eval_get_metric(data, coupling, metricName, opts);
        catch ME
            warning('Could not extract metric=%s for coupling=%s: %s', string(metricName), coupling, ME.message);
        end
    end
end


function data = local_get_data(evalOutOrData)
    if isfield(evalOutOrData, 'data')
        data = evalOutOrData.data;
    else
        data = evalOutOrData;
    end
end


function couplings = local_available_couplings(data)

    names = string(fieldnames(data));
    keep = false(size(names));

    for i = 1:numel(names)
        item = data.(char(names(i)));
        keep(i) = isstruct(item) && isfield(item, 'candidateTable');
    end

    couplings = lower(names(keep));
end
