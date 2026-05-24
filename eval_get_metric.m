function s = eval_get_metric(evalOutOrData, coupling, metricName, opts)
% EVAL_GET_METRIC
% Dynamically extract one candidateTable metric for one coupling.
%
% Example:
%   out = evaluation_energy_only(cfg);
%   s = eval_get_metric(out, "dc", "finalSoH");
%   plot(s.x, s.y, '-o')
%
% Output:
%   s.x      candidate x-axis, default BESS_PV_ratio
%   s.y      selected metric values
%   s.table  filtered/sorted candidate table

    if nargin < 4 || isempty(opts)
        opts = struct();
    end

    opts = local_set_default(opts, 'xField', "BESS_PV_ratio");
    opts = local_set_default(opts, 'onlyValid', true);
    opts = local_set_default(opts, 'sortByX', true);
    opts = local_set_default(opts, 'filterFcn', []);

    data = local_get_data(evalOutOrData);
    coupling = lower(string(coupling));
    metricName = char(metricName);
    xField = char(opts.xField);

    if ~isfield(data, char(coupling))
        error('Missing coupling data: %s', coupling);
    end

    T = data.(char(coupling)).candidateTable;

    if opts.onlyValid
        T = local_filter_valid(T);
    end

    if ~isempty(opts.filterFcn)
        mask = opts.filterFcn(T);
        T = T(mask, :);
    end

    if ~ismember(xField, T.Properties.VariableNames)
        error('Missing xField: %s', xField);
    end

    if ~ismember(metricName, T.Properties.VariableNames)
        error('Missing metric: %s', metricName);
    end

    if opts.sortByX
        T = sortrows(T, xField);
    end

    s = struct();
    s.coupling = coupling;
    s.metricName = string(metricName);
    s.xField = string(xField);
    s.x = T.(xField);
    s.y = T.(metricName);
    s.table = T;
    s.label = upper(coupling) + " - " + string(metricName);
end


function data = local_get_data(evalOutOrData)

    if isfield(evalOutOrData, 'data')
        data = evalOutOrData.data;
    else
        data = evalOutOrData;
    end
end


function T = local_filter_valid(T)

    if ismember('wasSimulated', T.Properties.VariableNames)
        T = T(logical(T.wasSimulated), :);
    end

    if ismember('hasError', T.Properties.VariableNames)
        T = T(~logical(T.hasError), :);
    end
end


function S = local_set_default(S, fieldName, defaultValue)

    if ~isfield(S, fieldName) || isempty(S.(fieldName))
        S.(fieldName) = defaultValue;
    end
end
