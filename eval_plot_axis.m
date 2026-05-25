function eval_plot_axis(ax, data, ps, opts)
% EVAL_PLOT_AXIS
%
% Dynamic subplot renderer used by eval_build_figures.
%
% Javitasok:
%   - Paired stacked bar esetben az energiaabra also y-hatara 0.
%   - Paired bar esetben nem allitunk BaseValue-t, mert zoomolt tengelynel
%     ez lecsuszott oszlophatast okoz.
%   - A BESS csoportfelirat az x-tengely ala kerul.
%   - A paired stacked bar + line gorbek pontjai a DC-AC par felezopontjan
%     jelennek meg.
%   - Jobb oldali y-tengely csak akkor latszik, ha tenylegesen hasznaljuk.

    if nargin < 4 || isempty(opts)
        opts = struct();
    end

    opts = setdef(opts, 'couplings', ["dc", "ac"]);

    ps = setdef(ps, 'x', "BESS_PV_ratio");
    ps = setdef(ps, 'scale', 1);
    ps = setdef(ps, 'lineScale', 1);
    ps = setdef(ps, 'title', "");
    ps = setdef(ps, 'xlabel', "");
    ps = setdef(ps, 'ylabel', "");
    ps = setdef(ps, 'rightylabel', "");
    ps = setdef(ps, 'legend', "best");
    ps = setdef(ps, 'grid', true);
    ps = setdef(ps, 'values', false);
    ps = setdef(ps, 'showValues', get_logical_field(ps, 'values', false));
    ps = setdef(ps, 'lineValues', false);
    ps = setdef(ps, 'showLineValues', get_logical_field(ps, 'lineValues', false));
    ps = setdef(ps, 'valueFmt', "%.2f");
    ps = setdef(ps, 'lineValueFmt', ps.valueFmt);
    ps = setdef(ps, 'zeroLine', false);
    ps = setdef(ps, 'rightAxis', false);
    ps = setdef(ps, 'hideLegend', false);

    ps = setdef(ps, 'hideZeroBess', true);
    ps = setdef(ps, 'lineStartAtOrigin', false);
    ps = setdef(ps, 'autoYLim', true);
    ps = setdef(ps, 'autoYMarginFrac', 0.20);

    ps = setdef(ps, 'pairedBarWidth', 0.36);
    ps = setdef(ps, 'insidePairDistance', 0.95);
    ps = setdef(ps, 'pairGroupGap', 1.25);

    hold(ax, 'on');

    if get_logical_field(ps, 'grid', true)
        grid(ax, 'on');
    end

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

        case "paired_stacked_bar"
            plot_paired_stacked_bar(ax, data, ps, opts, false);

        case "paired_stacked_bar_line"
            plot_paired_stacked_bar(ax, data, ps, opts, true);

        case "paired_bar"
            plot_paired_bar(ax, data, ps, opts);

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

    if get_logical_field(ps, 'zeroLine', false)
        yyaxis(ax, 'left');
        yline(ax, 0, '--', 'HandleVisibility', 'off');
    end

    yyaxis(ax, 'left');

    title(ax, string(ps.title), 'Interpreter', 'none');

    if strlength(string(ps.xlabel)) > 0
        xlabel(ax, string(ps.xlabel), 'Interpreter', 'none');
    end

    ylabel(ax, string(ps.ylabel), 'Interpreter', 'none');

    if isfield(ps, 'yLim') && ~isempty(ps.yLim)
        ylim(ax, ps.yLim);
    end

    if get_logical_field(ps, 'rightAxis', false) && strlength(string(ps.rightylabel)) > 0
        yyaxis(ax, 'right');

        if numel(ax.YAxis) > 1 && strcmp(ax.YAxis(2).Visible, 'on')
            ylabel(ax, string(ps.rightylabel), 'Interpreter', 'none');

            if isfield(ps, 'rightYLim') && ~isempty(ps.rightYLim)
                ylim(ax, ps.rightYLim);
            end
        end

        yyaxis(ax, 'left');
    end

    if isfield(ps, 'referenceLineY') && ~isempty(ps.referenceLineY)

        yyaxis(ax, 'left');

        referenceValues = ps.referenceLineY;

        if ~isnumeric(referenceValues)
            error('referenceLineY must be numeric.');
        end

        referenceValues = referenceValues(:);

        for r = 1:numel(referenceValues)

            if ~isfinite(referenceValues(r))
                error('referenceLineY must contain finite numeric values.');
            end

            if isfield(ps, 'referenceLineText') && ~isempty(ps.referenceLineText)

                referenceTexts = string(ps.referenceLineText);

                if numel(referenceTexts) == 1
                    referenceText = referenceTexts(1);
                elseif numel(referenceTexts) == numel(referenceValues)
                    referenceText = referenceTexts(r);
                else
                    error('referenceLineText must be scalar or have the same length as referenceLineY.');
                end

                yline(ax, referenceValues(r), '--', referenceText, ...
                    'LabelHorizontalAlignment', 'left', ...
                    'HandleVisibility', 'off', ...
                    'Interpreter', 'none');

            else

                yline(ax, referenceValues(r), '--', ...
                    'HandleVisibility', 'off');

            end
        end
    end

    if ~get_logical_field(ps, 'hideLegend', false)
        legend(ax, 'Location', char(string(ps.legend)), 'Interpreter', 'none');
    end

    hold(ax, 'off');
