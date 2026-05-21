function figureHandles = plot_arbitrage_energy_flow_figures(tableAll, cfg, outputFolder)
% PLOT_ARBITRAGE_ENERGY_FLOW_FIGURES
%
% Plusz dolgozati abrakat keszit az energiaarbitrazs / AC-DC osszehasonlitas
% kiertekelesehez.
%
% A gorbek/oszlopok minden BESS/PV racspontnal parositva jelennek meg:
%   bal oldali oszlop: DC
%   jobb oldali oszlop: AC
%
% Abrak:
%   1) SoH es BESS toltes/kisutes energiak
%   2) Grid/PV energiaaramlasok
%   3) Vesztesegkomponensek
%   4) Jelenlegi es idealis, vesztesegmentes energiaoldali megtakaritas

    if nargin < 3 || isempty(outputFolder)
        outputFolder = pwd;
    end

    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    T = tableAll;
    T = T(logical(T.wasSimulated) & ~logical(T.hasError), :);

    if isempty(T) || height(T) == 0
        error('Nincs ervenyes candidate az extra arbitrazs abrakhoz.');
    end

    T = local_prepare_missing_columns(T, cfg);

    ratios = unique(T.BESS_PV_ratio(:));
    ratios = sort(ratios(:).');

    figureHandles = struct();
    figureHandles.sohAndBessEnergy = local_plot_soh_and_bess_energy(T, ratios, outputFolder);
    figureHandles.gridPvFlowsAndLosses = local_plot_grid_pv_flows_and_losses(T, ratios, outputFolder);
    figureHandles.idealSavings = local_plot_ideal_savings(T, ratios, cfg, outputFolder);
end


% =========================================================================
% FIGURE 1
% =========================================================================
function fig = local_plot_soh_and_bess_energy(T, ratios, outputFolder)

    fig = figure('Name', 'Arbitrage SoH and BESS energy', ...
        'Position', [80, 80, 1500, 850]);

    tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile;
    hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');

    ySoH = local_matrix_by_coupling(T, ratios, 'finalSoH');
    local_grouped_bar(ax1, ratios, ySoH, false);

    ylabel(ax1, 'Final SoH [-]');
    title(ax1, 'Akkumulator vegso allapota a BESS meret fuggvenyeben');
    local_apply_bess_axis(ax1, T, ratios);
    legend(ax1, {'DC', 'AC'}, 'Location', 'best');

    ax2 = nexttile;
    hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');

    dcCharge = local_vector(T, ratios, "dc", 'bessCharge_kWh') ./ 1000;
    dcDis = local_vector(T, ratios, "dc", 'bessDischarge_kWh') ./ 1000;
    acCharge = local_vector(T, ratios, "ac", 'bessCharge_kWh') ./ 1000;
    acDis = local_vector(T, ratios, "ac", 'bessDischarge_kWh') ./ 1000;

    local_grouped_stacked_bar(ax2, ratios, ...
        cat(3, [dcDis; dcCharge - dcDis].', [acDis; acCharge - acDis].'), ...
        {'BESS-bol kisutott energia', 'Round-trip veszteseg'});

    ylabel(ax2, 'Energia [MWh / szimulalt idoszak]');
    title(ax2, 'BESS-be toltott es BESS-bol kisutott energia');
    local_apply_bess_axis(ax2, T, ratios);

    local_save_figure(fig, outputFolder, 'arbitrage_01_soh_bess_energy');
end


% =========================================================================
% FIGURE 2
% =========================================================================
function fig = local_plot_grid_pv_flows_and_losses(T, ratios, outputFolder)

    fig = figure('Name', 'Arbitrage grid, PV and loss energy flows', ...
        'Position', [90, 70, 1550, 1050]);

    tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

     % =====================================================================
    % 1) Grid -> BESS es BESS -> load energia
    % =====================================================================
    ax1 = nexttile;
    hold(ax1, 'on');
    grid(ax1, 'on');
    box(ax1, 'on');

    dcGridToBess = local_vector(T, ratios, "dc", 'gridToBess_kWh') ./ 1000;
    dcBessToLoad = local_vector(T, ratios, "dc", 'bessToLoad_kWh') ./ 1000;

    acGridToBess = local_vector(T, ratios, "ac", 'gridToBess_kWh') ./ 1000;
    acBessToLoad = local_vector(T, ratios, "ac", 'bessToLoad_kWh') ./ 1000;

    dcConversionDifference = dcGridToBess - dcBessToLoad;
    acConversionDifference = acGridToBess - acBessToLoad;

    dcEta_pct = 100 .* local_safe_divide(dcBessToLoad, dcGridToBess);
    acEta_pct = 100 .* local_safe_divide(acBessToLoad, acGridToBess);

    local_grouped_stacked_bar_with_efficiency(ax1, ratios, ...
        cat(3, ...
            [dcBessToLoad; dcConversionDifference].', ...
            [acBessToLoad; acConversionDifference].'), ...
        {'BESS -> fogyaszto', 'Grid -> BESS es BESS -> fogyaszto kulonbsege'}, ...
        dcEta_pct, ...
        acEta_pct);

    ylabel(ax1, 'Energia [MWh / szimulalt idoszak]');
    title(ax1, 'Grid -> BESS energia es BESS -> fogyaszto energia');
    local_apply_bess_axis(ax1, T, ratios);

    % =====================================================================
    % 2) PV energia hasznositasa
    % =====================================================================
    ax2 = nexttile;
    hold(ax2, 'on');
    grid(ax2, 'on');
    box(ax2, 'on');

    dcPvTotal = local_vector(T, ratios, "dc", 'pvEnergyAvailable_kWh') ./ 1000;
    dcPvToLoad = local_vector(T, ratios, "dc", 'pvToLoad_kWh') ./ 1000;
    dcPvToBess = local_vector(T, ratios, "dc", 'pvToBess_kWh') ./ 1000;
    dcPvUnused = max(dcPvTotal - dcPvToLoad - dcPvToBess, 0);

    acPvTotal = local_vector(T, ratios, "ac", 'pvEnergyAvailable_kWh') ./ 1000;
    acPvToLoad = local_vector(T, ratios, "ac", 'pvToLoad_kWh') ./ 1000;
    acPvToBess = local_vector(T, ratios, "ac", 'pvToBess_kWh') ./ 1000;
    acPvUnused = max(acPvTotal - acPvToLoad - acPvToBess, 0);

    local_grouped_stacked_bar(ax2, ratios, ...
        cat(3, [dcPvToLoad; dcPvToBess; dcPvUnused].', ...
               [acPvToLoad; acPvToBess; acPvUnused].'), ...
        {'PV -> fogyaszto', 'PV -> BESS', 'Nem hasznositott PV energia'});

    ylabel(ax2, 'Energia [MWh / szimulalt idoszak]');
    title(ax2, 'PV energia hasznositasa');
    local_apply_bess_axis(ax2, T, ratios);

    % =====================================================================
    % 3) Vesztesegkomponensek
    % =====================================================================
    ax3 = nexttile;
    hold(ax3, 'on');
    grid(ax3, 'on');
    box(ax3, 'on');

    dcCentral = local_vector(T, ratios, "dc", 'centralInverterLoss_kWh') ./ 1000;
    dcPcsb = local_vector(T, ratios, "dc", 'pcsbInverterLoss_kWh') ./ 1000;
    dcDcdc = local_vector(T, ratios, "dc", 'dcdcLoss_kWh') ./ 1000;
    dcBess = local_vector(T, ratios, "dc", 'bessInternalLoss_kWh') ./ 1000;

    acCentral = local_vector(T, ratios, "ac", 'centralInverterLoss_kWh') ./ 1000;
    acPcsb = local_vector(T, ratios, "ac", 'pcsbInverterLoss_kWh') ./ 1000;
    acDcdc = local_vector(T, ratios, "ac", 'dcdcLoss_kWh') ./ 1000;
    acBess = local_vector(T, ratios, "ac", 'bessInternalLoss_kWh') ./ 1000;

    local_grouped_stacked_bar(ax3, ratios, ...
        cat(3, [dcCentral; dcPcsb; dcDcdc; dcBess].', ...
               [acCentral; acPcsb; acDcdc; acBess].'), ...
        {'Kozponti inverter', 'BESS PCS inverter', 'DC/DC konverter', 'BESS belso'});

    ylabel(ax3, 'Veszteseg [MWh / szimulalt idoszak]');
    title(ax3, 'Energiaatalakitasi es BESS vesztesegkomponensek');
    local_apply_bess_axis(ax3, T, ratios);

    sgtitle(fig, 'Grid-, PV- es vesztesegaramlasok AC es DC topologia szerint');

    local_save_figure(fig, outputFolder, 'arbitrage_02_grid_pv_energy_flows');
end


% =========================================================================
% FIGURE 4
% =========================================================================
function fig = local_plot_ideal_savings(T, ratios, cfg, outputFolder)

    fig = figure('Name', 'Arbitrage current and ideal energy savings', ...
        'Position', [110, 110, 1550, 850]);

    tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile;
    hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');

    dcCurrent = local_vector(T, ratios, "dc", 'energySavingVsNoBess_HUF') ./ 1e6;
    acCurrent = local_vector(T, ratios, "ac", 'energySavingVsNoBess_HUF') ./ 1e6;

    dcLossValue = local_ideal_loss_value(T, ratios, "dc", cfg) ./ 1e6;
    acLossValue = local_ideal_loss_value(T, ratios, "ac", cfg) ./ 1e6;

    local_grouped_stacked_bar(ax1, ratios, ...
        cat(3, [dcCurrent; dcLossValue].', [acCurrent; acLossValue].'), ...
        {'Jelenlegi energiaoldali megtakaritas', 'Idealizalt vesztesegmentes tobblet'});

    ylabel(ax1, 'Megtakaritas [millio HUF / szimulalt idoszak]');
    title(ax1, 'Jelenlegi es idealis vesztesegmentes energiaoldali megtakaritas');
    local_apply_bess_axis(ax1, T, ratios);

    ax2 = nexttile;
    hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');

    dcPct = 100 .* local_safe_divide(dcLossValue, max(dcCurrent, 0));
    acPct = 100 .* local_safe_divide(acLossValue, max(acCurrent, 0));

    plot(ax2, 1:numel(ratios), dcPct, '-o', 'LineWidth', 1.6, 'DisplayName', 'DC idealis tobblet');
    plot(ax2, 1:numel(ratios), acPct, '-s', 'LineWidth', 1.6, 'DisplayName', 'AC idealis tobblet');

    ylabel(ax2, 'Megtakaritas-novekedes [%]');
    title(ax2, 'Idealizalt vesztesegmentes rendszer tobblete a jelenlegi megtakaritashoz kepest');
    local_apply_bess_axis(ax2, T, ratios);
    legend(ax2, 'Location', 'best');

    local_save_figure(fig, outputFolder, 'arbitrage_03_current_vs_ideal_savings');
end


% =========================================================================
% DATA PREPARATION
% =========================================================================
function T = local_prepare_missing_columns(T, cfg)

    n = height(T);
    names = T.Properties.VariableNames;

    numericDefaults = { ...
        'pvToLoad_kWh', 0; ...
        'gridToLoad_kWh', 0; ...
        'bessToLoad_kWh', 0; ...
        'pvToBess_kWh', 0; ...
        'gridToBess_kWh', 0; ...
        'centralInverterLoss_kWh', NaN; ...
        'pcsbInverterLoss_kWh', 0; ...
        'inverterLoss_kWh', 0; ...
        'dcdcLoss_kWh', 0; ...
        'bessInternalLoss_kWh', 0; ...
        'clippedEnergy_kWh', 0; ...
        'energySavingVsNoBess_HUF', NaN};

    for i = 1:size(numericDefaults, 1)
        name = numericDefaults{i, 1};
        value = numericDefaults{i, 2};

        if ~ismember(name, names)
            T.(name) = repmat(value, n, 1);
        end
    end

    if any(~isfinite(T.energySavingVsNoBess_HUF))
        if ismember('energyCostNoBess_HUF', T.Properties.VariableNames) && ismember('energyCost_HUF', T.Properties.VariableNames)
            T.energySavingVsNoBess_HUF = T.energyCostNoBess_HUF - T.energyCost_HUF;
        else
            T.energySavingVsNoBess_HUF = zeros(n, 1);
        end
    end

    % Ha a central/PCSB bontas meg nincs meg regi futasbol, akkor a teljes
    % invertervesztesegbol keszitunk kompatibilis becslest:
    %   DC: teljes inverterveszteseg -> kozponti inverter
    %   AC: teljes inverterveszteseg -> kozponti inverter, PCSB ismeretlen 0
    % Pontos bontashoz ujra kell futtatni a szimulaciot a friss kod utan.
    missingCentral = ~isfinite(T.centralInverterLoss_kWh);
    T.centralInverterLoss_kWh(missingCentral) = T.inverterLoss_kWh(missingCentral);

    if ~ismember('pvEnergyAvailable_kWh', T.Properties.VariableNames)
        error('Missing pvEnergyAvailable_kWh in candidate table.');
    end

    if ~ismember('finalSoH', T.Properties.VariableNames)
        T.finalSoH = ones(n, 1);
    end

    if ~ismember('coupling', T.Properties.VariableNames)
        error('Missing coupling column.');
    end
end


function y = local_ideal_loss_value(T, ratios, coupling, cfg)

    totalLoss_kWh = ...
        local_vector(T, ratios, coupling, 'centralInverterLoss_kWh') + ...
        local_vector(T, ratios, coupling, 'pcsbInverterLoss_kWh') + ...
        local_vector(T, ratios, coupling, 'dcdcLoss_kWh') + ...
        local_vector(T, ratios, coupling, 'bessInternalLoss_kWh');

    price = cfg.cost.grid_import_huf_per_kWh;
    y = totalLoss_kWh .* price;
end


% =========================================================================
% TABLE HELPERS
% =========================================================================
function y = local_matrix_by_coupling(T, ratios, fieldName)

    y = [ ...
        local_vector(T, ratios, "dc", fieldName), ...
        local_vector(T, ratios, "ac", fieldName)];
end


function y = local_vector(T, ratios, coupling, fieldName)

    y = NaN(numel(ratios), 1);

    if ~ismember(fieldName, T.Properties.VariableNames)
        return;
    end

    for i = 1:numel(ratios)
        mask = T.coupling == coupling & abs(T.BESS_PV_ratio - ratios(i)) < 1e-9;
        idx = find(mask, 1);

        if ~isempty(idx)
            y(i) = T.(fieldName)(idx);
        end
    end

    y(~isfinite(y)) = 0;
end


function labels = local_xlabels(T, ratios)

    labels = strings(numel(ratios), 1);

    for i = 1:numel(ratios)
        idx = find(abs(T.BESS_PV_ratio - ratios(i)) < 1e-9, 1);

        if isempty(idx)
            labels(i) = sprintf('BESS: - (%.2g)', ratios(i));
        else
            labels(i) = sprintf('E_{BESS}: %.0f kWh (%.2g)', T.E_BESS_kWh(idx), ratios(i));
        end
    end
end


% =========================================================================
% PLOT HELPERS
% =========================================================================
function local_grouped_bar(ax, ratios, Y, stacked)

    %#ok<INUSD>
    bar(ax, 1:numel(ratios), Y, 'grouped');
end


function local_grouped_stacked_bar(ax, ratios, data3d, legendLabels)
% data3d: nRatio x nStack x 2, ahol 1=DC, 2=AC

    n = numel(ratios);
    nStack = size(data3d, 2);
    width = 0.36;
    offset = 0.20;

    baseX = 1:n;
    xDC = baseX - offset;
    xAC = baseX + offset;

    bDC = bar(ax, xDC, data3d(:, :, 1), width, 'stacked');
    bAC = bar(ax, xAC, data3d(:, :, 2), width, 'stacked');

    for k = 1:nStack
        bAC(k).FaceColor = bDC(k).FaceColor;
        bAC(k).HandleVisibility = 'off';
    end

    legend(ax, bDC, legendLabels, 'Location', 'bestoutside');

    yl = ylim(ax);
    yText = yl(1) + 0.96 * (yl(2) - yl(1));

    for i = 1:n
        text(ax, xDC(i), yText, 'DC', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top', ...
            'FontSize', 8, ...
            'Rotation', 90);
        text(ax, xAC(i), yText, 'AC', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top', ...
            'FontSize', 8, ...
            'Rotation', 90);
    end
end


function local_apply_bess_axis(ax, T, ratios)

    xticks(ax, 1:numel(ratios));
    xticklabels(ax, cellstr(local_xlabels(T, ratios)));
    xtickangle(ax, 30);
    ax.TickLabelInterpreter = 'tex';
    xlabel(ax, 'E_{BESS} (BESS/PV arany)');
end


function y = local_safe_divide(a, b)

    y = NaN(size(a));
    mask = isfinite(a) & isfinite(b) & abs(b) > 1e-12;
    y(mask) = a(mask) ./ b(mask);
    y(~isfinite(y)) = 0;
end


function local_save_figure(fig, outputFolder, fileName)

    savefig(fig, fullfile(outputFolder, [fileName, '.fig']));

    try
        exportgraphics(fig, fullfile(outputFolder, [fileName, '.png']), 'Resolution', 150);
    catch
        saveas(fig, fullfile(outputFolder, [fileName, '.png']));
    end
end

function local_grouped_stacked_bar_with_efficiency(ax, ratios, data3d, legendLabels, dcEta_pct, acEta_pct)
% LOCAL_GROUPED_STACKED_BAR_WITH_EFFICIENCY
%
% data3d: nRatio x nStack x 2
%   (:,:,1) = DC stacked oszlopok
%   (:,:,2) = AC stacked oszlopok
%
% Az oszlopok a bal y tengelyen energiaerteket mutatnak.
% A DC es AC hatasfokgorbek a jobb y tengelyen jelennek meg.

    n = numel(ratios);
    nStack = size(data3d, 2);

    width = 0.36;
    offset = 0.20;

    baseX = 1:n;
    xDC = baseX - offset;
    xAC = baseX + offset;

    yyaxis(ax, 'left');

    bDC = bar(ax, xDC, data3d(:, :, 1), width, 'stacked');
    bAC = bar(ax, xAC, data3d(:, :, 2), width, 'stacked');

    for k = 1:nStack
        bAC(k).FaceColor = bDC(k).FaceColor;
        bAC(k).HandleVisibility = 'off';
    end

    ylabel(ax, 'Energia [MWh / szimulalt idoszak]');

    yyaxis(ax, 'right');

    p1 = plot(ax, baseX, dcEta_pct, '-o', ...
        'LineWidth', 1.5, ...
        'MarkerSize', 5, ...
        'DisplayName', 'DC hatasfok');

    p2 = plot(ax, baseX, acEta_pct, '-s', ...
        'LineWidth', 1.5, ...
        'MarkerSize', 5, ...
        'DisplayName', 'AC hatasfok');

    ylabel(ax, 'Hatasfok [%]');

    finiteEta = [dcEta_pct(:); acEta_pct(:)];
    finiteEta = finiteEta(isfinite(finiteEta));

    if ~isempty(finiteEta)
        yMin = max(0, min(finiteEta) - 5);
        yMax = min(110, max(finiteEta) + 5);

        if yMax <= yMin
            yMin = 0;
            yMax = 100;
        end

        ylim(ax, [yMin, yMax]);
    else
        ylim(ax, [0, 100]);
    end

    yyaxis(ax, 'left');

    yl = ylim(ax);
    yText = yl(1) + 0.96 * (yl(2) - yl(1));

    for i = 1:n
        text(ax, xDC(i), yText, 'DC', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top', ...
            'FontSize', 8, ...
            'Rotation', 90);

        text(ax, xAC(i), yText, 'AC', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top', ...
            'FontSize', 8, ...
            'Rotation', 90);
    end

    legend(ax, [bDC(:); p1; p2], ...
        [legendLabels(:); {'DC hatasfok'; 'AC hatasfok'}], ...
        'Location', 'bestoutside');
end
