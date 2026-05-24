function eval_plot_axis(ax, data, ps, opts)
% EVAL_PLOT_AXIS
% Dynamic subplot renderer used by eval_build_figures.
%
% Supported ps.type:
%   line, multi_line, grouped_bar, stacked_bar, stacked_bar_line,
%   signed_stacked_bar, signed_stacked_bar_line, area, scatter,
%   heatmap, profile_line, profile_heatmap
%
% Main idea:
%   The user describes WHAT to plot. This function handles HOW to plot it.

    if nargin < 4 || isempty(opts), opts = struct(); end

    opts = setdef(opts, 'couplings', ["dc", "ac"]);
    ps = setdef(ps, 'x', "BESS_PV_ratio");
    ps = setdef(ps, 'scale', 1);
    ps = setdef(ps, 'lineScale', 1);
    ps = setdef(ps, 'title', "");
    ps = setdef(ps, 'xlabel', string(ps.x));
    ps = setdef(ps, 'ylabel', "");
    ps = setdef(ps, 'rightylabel', "");
    ps = setdef(ps, 'legend', "best");
    ps = setdef(ps, 'grid', true);
    ps = setdef(ps, 'values', false);
    ps = setdef(ps, 'lineValues', false);
    ps = setdef(ps, 'valueFmt', "%.2f");
    ps = setdef(ps, 'zeroLine', false);
    ps = setdef(ps, 'rightAxis', false);

    hold(ax, 'on');
    if ps.grid, grid(ax, 'on'); end

    switch lower(string(ps.type))
        case {"line", "multi_line"}
            plot_lines(ax, data, ps, opts);
        case "grouped_bar"
            plot_grouped_bar(ax, data, ps, opts);
        case "stacked_bar"
            plot_stacked_bar(ax, data, ps, opts, false, false);
        case "stacked_bar_line"
            plot_stacked_bar(ax, data, ps, opts, true, false);
        case "signed_stacked_bar"
            plot_stacked_bar(ax, data, ps, opts, false, true);
        case "signed_stacked_bar_line"
            plot_stacked_bar(ax, data, ps, opts, true, true);
        case "area"
            plot_area(ax, data, ps);
        case "scatter"
            plot_scatter(ax, data, ps, opts);
        case "heatmap"
            plot_heatmap(ax, data, ps);
        case "profile_line"
            plot_profile_line(ax, data, ps);
        case "profile_heatmap"
            plot_profile_heatmap(ax, data, ps);
        otherwise
            error('Unknown plot type: %s', string(ps.type));
    end

    if ps.zeroLine
        yyaxis(ax, 'left');
        yline(ax, 0, '--', 'HandleVisibility', 'off');
    end

    yyaxis(ax, 'left');
    title(ax, string(ps.title));
    xlabel(ax, string(ps.xlabel));
    ylabel(ax, string(ps.ylabel));

    if ps.rightAxis && strlength(string(ps.rightylabel)) > 0
        yyaxis(ax, 'right');
        ylabel(ax, string(ps.rightylabel));
        yyaxis(ax, 'left');
    end

    if ~isfield(ps, 'hideLegend') || ~ps.hideLegend
        legend(ax, 'Location', char(ps.legend), 'Interpreter', 'none');
    end

    hold(ax, 'off');
end

function plot_lines(ax, data, ps, opts)
    couplings = get_couplings(data, opts);
    yFields = string(ps.y);
    labels = get_labels(ps, yFields);

    for c = 1:numel(couplings)
        T = sortrows(getT(data, couplings(c)), char(ps.x));
        x = T.(char(ps.x));
        for j = 1:numel(yFields)
            y = T.(char(yFields(j))) .* ps.scale;
            nm = sprintf('%s - %s', upper(couplings(c)), labels(j));
            plot(ax, x, y, '-o', 'LineWidth', 1.5, 'DisplayName', nm);
            if ps.values, add_values(ax, x, y, ps.valueFmt); end
        end
    end
end