end


% =========================================================================
% STANDARD PLOT TYPES
% =========================================================================
function plot_lines(ax, data, ps, opts)

    couplings = get_couplings(data, opts);
    yFields = string(ps.y);
    labels = get_labels(ps, yFields);

    allY = [];

    for c = 1:numel(couplings)

        coupling = lower(string(couplings(c)));

        T = sortrows(getT(data, coupling), char(ps.x));

        if get_logical_field(ps, 'hideZeroBess', false) && ...
                ismember('E_BESS_kWh', T.Properties.VariableNames)

            T = T(abs(T.E_BESS_kWh) > 1e-12, :);
        end

        x = T.(char(ps.x));

        for j = 1:numel(yFields)

            y = T.(char(yFields(j))) .* ps.scale;
            allY = [allY; y(:)];

            if numel(yFields) == 1
                name = upper(coupling);
            else
                name = sprintf('%s - %s', char(upper(coupling)), labels(j));
            end

            p = plot(ax, x, y, '-o', ...
                'LineWidth', 1.5, ...
                'MarkerSize', 5, ...
                'DisplayName', name);

            % -------------------------------------------------------------
            % Color handling
            % Priority:
            %   1) lineColorsByCoupling.dc / .ac
            %   2) colorsByCoupling.dc / .ac
            %   3) colors by metric index
            %   4) lineColors by metric index
            % -------------------------------------------------------------
            if isfield(ps, 'lineColorsByCoupling') && ...
                    ~isempty(ps.lineColorsByCoupling) && ...
                    isfield(ps.lineColorsByCoupling, char(coupling))

                p.Color = ps.lineColorsByCoupling.(char(coupling));

            elseif isfield(ps, 'colorsByCoupling') && ...
                    ~isempty(ps.colorsByCoupling) && ...
                    isfield(ps.colorsByCoupling, char(coupling))

                p.Color = ps.colorsByCoupling.(char(coupling));

            elseif isfield(ps, 'colors') && ~isempty(ps.colors)

                p.Color = pick_color(ps.colors, j);

            elseif isfield(ps, 'lineColors') && ~isempty(ps.lineColors)

                p.Color = pick_color(ps.lineColors, j);

            end

            % -------------------------------------------------------------
            % Line style handling
            % -------------------------------------------------------------
            if isfield(ps, 'lineStylesByCoupling') && ...
                    ~isempty(ps.lineStylesByCoupling) && ...
                    isfield(ps.lineStylesByCoupling, char(coupling))

                p.LineStyle = char(ps.lineStylesByCoupling.(char(coupling)));

            elseif isfield(ps, 'lineStyles') && ~isempty(ps.lineStyles)

                lineStyles = string(ps.lineStyles);
                p.LineStyle = char(lineStyles(1 + mod(j - 1, numel(lineStyles))));
            end

            if get_logical_field(ps, 'showValues', false)
                add_values(ax, x, y, ps.valueFmt);
            end
        end
    end

    if get_logical_field(ps, 'autoYLim', false)
        apply_auto_ylim(ax, allY, get_numeric_field(ps, 'autoYMarginFrac', 0.20), false, false);
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

    for c = 1:numel(couplings)
        b(c).DisplayName = upper(couplings(c));
    end

    apply_bar_colors(b, ps);
    set_xt(ax, x);

    if get_logical_field(ps, 'showValues', false)
        add_group_values(ax, x, Y, ps.valueFmt);
    end
end


function plot_stacked_bar(ax, data, ps, opts, withLine, signedMode)

    couplings = get_couplings(data, opts);
    yFields = string(ps.y);
    labels = get_labels(ps, yFields);

    x = refx(data, couplings, ps.x);

    dx = bardx(x);
    offs = offsets(numel(couplings), dx);
    bw = barwidth(numel(couplings), dx);

    if signedMode && isfield(ps, 'signs') && ~isempty(ps.signs)
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

        for j = 1:numel(b)
            b(j).DisplayName = sprintf('%s - %s', upper(couplings(c)), labels(j));
        end

        apply_bar_colors(b, ps);

        if get_logical_field(ps, 'showValues', false)
            add_stack_values(ax, x + offs(c), Y, ps.valueFmt);
        end
    end

    if withLine && isfield(ps, 'lineY') && ~isempty(ps.lineY)

        lineFields = string(ps.lineY);
        lineLabels = get_line_labels(ps, lineFields);

        if get_logical_field(ps, 'rightAxis', false)
            yyaxis(ax, 'right');
        else
            yyaxis(ax, 'left');
        end

        hold(ax, 'on');

        for c = 1:numel(couplings)

            T = getT(data, couplings(c));

            for j = 1:numel(lineFields)

                y = yonx(T, ps.x, lineFields(j), x) .* ps.lineScale;
                name = sprintf('%s - %s', upper(couplings(c)), lineLabels(j));

                p = plot(ax, x, y, '-o', ...
                    'LineWidth', 2, ...
                    'DisplayName', name);

                if isfield(ps, 'lineColors') && ~isempty(ps.lineColors)
                    p.Color = pick_color(ps.lineColors, j);
                end

                if get_logical_field(ps, 'showLineValues', false)
                    add_values(ax, x, y, ps.lineValueFmt);
                end
            end
        end

        yyaxis(ax, 'left');
    end

    set_xt(ax, x);
