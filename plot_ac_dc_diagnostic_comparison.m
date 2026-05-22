function out = plot_ac_dc_diagnostic_comparison(runResult, cfgBase, objectiveMode, candidateList)
% PLOT_AC_DC_DIAGNOSTIC_COMPARISON
%
% Teljes szimulalt idoszakra vonatkozo AC/DC diagnosztikai osszehasonlito
% abra a candidateTable-ben mentett, topologia-szintu kanonikus metrikak
% alapjan.
%
% Ez a fuggveny nem a final_day idosorokbol dolgozik, hanem a teljes
% szimulalt horizonra osszegzett DB.candidateTable oszlopokbol.

    out = struct();
    out.outputFolder = "";
    out.figureFiles = strings(0, 1);
    out.tableFiles = strings(0, 1);

    objectiveMode = lower(string(objectiveMode));

    if ~isfield(runResult, 'dc') || ~isfield(runResult, 'ac')
        fprintf('AC/DC diagnostic comparison skipped: runResult.dc or runResult.ac missing.\n');
        return;
    end

    if ~isfield(runResult.dc, 'DB') || ~isfield(runResult.ac, 'DB')
        fprintf('AC/DC diagnostic comparison skipped: DB missing.\n');
        return;
    end

    DBdc = runResult.dc.DB;
    DBac = runResult.ac.DB;

    if ~isfield(DBdc, 'candidateTable') || ~isfield(DBac, 'candidateTable')
        fprintf('AC/DC diagnostic comparison skipped: candidateTable missing.\n');
        return;
    end

    Tdc = DBdc.candidateTable;
    Tac = DBac.candidateTable;

    if nargin < 4 || isempty(candidateList)
        candidateList = 1:min(height(Tdc), height(Tac));
    end

    candidateList = unique(candidateList(:).', 'stable');

    outFolder = fullfile( ...
        cfgBase.paths.results, ...
        char(objectiveMode), ...
        'diagnostics', ...
        'ac_dc_comparison');

    if ~exist(outFolder, 'dir')
        mkdir(outFolder);
    end

    out.outputFolder = string(outFolder);

    for ii = 1:numel(candidateList)

        candidateIndex = candidateList(ii);

        if candidateIndex < 1 || candidateIndex > height(Tdc) || candidateIndex > height(Tac)
            fprintf('AC/DC diagnostic comparison skipped for invalid candidate index: %d\n', candidateIndex);
            continue;
        end

        if local_is_baseline_candidate(Tdc, candidateIndex)
            continue;
        end

        Mdc = local_collect_metrics(Tdc, candidateIndex, "DC");
        Mac = local_collect_metrics(Tac, candidateIndex, "AC");

        metricTable = struct2table([Mdc; Mac]);

        tableFile = fullfile(outFolder, sprintf('ac_dc_diagnostic_comparison_candidate_%06d.csv', candidateIndex));
        writetable(metricTable, tableFile);
        out.tableFiles(end+1, 1) = string(tableFile); %#ok<AGROW>

        fig = local_plot_one_candidate(metricTable, candidateIndex);

        fileBase = fullfile(outFolder, sprintf('ac_dc_diagnostic_comparison_candidate_%06d', candidateIndex));
        local_safe_save_figure(fig, fileBase);
        out.figureFiles(end+1, 1) = string([fileBase, '.png']); %#ok<AGROW>
    end

    fprintf('AC/DC diagnostic comparison saved for full simulated period:\n%s\n', outFolder);
end


function M = local_collect_metrics(T, rowIdx, coupling)

    M = struct();
    M.coupling = string(coupling);
    M.candidateIndex = rowIdx;

    M.P_PV_kW = local_metric(T, rowIdx, 'P_PV_kW');
    M.P_inv_kW = local_metric(T, rowIdx, 'P_inv_kW');
    M.E_BESS_kWh = local_metric(T, rowIdx, 'E_BESS_kWh');
    M.BESS_PV_ratio = local_metric(T, rowIdx, 'BESS_PV_ratio');

    M.gridImportNoBess_kWh = local_first_existing_metric(T, rowIdx, {'gridImportNoBess_kWh', 'gridImportBase_kWh'});
    M.gridImport_kWh = local_first_existing_metric(T, rowIdx, {'gridImport_kWh', 'gridEnergyImport_kWh'});
    M.gridToLoad_kWh = local_metric(T, rowIdx, 'gridToLoad_kWh');
    M.gridToBess_kWh = local_metric(T, rowIdx, 'gridToBess_kWh');
    M.gridToBessStored_kWh = local_metric(T, rowIdx, 'gridToBessStored_kWh');

    M.pvToBess_kWh = local_metric(T, rowIdx, 'pvToBess_kWh');
    M.pvToBessStored_kWh = local_metric(T, rowIdx, 'pvToBessStored_kWh');

    M.bessDischargeBeforeConversion_kWh = local_metric(T, rowIdx, 'bessDischargeBeforeConversion_kWh');
    M.bessToLoad_kWh = local_metric(T, rowIdx, 'bessToLoad_kWh');

    M.gridToBessLoss_kWh = local_metric(T, rowIdx, 'gridToBessLoss_kWh');
    M.pvToBessLoss_kWh = local_metric(T, rowIdx, 'pvToBessLoss_kWh');
    M.bessToLoadConversionLoss_kWh = local_metric(T, rowIdx, 'bessToLoadConversionLoss_kWh');

    M.centralInverterLoss_kWh = local_metric(T, rowIdx, 'centralInverterLoss_kWh');
    M.dcdcLoss_kWh = local_metric(T, rowIdx, 'dcdcLoss_kWh');
    M.pcsbInverterLoss_kWh = local_metric(T, rowIdx, 'pcsbInverterLoss_kWh');
    M.bessInternalLoss_kWh = local_metric(T, rowIdx, 'bessInternalLoss_kWh');

    M.totalConverterLoss_kWh = local_sum_finite([ ...
        M.centralInverterLoss_kWh, ...
        M.dcdcLoss_kWh, ...
        M.pcsbInverterLoss_kWh]);

    M.trackedPathConverterLoss_kWh = local_sum_finite([ ...
        M.gridToBessLoss_kWh, ...
        M.pvToBessLoss_kWh, ...
        M.bessToLoadConversionLoss_kWh]);

    M.otherConverterLoss_kWh = max(M.totalConverterLoss_kWh - M.trackedPathConverterLoss_kWh, 0);

    M.gridImportReduction_kWh = M.gridImportNoBess_kWh - M.gridImport_kWh;
    M.gridImport_pct_of_noBess = 100 * local_safe_divide(M.gridImport_kWh, M.gridImportNoBess_kWh);
    M.gridImportReduction_pct = 100 * local_safe_divide(M.gridImportReduction_kWh, M.gridImportNoBess_kWh);
    M.gridToBess_pct_of_noBess = 100 * local_safe_divide(M.gridToBess_kWh, M.gridImportNoBess_kWh);

    M.gridToBess_charge_eff_pct = 100 * local_safe_divide(M.gridToBessStored_kWh, M.gridToBess_kWh);
    M.bessDischarge_to_load_eff_pct = 100 * local_safe_divide(M.bessToLoad_kWh, M.bessDischargeBeforeConversion_kWh);
    M.gridToBess_to_bessLoad_ratio_pct = 100 * local_safe_divide(M.bessToLoad_kWh, M.gridToBess_kWh);

    M.energyCostNoBess_HUF = local_metric(T, rowIdx, 'energyCostNoBess_HUF');
    M.energyCost_HUF = local_metric(T, rowIdx, 'energyCost_HUF');
    M.energyCostSaving_HUF = M.energyCostNoBess_HUF - M.energyCost_HUF;

    M.gridToBessImportCost_HUF = local_metric(T, rowIdx, 'gridToBessImportCost_HUF');
    M.gridToBessStoredImportEquivCost_HUF = local_metric(T, rowIdx, 'gridToBessStoredImportEquivCost_HUF');
    M.bessDischargeBeforeConversionImportEquivCost_HUF = local_metric(T, rowIdx, 'bessDischargeBeforeConversionImportEquivCost_HUF');
    M.bessToLoadImportEquivCost_HUF = local_metric(T, rowIdx, 'bessToLoadImportEquivCost_HUF');

    M.gridToBessChargeLossValue_HUF = ...
        M.gridToBessImportCost_HUF - M.gridToBessStoredImportEquivCost_HUF;

    M.bessDischargePathLossValue_HUF = ...
        M.bessDischargeBeforeConversionImportEquivCost_HUF - M.bessToLoadImportEquivCost_HUF;

    M.totalTrackedLossValue_HUF = local_sum_finite([ ...
        M.gridToBessChargeLossValue_HUF, ...
        M.bessDischargePathLossValue_HUF]);

    M.savingAfterTrackedLossValue_HUF = ...
        M.energyCostSaving_HUF - M.totalTrackedLossValue_HUF;
end


function fig = local_plot_one_candidate(M, candidateIndex)

    labels = cellstr(M.coupling);
    xTopo = 1:height(M);

    fig = figure( ...
        'Name', sprintf('AC/DC full-period diagnostic comparison - candidate %06d', candidateIndex), ...
        'Position', [60, 40, 1650, 1120]);

    tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    % ------------------------------------------------------------------
    % 1) Energy-chain plot: grid charging and final useful BESS energy
    % ------------------------------------------------------------------
    ax1 = nexttile;
    hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');

    stageNames = { ...
        sprintf('Grid -> BESS\nkonverzió előtt'), ...
        sprintf('Grid eredetű\neltárolt energia'), ...
        sprintf('BESS kisütés\nkonverzió előtt'), ...
        sprintf('BESS -> fogyasztó\nhasznos energia')};

    stageX = 1:numel(stageNames);
    chainDataMWh = [ ...
        M.gridToBess_kWh, ...
        M.gridToBessStored_kWh, ...
        M.bessDischargeBeforeConversion_kWh, ...
        M.bessToLoad_kWh] ./ 1000;

    bar(ax1, stageX, chainDataMWh.', 'grouped');

    for r = 1:height(M)
        plot(ax1, stageX, chainDataMWh(r, :), '-o', 'LineWidth', 1.6, ...
            'MarkerSize', 6, 'DisplayName', labels{r});
    end

    set(ax1, 'XTick', stageX, 'XTickLabel', stageNames);
    ylabel(ax1, 'Energia [MWh / teljes időszak]');
    title(ax1, 'Hálózatból töltött energia útja és BESS-ből hasznosult energia');
    legend(ax1, labels, 'Location', 'best');

    local_add_value_labels(ax1, stageX, chainDataMWh, '%.0f');

    % ------------------------------------------------------------------
    % 2) Loss components
    % ------------------------------------------------------------------
    ax2 = nexttile;
    hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');

    lossDataMWh = [ ...
        M.gridToBessLoss_kWh, ...
        M.pvToBessLoss_kWh, ...
        M.bessToLoadConversionLoss_kWh, ...
        M.otherConverterLoss_kWh, ...
        M.bessInternalLoss_kWh] ./ 1000;

    bar(ax2, xTopo, lossDataMWh, 'stacked');
    set(ax2, 'XTick', xTopo, 'XTickLabel', labels);
    ylabel(ax2, 'Veszteség [MWh / teljes időszak]');
    title(ax2, 'Veszteségkomponensek topológiánként');
    legend(ax2, { ...
        sprintf('Grid -> BESS\nkonverziós veszteség'), ...
        sprintf('PV -> BESS\nkonverziós veszteség'), ...
        sprintf('BESS -> fogyasztó\nkonverziós veszteség'), ...
        sprintf('Egyéb konverziós\nveszteség'), ...
        sprintf('BESS belső\nveszteség')}, ...
        'Location', 'bestoutside');

    % ------------------------------------------------------------------
    % 3) Percentage diagnostics
    % ------------------------------------------------------------------
    ax3 = nexttile;
    hold(ax3, 'on'); grid(ax3, 'on'); box(ax3, 'on');

    pctNames = { ...
        sprintf('Teljes grid import\n/ noBESS import'), ...
        sprintf('Grid import\ncsökkenése'), ...
        sprintf('Grid -> BESS\n/ noBESS import'), ...
        sprintf('Grid -> BESS\ntöltési hatásfok'), ...
        sprintf('BESS kisütés ->\nfogyasztó hatásfok'), ...
        sprintf('BESS -> fogyasztó\n/ grid -> BESS')};

    pctX = 1:numel(pctNames);
    pctData = [ ...
        M.gridImport_pct_of_noBess, ...
        M.gridImportReduction_pct, ...
        M.gridToBess_pct_of_noBess, ...
        M.gridToBess_charge_eff_pct, ...
        M.bessDischarge_to_load_eff_pct, ...
        M.gridToBess_to_bessLoad_ratio_pct];

    bar(ax3, pctX, pctData.', 'grouped');
    for r = 1:height(M)
        plot(ax3, pctX, pctData(r, :), '-o', 'LineWidth', 1.6, ...
            'MarkerSize', 6, 'DisplayName', labels{r});
    end
    yline(ax3, 100, '--', '100 % referencia', 'LabelHorizontalAlignment', 'left');
    set(ax3, 'XTick', pctX, 'XTickLabel', pctNames);
    ylabel(ax3, 'Arány [%]');
    title(ax3, 'NoBESS-hez viszonyított import és energiaút-hatásfokok');
    legend(ax3, labels, 'Location', 'best');
    ylim(ax3, [0, max(110, 1.15 * max(pctData(:), [], 'omitnan'))]);

    % ------------------------------------------------------------------
    % 4) Financial interpretation of savings and tracked loss values
    % ------------------------------------------------------------------
    ax4 = nexttile;
    hold(ax4, 'on'); grid(ax4, 'on'); box(ax4, 'on');

    costNames = { ...
        sprintf('Villamosenergia-\nköltségmegtakarítás'), ...
        sprintf('Grid -> BESS\nveszteség értéke'), ...
        sprintf('BESS -> fogyasztó\nveszteség értéke'), ...
        sprintf('Követett veszteségek\nösszesen'), ...
        sprintf('Megtakarítás a követett\nveszteségérték után')};

    costX = 1:numel(costNames);
    costDataMillionHUF = [ ...
        M.energyCostSaving_HUF, ...
        M.gridToBessChargeLossValue_HUF, ...
        M.bessDischargePathLossValue_HUF, ...
        M.totalTrackedLossValue_HUF, ...
        M.savingAfterTrackedLossValue_HUF] ./ 1e6;

    bar(ax4, costX, costDataMillionHUF.', 'grouped');
    for r = 1:height(M)
        plot(ax4, costX, costDataMillionHUF(r, :), '-o', 'LineWidth', 1.6, ...
            'MarkerSize', 6, 'DisplayName', labels{r});
    end
    yline(ax4, 0, 'k-');
    set(ax4, 'XTick', costX, 'XTickLabel', costNames);
    ylabel(ax4, 'Érték [millió HUF / teljes időszak]');
    title(ax4, 'Megtakarítások és veszteségek importáras értelmezése');
    legend(ax4, labels, 'Location', 'best');

    sgtitle(fig, sprintf('AC/DC teljes időszakos diagnosztikai összehasonlítás | candidate %06d', candidateIndex));
end


function tf = local_is_baseline_candidate(T, rowIdx)

    tf = false;

    if ismember('BESS_PV_ratio', T.Properties.VariableNames)
        tf = abs(T.BESS_PV_ratio(rowIdx)) < 1e-12;
    elseif ismember('E_BESS_kWh', T.Properties.VariableNames)
        tf = T.E_BESS_kWh(rowIdx) <= 0;
    end
end


function value = local_first_existing_metric(T, rowIdx, names)

    value = NaN;

    for i = 1:numel(names)
        value = local_metric(T, rowIdx, names{i});
        if isfinite(value)
            return;
        end
    end
end


function value = local_metric(T, rowIdx, name)

    if ismember(name, T.Properties.VariableNames)
        value = T.(name)(rowIdx);
    else
        value = NaN;
    end

    if isempty(value)
        value = NaN;
    end

    if iscell(value)
        value = value{1};
    end

    if isstring(value) || ischar(value)
        value = str2double(value);
    end

    if ~isnumeric(value) || ~isscalar(value)
        value = NaN;
    end
end


function y = local_safe_divide(a, b)

    if isempty(a) || isempty(b) || isnan(a) || isnan(b) || abs(b) < 1e-12
        y = NaN;
    else
        y = a ./ b;
    end
end


function s = local_sum_finite(x)

    x = x(:);
    x = x(isfinite(x));

    if isempty(x)
        s = 0;
    else
        s = sum(x);
    end
end


function local_add_value_labels(ax, x, data, fmt)

    if isempty(data)
        return;
    end

    [nRows, nCols] = size(data);
    if nRows == 0 || nCols == 0
        return;
    end

    groupWidth = min(0.8, nRows / (nRows + 1.5));

    for r = 1:nRows
        for c = 1:nCols
            if ~isfinite(data(r, c)) || data(r, c) == 0
                continue;
            end

            xPos = x(c) - groupWidth/2 + (2*r-1) * groupWidth / (2*nRows);
            text(ax, xPos, data(r, c), sprintf(fmt, data(r, c)), ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'bottom', ...
                'FontSize', 8);
        end
    end
end


function local_safe_save_figure(fig, fileBase)

    if isempty(fig) || ~isgraphics(fig, 'figure')
        return;
    end

    try
        savefig(fig, [fileBase, '.fig']);
    catch ME
        warning('Could not save FIG file: %s.fig\nReason: %s', fileBase, ME.message);
    end

    if ~isgraphics(fig, 'figure')
        return;
    end

    try
        exportgraphics(fig, [fileBase, '.png'], 'Resolution', 150);
    catch ME_export
        warning('exportgraphics failed for %s.png\nReason: %s', fileBase, ME_export.message);

        if isgraphics(fig, 'figure')
            try
                saveas(fig, [fileBase, '.png']);
            catch ME_saveas
                warning('saveas fallback failed for %s.png\nReason: %s', fileBase, ME_saveas.message);
            end
        end
    end
end