function plot_grouped_bar(ax, data, ps, opts)
    couplings = get_couplings(data, opts);
    x = refx(data, couplings, ps.x);
    Y = nan(numel(x), numel(couplings));

    for c = 1:numel(couplings)
        T = getT(data, couplings(c));
        Y(:, c) = yonx(T, ps.x, string(ps.y), x) .* ps.scale;
    end

    b = bar(ax, x, Y, 'grouped');
    for c = 1:numel(couplings), b(c).DisplayName = upper(couplings(c)); end
    set_xt(ax, x);
    if ps.values, add_group_values(ax, x, Y, ps.valueFmt); end
end

function plot_stacked_bar(ax, data, ps, opts, withLine, signedMode)
    couplings = get_couplings(data, opts);
    yFields = string(ps.y);
    labels = get_labels(ps, yFields);
    x = refx(data, couplings, ps.x);
    dx = bardx(x);
    offs = offsets(numel(couplings), dx);
    bw = barwidth(numel(couplings), dx);

    if signedMode && isfield(ps, 'signs')
        signs = ps.signs(:).';
    else
        signs = ones(1, numel(yFields));
    end

    yyaxis(ax, 'left');

    for c = 1:numel(couplings)
        T = getT(data, couplings(c));
        Y = nan(numel(x), numel(yFields));
        for j = 1:numel(yFields)
            Y(:, j) = signs(j) .* yonx(T, ps.x, yFields(j), x) .* ps.scale;
        end
        b = bar(ax, x + offs(c), Y, bw, 'stacked');
        for j = 1:numel(b), b(j).DisplayName = sprintf('%s - %s', upper(couplings(c)), labels(j)); end
        if ps.values, add_stack_values(ax, x + offs(c), Y, ps.valueFmt); end
    end

    if withLine && isfield(ps, 'lineY')
        lineFields = string(ps.lineY);
        lineLabels = get_line_labels(ps, lineFields);

        if ps.rightAxis, yyaxis(ax, 'right'); else, yyaxis(ax, 'left'); end
        hold(ax, 'on');

        for c = 1:numel(couplings)
            T = getT(data, couplings(c));
            for j = 1:numel(lineFields)
                y = yonx(T, ps.x, lineFields(j), x) .* ps.lineScale;
                nm = sprintf('%s - %s', upper(couplings(c)), lineLabels(j));
                plot(ax, x, y, '-o', 'LineWidth', 2, 'DisplayName', nm);
                if ps.lineValues, add_values(ax, x, y, ps.valueFmt); end
            end
        end

        yyaxis(ax, 'left');
    end

    set_xt(ax, x);
end

function plot_area(ax, data, ps)
    T = sortrows(getT(data, string(ps.coupling)), char(ps.x));
    x = T.(char(ps.x));
    Y = T{:, cellstr(string(ps.y))} .* ps.scale;
    h = area(ax, x, Y);
    labels = get_labels(ps, string(ps.y));
    for i = 1:numel(h), h(i).DisplayName = labels(i); end
end

function plot_scatter(ax, data, ps, opts)
    couplings = get_couplings(data, opts);
    for c = 1:numel(couplings)
        T = getT(data, couplings(c));
        x = T.(char(ps.x));
        y = T.(char(ps.y)) .* ps.scale;
        scatter(ax, x, y, 45, 'filled', 'DisplayName', upper(couplings(c)));
    end
end

function plot_heatmap(ax, data, ps)
    T = getT(data, string(ps.coupling));
    x = T.(char(ps.x));
    y = T.(char(ps.y));
    z = T.(char(ps.z)) .* ps.scale;
    [xu,~,ix] = unique(x); [yu,~,iy] = unique(y);
    Z = nan(numel(yu), numel(xu));
    for i = 1:numel(z), Z(iy(i), ix(i)) = z(i); end
    imagesc(ax, xu, yu, Z); axis(ax, 'xy'); colorbar(ax);
    if isfield(ps, 'colorLabel'), cb = colorbar(ax); ylabel(cb, string(ps.colorLabel)); end
end