end


% =========================================================================
% PAIRED AC/DC DIAGNOSTIC PLOT TYPES
% =========================================================================
function plot_paired_stacked_bar(ax, data, ps, opts, withLine)
% PLOT_PAIRED_STACKED_BAR
%
% AC/DC parositott stacked bar abra.
%
% Hasznalat:
%   - energiautak: csak pozitiv stack, y-tengely 0-rol indul
%   - megtakaritasok: pozitiv es negativ stack is lehet
%
% Opcionális mezők:
%   ps.forceZeroBottom
%       true  -> az also y-hatar pontosan 0
%       false -> negativ ertekek is latszanak
%
%   ps.includeZeroInYLim
%       true -> a 0 bekerul az autoscale tartomanyba
%
%   ps.symmetricYLimAroundZero
%       true -> a y-tengely szimmetrikus lesz 0 korul
%               vagyis a 0-vonal vizualisan kozepre kerul

    couplings = lower(string(opts.couplings));

    if numel(couplings) ~= 2
        error('paired_stacked_bar requires exactly two couplings, usually ["dc", "ac"].');
    end

    T1 = getT(data, couplings(1));
    T2 = getT(data, couplings(2));

    [T1, T2] = align_pair_tables(T1, T2);

    if get_logical_field(ps, 'hideZeroBess', true)
        [T1, T2] = remove_zero_bess_rows(T1, T2);
    end

    if height(T1) == 0
        title(ax, "No non-zero BESS candidates to plot", 'Interpreter', 'none');
        hide_right_axis(ax);
        return;
    end

    n = height(T1);
    [x, x1, x2, xMid, pitch] = pair_positions(n, ps);

    yFields = string(ps.y);
    labels = get_labels(ps, yFields);

    Y1 = table_matrix(T1, yFields) .* ps.scale;
    Y2 = table_matrix(T2, yFields) .* ps.scale;

    yyaxis(ax, 'left');

    requestedAbsWidth = get_numeric_field(ps, 'pairedBarWidth', 0.36);
    relWidth = min(0.80, requestedAbsWidth / pitch);

    b1 = bar(ax, x1, Y1, relWidth, 'stacked');
    hold(ax, 'on');
    b2 = bar(ax, x2, Y2, relWidth, 'stacked');

    colors1 = get_coupling_colors(ps, "dc", numel(yFields));
    colors2 = get_coupling_colors(ps, "ac", numel(yFields));

    apply_color_matrix_to_bars(b1, colors1);
    apply_color_matrix_to_bars(b2, colors2);

    for j = 1:numel(b1)
        b1(j).DisplayName = sprintf('%s - %s', char(upper(couplings(1))), labels(j));
    end

    for j = 1:numel(b2)
        b2(j).DisplayName = sprintf('%s - %s', char(upper(couplings(2))), labels(j));
    end

    xlim(ax, [min(x) - 0.7, max(x) + 0.7]);

    % ---------------------------------------------------------------------
    % Helyes y-tartomany stacked bar eseten.
    %
    % Pozitiv es negativ stackeket kulon kezelunk:
    %   pozitiv stack teteje = pozitiv komponensek osszege
    %   negativ stack alja   = negativ komponensek osszege
    %
    % A koltsegkulonbseg abra eseteben a 0-vonal kozepre kerulhet:
    %   ps.symmetricYLimAroundZero = true
    % ---------------------------------------------------------------------
    positiveStack1 = sum(max(Y1, 0), 2);
    positiveStack2 = sum(max(Y2, 0), 2);

    negativeStack1 = sum(min(Y1, 0), 2);
    negativeStack2 = sum(min(Y2, 0), 2);

    leftStackLimits = [
        positiveStack1
        positiveStack2
        negativeStack1
        negativeStack2
    ];

    if get_logical_field(ps, 'autoYLim', true)

        includeZeroInYLim = get_logical_field(ps, ...
            'includeZeroInYLim', true);

        forceZeroBottom = get_logical_field(ps, ...
            'forceZeroBottom', true);

        symmetricYLimAroundZero = get_logical_field(ps, ...
            'symmetricYLimAroundZero', false);

        if symmetricYLimAroundZero

            apply_symmetric_ylim_around_zero( ...
                ax, ...
                leftStackLimits, ...
                get_numeric_field(ps, 'autoYMarginFrac', 0.20));

        else

            apply_auto_ylim( ...
                ax, ...
                leftStackLimits, ...
                get_numeric_field(ps, 'autoYMarginFrac', 0.20), ...
                includeZeroInYLim, ...
                forceZeroBottom);

        end
    end

    if get_logical_field(ps, 'showValues', false)
        add_stack_values(ax, x1, Y1, ps.valueFmt);
        add_stack_values(ax, x2, Y2, ps.valueFmt);
    end

    xticks(ax, x);
    xticklabels(ax, pair_ticklabels(n, couplings));

    add_bess_group_labels(ax, xMid, T1);

    rightAxisWasUsed = false;

    if withLine && isfield(ps, 'lineY') && ~isempty(ps.lineY)

        lineFields = string(ps.lineY);
        lineLabels = get_line_labels(ps, lineFields);

        separateLinesByCoupling = get_logical_field(ps, ...
            'separateLinesByCoupling', true);

        lineStartAtOrigin = get_logical_field(ps, ...
            'lineStartAtOrigin', false);

        useRightAxis = get_logical_field(ps, 'rightAxis', false);

        if useRightAxis
            yyaxis(ax, 'right');
            rightAxisWasUsed = true;
        else
            yyaxis(ax, 'left');
        end

        rightValuesAll = [];

        hold(ax, 'on');

        if separateLinesByCoupling

            for j = 1:numel(lineFields)

                yLine1 = T1.(char(lineFields(j))) .* ps.lineScale;
                yLine2 = T2.(char(lineFields(j))) .* ps.lineScale;

                xLine = xMid(:);

                if lineStartAtOrigin
                    xLine1 = [0; xLine(:)];
                    yLine1 = [0; yLine1(:)];

                    xLine2 = [0; xLine(:)];
                    yLine2 = [0; yLine2(:)];
                else
                    xLine1 = xLine;
                    xLine2 = xLine;
                end

                p1 = plot(ax, xLine1, yLine1, '-o', ...
                    'LineWidth', 1.5, ...
                    'MarkerSize', 5, ...
                    'DisplayName', sprintf('%s - %s', char(upper(couplings(1))), lineLabels(j)));

                p2 = plot(ax, xLine2, yLine2, '--o', ...
                    'LineWidth', 1.5, ...
                    'MarkerSize', 5, ...
                    'DisplayName', sprintf('%s - %s', char(upper(couplings(2))), lineLabels(j)));

                if isfield(ps, 'lineColorsByCoupling') && ...
                        ~isempty(ps.lineColorsByCoupling)

                    lineColors = ps.lineColorsByCoupling;

                    if size(lineColors, 1) < 2 || size(lineColors, 2) ~= 3
                        error('lineColorsByCoupling must be an N x 3 RGB matrix with at least 2 rows.');
                    end

                    p1.Color = lineColors(1, :);
                    p2.Color = lineColors(2, :);

                elseif isfield(ps, 'lineColors') && ~isempty(ps.lineColors)

                    p1.Color = pick_color(ps.lineColors, 1);
                    p2.Color = pick_color(ps.lineColors, 2);
                end

                if get_logical_field(ps, 'showLineValues', false)

                    if lineStartAtOrigin
                        add_values(ax, xLine1(2:end), yLine1(2:end), ps.lineValueFmt);
                        add_values(ax, xLine2(2:end), yLine2(2:end), ps.lineValueFmt);
                    else
                        add_values(ax, xLine1, yLine1, ps.lineValueFmt);
                        add_values(ax, xLine2, yLine2, ps.lineValueFmt);
                    end
                end

                rightValuesAll = [rightValuesAll; yLine1(:); yLine2(:)];
            end

        else

            for j = 1:numel(lineFields)

                yLine1 = T1.(char(lineFields(j)));
                yLine2 = T2.(char(lineFields(j)));

                yLine = 0.5 * (yLine1(:) + yLine2(:)) .* ps.lineScale;
                xLine = xMid(:);

                if lineStartAtOrigin
                    xLine = [0; xLine(:)];
                    yLine = [0; yLine(:)];
                end

                p = plot(ax, xLine, yLine, '-o', ...
                    'LineWidth', 1.2, ...
                    'MarkerSize', 5, ...
                    'DisplayName', lineLabels(j));

                if isfield(ps, 'lineColors') && ~isempty(ps.lineColors)
                    p.Color = pick_color(ps.lineColors, j);
                end

                if get_logical_field(ps, 'showLineValues', false)

                    if lineStartAtOrigin
                        add_values(ax, xLine(2:end), yLine(2:end), ps.lineValueFmt);
                    else
                        add_values(ax, xLine, yLine, ps.lineValueFmt);
                    end
                end

                rightValuesAll = [rightValuesAll; yLine(:)];
            end
        end

        if useRightAxis && get_logical_field(ps, 'autoYLim', true)
            yyaxis(ax, 'right');
            apply_auto_ylim(ax, rightValuesAll, get_numeric_field(ps, 'autoYMarginFrac', 0.20), false, false);
        end

        yyaxis(ax, 'left');
    end

    if ~rightAxisWasUsed
        hide_right_axis(ax);
    end
