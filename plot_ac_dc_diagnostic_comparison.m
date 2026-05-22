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

    fig = figure( ...
        'Name', sprintf('AC/DC full-period diagnostic comparison - candidate %06d', candidateIndex), ...
        'Position', [80, 60, 1550, 1050]);

    tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    % ------------------------------------------------------------------
    % 1) Grid -> BESS -> stored -> discharge -> load chain
    % ------------------------------------------------------------------
    ax1 = nexttile;
    hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');

    chainData = [ ...
        M.gridToBess_kWh, ...
        M.gridToBessStored_kWh, ...
        M.bessDischargeBeforeConversion_kWh, ...
        M.bessToLoad_kWh];

    bar(ax1, chainData.');
    set(ax1, 'XTickLabel', { ...
        'Grid -> BESS\nkonv. előtt', ...
        'Grid eredetű\neltárolt', ...
        'BESS kisütés\nkonv. előtt', ...
        'BESS -> load\nhasznosult'});
    ylabel(ax1, 'Energia [kWh / teljes időszak]');
    title(ax1, 'Grid -> BESS lánc és load oldali hasznosulás');
    legend(ax1, labels, 'Location', 'best');

    % ------------------------------------------------------------------
    % 2) Conversion/storage losses
    % ------------------------------------------------------------------
    ax2 = nexttile;
    hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');

    lossData = [ ...
        M.gridToBessLoss_kWh, ...
        M.pvToBessLoss_kWh, ...
        M.bessToLoadConversionLoss_kWh, ...
        M.otherConverterLoss_kWh, ...
        M.bessInternalLoss_kWh];

    bar(ax2, lossData, 'stacked');
    set(ax2, 'XTickLabel', labels);
    ylabel(ax2, 'Energia [kWh / teljes időszak]');
    title(ax2, 'Konverziós és BESS belső veszteségek');
    legend(ax2, { ...
        'Grid -> BESS konv. veszteség', ...
        'PV -> BESS konv. veszteség', ...
        'BESS -> load konv. veszteség', ...
        'Egyéb konv. veszteség', ...
        'BESS belső veszteség'}, ...
        'Location', 'bestoutside');

    % ------------------------------------------------------------------
    % 3) Grid import and utilization ratios
    % ------------------------------------------------------------------
    ax3 = nexttile;
    hold(ax3, 'on'); grid(ax3, 'on'); box(ax3, 'on');

    pctData = [ ...
        M.gridImport_pct_of_noBess, ...
        M.gridImportReduction_pct, ...
        M.gridToBess_pct_of_noBess, ...
        M.gridToBess_charge_eff_pct, ...
        M.bessDischarge_to_load_eff_pct, ...
        M.gridToBess_to_bessLoad_ratio_pct];

    bar(ax3, pctData.');
    set(ax3, 'XTickLabel', { ...
        'Grid import /\nNoBESS', ...
        'Grid import\ncsökkenés', ...
        'Grid -> BESS /\nNoBESS', ...
        'Grid -> BESS\ntöltési hatás', ...
        'BESS kisütés ->\nload hatás', ...
        'BESS -> load /\nGrid -> BESS'});
    ylabel(ax3, 'Arány [%]');
    title(ax3, 'Import és energiaút-hasznosulási arányok');
    legend(ax3, labels, 'Location', 'best');

    % ------------------------------------------------------------------
    % 4) Savings and tracked loss values
    % ------------------------------------------------------------------
    ax4 = nexttile;
    hold(ax4, 'on'); grid(ax4, 'on'); box(ax4, 'on');

    costData = [ ...
        M.energyCostSaving_HUF, ...
        M.gridToBessChargeLossValue_HUF, ...
        M.bessDischargePathLossValue_HUF, ...
        M.totalTrackedLossValue_HUF, ...
        M.savingAfterTrackedLossValue_HUF] ./ 1e6;

    bar(ax4, costData.');
    set(ax4, 'XTickLabel', { ...
        'Energia-\nköltségmegtakarítás', ...
        'Grid -> BESS\nveszt. értéke', ...
        'BESS -> load\nveszt. értéke', ...
        'Követett\nveszt. összesen', ...
        'Megtakarítás -\nkövetett veszt.'});
    ylabel(ax4, 'Millió HUF / teljes időszak');
    title(ax4, 'Megtakarítások és veszteségek importáras értéke');
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
