function fig = eval_plot_generic(data, spec, opts)
% EVAL_PLOT_GENERIC
% Generic plot engine for saved evaluation result tables.
%
% Supported spec.type values:
%   grouped_bar
%   stacked_grouped_bar
%   stacked_grouped_bar_lines
%   signed_stacked_grouped_bar
%   signed_stacked_grouped_bar_lines
%   lines
%
% The function expects data from eval_load_result_pair or evaluation_mode_template.

    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    opts = local_set_default(opts, 'couplings', local_default_couplings(data));
    opts = local_set_default(opts, 'saveFigure', false);
    opts = local_set_default(opts, 'outputFolder', fullfile(pwd, 'evaluation_figures'));
    opts = local_set_default(opts, 'closeAfterSave', false);

    spec = local_set_default(spec, 'type', "lines");
    spec = local_set_default(spec, 'name', "evaluation_plot");
    spec = local_set_default(spec, 'xField', "BESS_PV_ratio");
    spec = local_set_default(spec, 'scale', 1.0);
    spec = local_set_default(spec, 'lineScale', 1.0);
    spec = local_set_default(spec, 'title', "");
    spec = local_set_default(spec, 'xlabel', string(spec.xField));
    spec = local_set_default(spec, 'ylabel', "");
    spec = local_set_default(spec, 'legendLocation', "best");
    spec = local_set_default(spec, 'showZeroLine', false);
    spec = local_set_default(spec, 'showValues', false);
    spec = local_set_default(spec, 'showStackValues', false);
    spec = local_set_default(spec, 'showLineValues', false);
    spec = local_set_default(spec, 'valueFormat', "%.2f");

    fig = figure('Name', char(spec.name), 'Position', [100, 80, 1350, 780]);
    ax = axes(fig);
    hold(ax, 'on');
    grid(ax, 'on');

    type = lower(string(spec.type));

    switch type
        case "grouped_bar"
            local_plot_grouped_bar(ax, data, spec, opts);
        case "stacked_grouped_bar"
            local_plot_stacked_grouped_bar(ax, data, spec, opts, false, false);
        case "stacked_grouped_bar_lines"
            local_plot_stacked_grouped_bar(ax, data, spec, opts, true, false);
        case "signed_stacked_grouped_bar"
            local_plot_stacked_grouped_bar(ax, data, spec, opts, false, true);
        case "signed_stacked_grouped_bar_lines"
            local_plot_stacked_grouped_bar(ax, data, spec, opts, true, true);
        case "lines"
            local_plot_lines(ax, data, spec, opts);
        otherwise
            error('Unknown plot type: %s', type);
    end

    if logical(spec.showZeroLine)
        yline(ax, 0, '--', 'HandleVisibility', 'off');
    end

    xlabel(ax, string(spec.xlabel));
    ylabel(ax, string(spec.ylabel));
    title(ax, string(spec.title));
    legend(ax, 'Location', char(spec.legendLocation));
    hold(ax, 'off');

    if logical(opts.saveFigure)
        if ~exist(opts.outputFolder, 'dir')
            mkdir(opts.outputFolder);
        end

        savefig(fig, fullfile(opts.outputFolder, [char(spec.name), '.fig']));

        try
            exportgraphics(fig, fullfile(opts.outputFolder, [char(spec.name), '.png']), 'Resolution', 180);
        catch
            saveas(fig, fullfile(opts.outputFolder, [char(spec.name), '.png']));
        end
    end

    if logical(opts.closeAfterSave)
        close(fig);
    end
end


function local_plot_grouped_bar(ax, data, spec, opts)

    couplings = string(opts.couplings);
    xField = char(spec.xField);
    yFields = string(spec.yFields);

    if numel(yFields) ~= 1
        error('grouped_bar expects exactly one yField.');
    end

    [xRef, xLabels] = local_reference_x(data, couplings, xField);
    Y = NaN(numel(xRef), numel(couplings));

    for c = 1:numel(couplings)
        coupling = lower(couplings(c));
        T = local_get_valid_table(data, coupling);
        Y(:, c) = local_get_y_on_x(T, xField, char(yFields(1)), xRef) .* spec.scale;
    end

    b = bar(ax, xRef, Y, 'grouped');

    for c = 1:numel(couplings)
        b(c).DisplayName = upper(couplings(c));
    end

    local_apply_x_ticks(ax, xRef, xLabels);

    if logical(spec.showValues)
        local_add_grouped_bar_values(ax, xRef, Y, char(spec.valueFormat));
    end