end


function plot_paired_bar(ax, data, ps, opts)
% PLOT_PAIRED_BAR
%
% AC/DC parositott sima oszlopdiagram.
%
% Fontos:
%   - Ezt ugyanugy kell kezelni, mint a stacked energiaabrakat:
%     az oszlopok 0-rol indulnak, ezert az y-tengely also hatara is 0.
%
%   - Nem szabad zoomolt y-tengelyt hasznalni ugy, hogy a 0 nem latszik,
%     mert ilyenkor MATLAB-ban az oszlopok vizualisan "lecsusznak".
%
%   - Ezert itt az auto y-limit:
%       includeZero = true
%       forceZeroBottom = true
%
%   - Nem hasznalunk BaseValue allitast.

    couplings = lower(string(opts.couplings));

    if numel(couplings) ~= 2
        error('paired_bar requires exactly two couplings, usually ["dc", "ac"].');
    end

    T1 = getT(data, couplings(1));
    T2 = getT(data, couplings(2));

    [T1, T2] = align_pair_tables(T1, T2);

    if get_logical_field(ps, 'hideZeroBess', true)
        [T1, T2] = remove_zero_bess_rows(T1, T2);
    end

    if height(T1) == 0
        title(ax, "No non-zero BESS candidates to plot", 'Interpreter', 'none');
        hide_right_axis(ax);
        return;
    end

    n = height(T1);
    [x, x1, x2, xMid, pitch] = pair_positions(n, ps);

    yField = string(ps.y);

    y1 = T1.(char(yField));
    y2 = T2.(char(yField));

    y = interleave_vectors(y1, y2) .* ps.scale;

    yyaxis(ax, 'left');

    requestedAbsWidth = get_numeric_field(ps, 'pairedBarWidth', 0.36);
    relWidth = min(0.80, requestedAbsWidth / pitch);

    b = bar(ax, x, y, relWidth, ...
        'DisplayName', string(yField));

    if isfield(ps, 'colors') && ~isempty(ps.colors)
        b.FaceColor = ps.colors(1, :);
    end

    xlim(ax, [min(x) - 0.7, max(x) + 0.7]);

    % ---------------------------------------------------------------------
    % FONTOS JAVITAS:
    %
    % A paired_bar is oszlopdiagram, ezert a tengelyt 0-rol kell inditani.
    % Kulonben pl. FinalSoH esetben 83-88 kozotti y-limit mellett az
    % oszlopok valojaban 0-rol indulnak, de a 0 nem latszik, emiatt ugy
    % tunik, mintha az oszlopok lecsusztak volna.
    % ---------------------------------------------------------------------
    if get_logical_field(ps, 'autoYLim', true)
        apply_auto_ylim( ...
            ax, ...
            y, ...
            get_numeric_field(ps, 'autoYMarginFrac', 0.20), ...
            true, ...   % includeZero
            true);      % forceZeroBottom
    end

    xticks(ax, x);
    xticklabels(ax, pair_ticklabels(n, couplings));

    add_bess_group_labels(ax, xMid, T1);

    if get_logical_field(ps, 'showValues', false)
        add_simple_bar_values(ax, x, y, ps.valueFmt);
    end

    hide_right_axis(ax);