function plot_profile_line(ax, data, ps)
    item = data.(char(string(ps.coupling)));
    P = item.candidateProfiles.(char(ps.profile));
    idx = ps.row;
    if isfield(ps, 'xProfile'), x = ps.xProfile; else, x = 1:size(P, 2); end
    plot(ax, x, P(idx, :) .* ps.scale, 'LineWidth', 1.5, 'DisplayName', string(ps.profile));
end

function plot_profile_heatmap(ax, data, ps)
    item = data.(char(string(ps.coupling)));
    P = item.candidateProfiles.(char(ps.profile)) .* ps.scale;
    imagesc(ax, P); axis(ax, 'xy'); colorbar(ax);
end

function T = getT(data, coupling)
    data = unwrap_data(data);
    T = data.(char(coupling)).candidateTable;
end

function data = unwrap_data(data)
    if isfield(data, 'data'), data = data.data; end
end

function couplings = get_couplings(data, opts)
    data = unwrap_data(data);
    if isfield(opts, 'couplings') && ~isempty(opts.couplings)
        couplings = lower(string(opts.couplings));
    else
        names = string(fieldnames(data));
        keep = false(size(names));
        for i = 1:numel(names), keep(i) = isfield(data.(char(names(i))), 'candidateTable'); end
        couplings = names(keep);
    end
end

function x = refx(data, couplings, xField)
    T = sortrows(getT(data, couplings(1)), char(xField));
    x = T.(char(xField));
    x = x(:);
end

function y = yonx(T, xField, yField, xRef)
    T = sortrows(T, char(xField));
    x = T.(char(xField));
    raw = T.(char(yField));
    [xu, ia] = unique(x, 'stable');
    yu = raw(ia);
    if numel(xu) == numel(xRef) && all(abs(xu(:) - xRef(:)) < 1e-12)
        y = yu(:);
    else
        y = interp1(xu(:), yu(:), xRef(:), 'linear', NaN);
    end
end

function labels = get_labels(ps, fields)
    if isfield(ps, 'labels'), labels = string(ps.labels); else, labels = string(fields); end
end

function labels = get_line_labels(ps, fields)
    if isfield(ps, 'lineLabels'), labels = string(ps.lineLabels); else, labels = string(fields); end
end

function set_xt(ax, x)
    xticks(ax, x); xticklabels(ax, string(x));
    if numel(x) > 10, xtickangle(ax, 45); end
end

function dx = bardx(x)
    x = unique(x(:));
    if numel(x) < 2, dx = 1; else, dx = median(diff(x)); end
    if ~isfinite(dx) || dx <= 0, dx = 1; end
end

function o = offsets(n, dx)
    if n <= 1, o = 0; else, o = linspace(-0.22*dx, 0.22*dx, n); end
end

function w = barwidth(n, dx)
    if n <= 1, w = 0.55*dx; else, w = 0.34*dx; end
end

function add_values(ax, x, y, fmt)
    for i = 1:numel(x)
        if isfinite(y(i))
            text(ax, x(i), y(i), sprintf(fmt, y(i)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
        end
    end
end

function add_group_values(ax, x, Y, fmt)
    dx = bardx(x); o = offsets(size(Y,2), dx);
    for j = 1:size(Y,2)
        for i = 1:numel(x)
            if isfinite(Y(i,j))
                text(ax, x(i)+o(j), Y(i,j), sprintf(fmt, Y(i,j)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
            end
        end
    end
end

function add_stack_values(ax, x, Y, fmt)
    cp = zeros(numel(x),1); cn = zeros(numel(x),1);
    for j = 1:size(Y,2)
        for i = 1:numel(x)
            y = Y(i,j);
            if ~isfinite(y) || abs(y) < 1e-12, continue; end
            if y >= 0
                yt = cp(i) + y/2; cp(i) = cp(i) + y;
            else
                yt = cn(i) + y/2; cn(i) = cn(i) + y;
            end
            text(ax, x(i), yt, sprintf(fmt, y), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontSize', 8);
        end
    end
end

function S = setdef(S, name, value)
    if ~isfield(S, name) || isempty(S.(name)), S.(name) = value; end
end