end


function local_plot_stacked_grouped_bar(ax, data, spec, opts, withLines, signedMode)

    couplings = string(opts.couplings);
    xField = char(spec.xField);
    yFields = string(spec.yFields);
    yLabels = local_get_labels(spec, yFields);

    if signedMode && isfield(spec, 'ySigns') && ~isempty(spec.ySigns)
        signs = spec.ySigns(:).';
    else
        signs = ones(1, numel(yFields));
    end

    if numel(signs) ~= numel(yFields)
        error('spec.ySigns must have the same length as spec.yFields.');
    end

    [xRef, xLabels] = local_reference_x(data, couplings, xField);

    dx = local_bar_dx(xRef);
    offsets = local_offsets(numel(couplings), dx);
    barWidth = local_bar_width(numel(couplings), dx);

    for c = 1:numel(couplings)
        coupling = lower(couplings(c));
        T = local_get_valid_table(data, coupling);

        Y = NaN(numel(xRef), numel(yFields));

        for j = 1:numel(yFields)
            Y(:, j) = signs(j) .* local_get_y_on_x(T, xField, char(yFields(j)), xRef) .* spec.scale;
        end

        b = bar(ax, xRef + offsets(c), Y, barWidth, 'stacked');

        for j = 1:numel(b)
            b(j).DisplayName = sprintf('%s - %s', upper(coupling), yLabels(j));
        end

        if logical(spec.showStackValues)
            local_add_stacked_values(ax, xRef + offsets(c), Y, char(spec.valueFormat));
        end
    end

    if withLines
        local_overlay_lines(ax, data, spec, opts, xRef);
    end

    local_apply_x_ticks(ax, xRef, xLabels);
end


function local_plot_lines(ax, data, spec, opts)

    couplings = string(opts.couplings);
    xField = char(spec.xField);
    yFields = string(spec.yFields);
    yLabels = local_get_labels(spec, yFields);

    for c = 1:numel(couplings)
        coupling = lower(couplings(c));
        T = local_get_valid_table(data, coupling);
        x = T.(xField);

        for j = 1:numel(yFields)
            yField = char(yFields(j));

            if ~ismember(yField, T.Properties.VariableNames)
                warning('Missing yField: %s for coupling %s. Skipping.', yField, coupling);
                continue;
            end

            y = T.(yField) .* spec.scale;
            displayName = sprintf('%s - %s', upper(coupling), yLabels(j));

            plot(ax, x, y, '-o', 'LineWidth', 1.5, 'DisplayName', displayName);

            if logical(spec.showLineValues)
                local_add_line_values(ax, x, y, char(spec.valueFormat));
            end
        end
    end
end


function local_overlay_lines(ax, data, spec, opts, xRef)

    if ~isfield(spec, 'lineFields') || isempty(spec.lineFields)
        return;
    end

    couplings = string(opts.couplings);
    xField = char(spec.xField);
    lineFields = string(spec.lineFields);

    if isfield(spec, 'lineLabels') && ~isempty(spec.lineLabels)
        lineLabels = string(spec.lineLabels);
    else
        lineLabels = lineFields;
    end

    for c = 1:numel(couplings)
        coupling = lower(couplings(c));
        T = local_get_valid_table(data, coupling);

        for j = 1:numel(lineFields)
            y = local_get_y_on_x(T, xField, char(lineFields(j)), xRef) .* spec.lineScale;
            displayName = sprintf('%s - %s', upper(coupling), lineLabels(j));
            plot(ax, xRef, y, '-o', 'LineWidth', 2.0, 'DisplayName', displayName);

            if logical(spec.showLineValues)
                local_add_line_values(ax, xRef, y, char(spec.valueFormat));
            end
        end
    end
end


function data = local_unwrap_data(data)
    if isfield(data, 'data')
        data = data.data;
    end
end