end

% =========================================================================
% OTHER PLOT TYPES
% =========================================================================
function plot_area(ax, data, ps)

    T = sortrows(getT(data, string(ps.coupling)), char(ps.x));

    x = T.(char(ps.x));
    yFields = string(ps.y);

    Y = T{:, cellstr(yFields)} .* ps.scale;

    h = area(ax, x, Y);

    labels = get_labels(ps, yFields);

    for i = 1:numel(h)
        h(i).DisplayName = labels(i);
    end

    apply_bar_colors(h, ps);
end


function plot_scatter(ax, data, ps, opts)

    couplings = get_couplings(data, opts);

    for c = 1:numel(couplings)

        T = getT(data, couplings(c));

        x = T.(char(ps.x));
        y = T.(char(ps.y)) .* ps.scale;

        scatter(ax, x, y, 45, 'filled', ...
            'DisplayName', upper(couplings(c)));
    end
end


function plot_heatmap(ax, data, ps)

    T = getT(data, string(ps.coupling));

    x = T.(char(ps.x));
    y = T.(char(ps.y));
    z = T.(char(ps.z)) .* ps.scale;

    [xu, ~, ix] = unique(x);
    [yu, ~, iy] = unique(y);

    Z = nan(numel(yu), numel(xu));

    for i = 1:numel(z)
        Z(iy(i), ix(i)) = z(i);
    end

    imagesc(ax, xu, yu, Z);
    axis(ax, 'xy');

    xticks(ax, xu);
    yticks(ax, yu);

    xlabel(ax, string(ps.xlabel), 'Interpreter', 'none');
    ylabel(ax, string(ps.ylabel), 'Interpreter', 'none');
    title(ax, string(ps.title), 'Interpreter', 'none');

    cb = colorbar(ax);

    if isfield(ps, 'colorLabel') && ~isempty(ps.colorLabel)
        ylabel(cb, string(ps.colorLabel), 'Interpreter', 'none');
    end

    if isfield(ps, 'nanColor') && ~isempty(ps.nanColor)
        ax.Color = ps.nanColor;
    end
end


function plot_profile_line(ax, data, ps)

    item = data.(char(string(ps.coupling)));
    P = item.candidateProfiles.(char(ps.profile));

    idx = ps.row;

    if isfield(ps, 'xProfile') && ~isempty(ps.xProfile)
        x = ps.xProfile;
    else
        x = 1:size(P, 2);
    end

    plot(ax, x, P(idx, :) .* ps.scale, ...
        'LineWidth', 1.5, ...
        'DisplayName', string(ps.profile));
end


function plot_profile_heatmap(ax, data, ps)

    item = data.(char(string(ps.coupling)));
    P = item.candidateProfiles.(char(ps.profile)) .* ps.scale;

    imagesc(ax, P);
    axis(ax, 'xy');
    colorbar(ax);
end


% =========================================================================
% DATA HELPERS
% =========================================================================
function T = getT(data, coupling)

    data = unwrap_data(data);

    if ~isfield(data, char(coupling))
        error('Missing coupling field in data: %s', coupling);
    end

    if ~isfield(data.(char(coupling)), 'candidateTable')
        error('Missing candidateTable for coupling: %s', coupling);
    end

    T = data.(char(coupling)).candidateTable;
end


function data = unwrap_data(data)

    if isfield(data, 'data')
        data = data.data;
    end
end


function couplings = get_couplings(data, opts)

    data = unwrap_data(data);

    if isfield(opts, 'couplings') && ~isempty(opts.couplings)
        couplings = lower(string(opts.couplings));
    else
        names = string(fieldnames(data));
        keep = false(size(names));

        for i = 1:numel(names)
            value = data.(char(names(i)));
            keep(i) = isstruct(value) && isfield(value, 'candidateTable');
        end

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


function [T1, T2] = align_pair_tables(T1, T2)

    if ismember('candidateIndex', T1.Properties.VariableNames) && ...
       ismember('candidateIndex', T2.Properties.VariableNames)

        common = intersect(T1.candidateIndex, T2.candidateIndex, 'stable');

        idx1 = zeros(numel(common), 1);
        idx2 = zeros(numel(common), 1);

        for i = 1:numel(common)
            idx1(i) = find(T1.candidateIndex == common(i), 1, 'first');
            idx2(i) = find(T2.candidateIndex == common(i), 1, 'first');
        end

        T1 = T1(idx1, :);
        T2 = T2(idx2, :);
    else
        n = min(height(T1), height(T2));
        T1 = T1(1:n, :);
        T2 = T2(1:n, :);
    end
end


function [T1, T2] = remove_zero_bess_rows(T1, T2)

    if ~ismember('E_BESS_kWh', T1.Properties.VariableNames) || ...
       ~ismember('E_BESS_kWh', T2.Properties.VariableNames)
        return;
    end

    E1 = T1.E_BESS_kWh(:);
    E2 = T2.E_BESS_kWh(:);

    keep = ~(abs(E1) <= 1e-12 & abs(E2) <= 1e-12);

    T1 = T1(keep, :);
    T2 = T2(keep, :);
end


function Y = table_matrix(T, fields)

    fields = string(fields);
    Y = zeros(height(T), numel(fields));

    for j = 1:numel(fields)

        if ~ismember(fields(j), string(T.Properties.VariableNames))
            error('Missing table variable: %s', fields(j));
        end

        Y(:, j) = T.(char(fields(j)));
    end
end


% =========================================================================
% LABEL HELPERS
% =========================================================================
function labels = get_labels(ps, fields)

    if isfield(ps, 'labels') && ~isempty(ps.labels)
        labels = string(ps.labels);
    else
        labels = string(fields);
    end
end


function labels = get_line_labels(ps, fields)

    if isfield(ps, 'lineLabels') && ~isempty(ps.lineLabels)
        labels = string(ps.lineLabels);
    else
        labels = string(fields);
    end
end


function labels = pair_ticklabels(n, couplings)

    labels = strings(2 * n, 1);

    for i = 1:n
        labels(2*i - 1) = upper(couplings(1));
        labels(2*i) = upper(couplings(2));
    end