function T = local_get_valid_table(data, coupling)

    data = local_unwrap_data(data);

    if ~isfield(data, char(coupling)) || ~isfield(data.(char(coupling)), 'candidateTable')
        error('Missing candidateTable for coupling: %s', coupling);
    end

    T = data.(char(coupling)).candidateTable;

    if ismember('wasSimulated', T.Properties.VariableNames)
        T = T(logical(T.wasSimulated), :);
    end

    if ismember('hasError', T.Properties.VariableNames)
        T = T(~logical(T.hasError), :);
    end
end


function [xRef, xLabels] = local_reference_x(data, couplings, xField)

    for c = 1:numel(couplings)
        coupling = lower(couplings(c));

        try
            T = local_get_valid_table(data, coupling);
        catch
            continue;
        end

        if ~isempty(T) && ismember(xField, T.Properties.VariableNames)
            T = sortrows(T, xField);
            xRef = T.(xField);
            xRef = xRef(:);
            xLabels = string(xRef);
            return;
        end
    end

    error('No valid reference xField found: %s', xField);
end


function y = local_get_y_on_x(T, xField, yField, xRef)

    if ~ismember(yField, T.Properties.VariableNames)
        warning('Missing yField: %s. Filling with NaN.', yField);
        y = NaN(numel(xRef), 1);
        return;
    end

    T = sortrows(T, xField);
    x = T.(xField);
    yRaw = T.(yField);

    [xUnique, ia] = unique(x, 'stable');
    yUnique = yRaw(ia);

    if numel(xUnique) == numel(xRef) && all(abs(xUnique(:) - xRef(:)) < 1e-12)
        y = yUnique(:);
    else
        y = interp1(xUnique(:), yUnique(:), xRef(:), 'linear', NaN);
    end
end


function labels = local_get_labels(spec, fields)
    if isfield(spec, 'yLabels') && ~isempty(spec.yLabels)
        labels = string(spec.yLabels);
    else
        labels = string(fields);
    end
end


function couplings = local_default_couplings(data)
    data = local_unwrap_data(data);
    names = string(fieldnames(data));
    valid = false(size(names));

    for i = 1:numel(names)
        valid(i) = isfield(data.(char(names(i))), 'candidateTable');
    end

    couplings = names(valid);
end


function dx = local_bar_dx(x)
    xu = unique(x(:));
    if numel(xu) < 2
        dx = 1;
    else
        dx = median(diff(xu));
    end
    if ~isfinite(dx) || dx <= 0
        dx = 1;
    end
end


function offsets = local_offsets(n, dx)
    if n <= 1
        offsets = 0;
    else
        offsets = linspace(-0.22 * dx, 0.22 * dx, n);
    end
end


function w = local_bar_width(n, dx)
    if n <= 1
        w = 0.55 * dx;
    else
        w = 0.34 * dx;
    end
end


function local_apply_x_ticks(ax, xRef, xLabels)
    xticks(ax, xRef);
    xticklabels(ax, xLabels);
    if numel(xRef) > 12
        xtickangle(ax, 45);
    end
end


function local_add_grouped_bar_values(ax, x, Y, fmt)
    n = size(Y, 2);
    dx = local_bar_dx(x);
    offsets = local_offsets(n, dx);

    for j = 1:n
        for i = 1:numel(x)
            y = Y(i, j);
            if ~isfinite(y)
                continue;
            end
            text(ax, x(i) + offsets(j), y, sprintf(fmt, y), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
        end
    end
end


function local_add_stacked_values(ax, x, Y, fmt)
    cumPos = zeros(numel(x), 1);
    cumNeg = zeros(numel(x), 1);

    for j = 1:size(Y, 2)
        for i = 1:numel(x)
            y = Y(i, j);
            if ~isfinite(y) || abs(y) < 1e-12
                continue;
            end
            if y >= 0
                yText = cumPos(i) + y / 2;
                cumPos(i) = cumPos(i) + y;
            else
                yText = cumNeg(i) + y / 2;
                cumNeg(i) = cumNeg(i) + y;
            end
            text(ax, x(i), yText, sprintf(fmt, y), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontSize', 8);
        end
    end
end


function local_add_line_values(ax, x, y, fmt)
    for i = 1:numel(x)
        if ~isfinite(y(i))
            continue;
        end
        text(ax, x(i), y(i), sprintf(fmt, y(i)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
    end
end


function S = local_set_default(S, fieldName, defaultValue)
    if ~isfield(S, fieldName) || isempty(S.(fieldName))
        S.(fieldName) = defaultValue;
    end
end