end


function add_bess_group_labels(ax, xMid, T)

    yyaxis(ax, 'left');

    if ~ismember('E_BESS_kWh', T.Properties.VariableNames)
        return;
    end

    E = T.E_BESS_kWh(:);

    yl = ylim(ax);
    yr = yl(2) - yl(1);

    if yr <= 0 || ~isfinite(yr)
        yr = 1;
    end

    yText = yl(1) - 0.10 * yr;

    ax.Clipping = 'off';

    for i = 1:numel(E)

        txt = sprintf('BESS %.0f kWh', E(i));

        text(ax, xMid(i), yText, txt, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top', ...
            'Rotation', 0, ...
            'Clipping', 'off', ...
            'FontSize', 8, ...
            'Interpreter', 'none', ...
            'HandleVisibility', 'off');
    end
end


% =========================================================================
% POSITION HELPERS
% =========================================================================
function [x, x1, x2, xMid, pitch] = pair_positions(n, ps)

    insidePairDistance = get_numeric_field(ps, 'insidePairDistance', 0.95);
    pairGroupGap = get_numeric_field(ps, 'pairGroupGap', 1.25);

    pitch = insidePairDistance + pairGroupGap;

    x1 = zeros(n, 1);
    x2 = zeros(n, 1);
    xMid = zeros(n, 1);

    for i = 1:n
        x1(i) = 1 + (i - 1) * pitch;
        x2(i) = x1(i) + insidePairDistance;
        xMid(i) = 0.5 * (x1(i) + x2(i));
    end

    x = zeros(2 * n, 1);
    x(1:2:end) = x1;
    x(2:2:end) = x2;
end


function y = interleave_vectors(v1, v2)

    if numel(v1) ~= numel(v2)
        error('Vector length differs in interleave_vectors.');
    end

    y = zeros(2 * numel(v1), 1);

    y(1:2:end) = v1(:);
    y(2:2:end) = v2(:);
end


function set_xt(ax, x)

    xticks(ax, x);
    xticklabels(ax, string(x));

    if numel(x) > 10
        xtickangle(ax, 45);
    end
end


function dx = bardx(x)

    x = unique(x(:));

    if numel(x) < 2
        dx = 1;
    else
        dx = median(diff(x));
    end

    if ~isfinite(dx) || dx <= 0
        dx = 1;
    end
end


function o = offsets(n, dx)

    if n <= 1
        o = 0;
    else
        o = linspace(-0.22 * dx, 0.22 * dx, n);
    end
end


function w = barwidth(n, dx)

    if n <= 1
        w = 0.55 * dx;
    else
        w = 0.34 * dx;
    end
end


% =========================================================================
% COLOR HELPERS
% =========================================================================
function apply_bar_colors(barHandles, ps)

    if ~isfield(ps, 'colors') || isempty(ps.colors)
        return;
    end

    for k = 1:numel(barHandles)
        barHandles(k).FaceColor = pick_color(ps.colors, k);
    end
end


function colors = get_coupling_colors(ps, coupling, nSeries)

    coupling = lower(string(coupling));

    if coupling == "dc" && isfield(ps, 'colorsDc') && ~isempty(ps.colorsDc)
        colors = ps.colorsDc;

    elseif coupling == "ac" && isfield(ps, 'colorsAc') && ~isempty(ps.colorsAc)
        colors = ps.colorsAc;

    elseif isfield(ps, 'colors') && ~isempty(ps.colors)
        colors = ps.colors;

    else
        colors = lines(nSeries);
    end

    if size(colors, 2) ~= 3
        error('Color matrix must have 3 columns: [R G B].');
    end

    if size(colors, 1) < nSeries
        baseColors = colors;
        colors = zeros(nSeries, 3);

        for i = 1:nSeries
            colors(i, :) = baseColors(1 + mod(i - 1, size(baseColors, 1)), :);
        end
    end
end


function apply_color_matrix_to_bars(barHandles, colors)

    for k = 1:numel(barHandles)
        barHandles(k).FaceColor = colors(k, :);
    end
end


function color = pick_color(colors, idx)

    if size(colors, 1) == 1
        color = colors(1, :);
    else
        color = colors(1 + mod(idx - 1, size(colors, 1)), :);
    end
end


% =========================================================================
% VALUE LABEL HELPERS
% =========================================================================
function add_values(ax, x, y, fmt)

    for i = 1:numel(x)

        if isfinite(y(i))
            text(ax, x(i), y(i), sprintf(fmt, y(i)), ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'bottom', ...
                'FontSize', 8, ...
                'HandleVisibility', 'off');
        end
    end
end


function add_group_values(ax, x, Y, fmt)

    dx = bardx(x);
    o = offsets(size(Y, 2), dx);

    for j = 1:size(Y, 2)

        for i = 1:numel(x)

            if isfinite(Y(i, j))
                text(ax, x(i) + o(j), Y(i, j), sprintf(fmt, Y(i, j)), ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'bottom', ...
                    'FontSize', 8, ...
                    'HandleVisibility', 'off');
            end
        end
    end
end


function add_stack_values(ax, x, Y, fmt)

    yyaxis(ax, 'left');

    totals = sum(abs(Y), 2);
    maxTotal = max(totals);

    if maxTotal <= 0
        return;
    end

    minVisible = 0.035 * maxTotal;

    posBase = zeros(numel(x), 1);
    negBase = zeros(numel(x), 1);

    for j = 1:size(Y, 2)

        for i = 1:numel(x)

            val = Y(i, j);

            if ~isfinite(val) || abs(val) < minVisible
                continue;
            end

            if val >= 0
                yText = posBase(i) + val / 2;
                posBase(i) = posBase(i) + val;
            else
                yText = negBase(i) + val / 2;
                negBase(i) = negBase(i) + val;
            end

            text(ax, x(i), yText, sprintf(fmt, val), ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontSize', 8, ...
                'HandleVisibility', 'off');
        end
    end
end


function add_simple_bar_values(ax, x, y, fmt)

    yyaxis(ax, 'left');

    yl = ylim(ax);
    dy = 0.015 * (yl(2) - yl(1));

    for i = 1:numel(x)

        if ~isfinite(y(i))
            continue;
        end

        text(ax, x(i), y(i) + dy, sprintf(fmt, y(i)), ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', ...
            'FontSize', 8, ...
            'HandleVisibility', 'off');
    end
end


% =========================================================================
% AXIS HELPERS
% =========================================================================
function yLimits = apply_auto_ylim(ax, values, marginFrac, includeZero, forceZeroBottom)

    values = values(:);
    values = values(isfinite(values));

    if isempty(values)
        yLimits = ylim(ax);
        return;
    end

    if includeZero
        values = [values; 0];
    end

    yMin = min(values);
    yMax = max(values);

    if abs(yMax - yMin) <= 1e-12
        base = max(abs(yMax), 1);
        pad = marginFrac * base;
    else
        pad = marginFrac * (yMax - yMin);
    end

    yLow = yMin - pad;
    yHigh = yMax + pad;

    if forceZeroBottom
        yLow = 0;
    elseif includeZero && yLow > 0
        yLow = 0;
    end

    if abs(yHigh - yLow) <= 1e-12
        yHigh = yLow + 1;
    end

    yLimits = [yLow, yHigh];
    ylim(ax, yLimits);
end


function hide_right_axis(ax)

    if numel(ax.YAxis) >= 2
        ax.YAxis(2).Visible = 'off';
    end

    yyaxis(ax, 'left');
end


% =========================================================================
% GENERAL HELPERS
% =========================================================================
function S = setdef(S, name, value)

    if ~isfield(S, name) || isempty(S.(name))
        S.(name) = value;
    end
end


function value = get_logical_field(S, fieldName, defaultValue)

    if ~isfield(S, fieldName) || isempty(S.(fieldName))
        value = logical(defaultValue);
        return;
    end

    raw = S.(fieldName);

    if islogical(raw)
        value = any(raw(:));
        return;
    end

    if isnumeric(raw)
        value = any(raw(:) ~= 0);
        return;
    end

    if isstring(raw) || ischar(raw)
        txt = lower(string(raw));

        if any(txt == "true") || any(txt == "1") || any(txt == "yes")
            value = true;
        elseif any(txt == "false") || any(txt == "0") || any(txt == "no")
            value = false;
        else
            error('Field %s must be logical-like. Current value: %s', ...
                fieldName, strjoin(txt, ", "));
        end

        return;
    end

    error('Field %s must be logical, numeric, string, or char.', fieldName);
end


function value = get_numeric_field(S, fieldName, defaultValue)

    if ~isfield(S, fieldName) || isempty(S.(fieldName))
        value = defaultValue;
        return;
    end

    value = S.(fieldName);

    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
        error('Field %s must be a finite numeric scalar.', fieldName);
    end
end

function yLimits = apply_symmetric_ylim_around_zero(ax, values, marginFrac)
% APPLY_SYMMETRIC_YLIM_AROUND_ZERO
%
% A y-tengelyt szimmetrikusra allitja 0 korul.
%
% Ez signed stacked bar abranal hasznos, ahol:
%   - pozitiv irany = megtakaritas
%   - negativ irany = tobbletkoltseg
%
% Igy a 0-vonal vizualisan az abra kozepebe kerul.

    values = values(:);
    values = values(isfinite(values));

    if isempty(values)
        yLimits = ylim(ax);
        return;
    end

    maxAbs = max(abs(values));

    if maxAbs <= 1e-12
        maxAbs = 1;
    end

    maxAbs = maxAbs * (1 + marginFrac);

    yLimits = [-maxAbs, maxAbs];

    ylim(ax, yLimits);
end