function out = plot_ac_dc_diagnostic_comparison(runResult, cfgBase, objectiveMode, candidateList)
% PLOT_AC_DC_DIAGNOSTIC_COMPARISON
%
% Teljes szimulalt idoszakra vonatkozo AC/DC diagnosztikai abracsomag.
% A fuggveny a DB.candidateTable-ben mentett, topologia-szintu kanonikus
% metrikakbol dolgozik, ezert nem futtat uj szimulaciot es nem hasznal
% final_day idosorokat.
%
% Kimeneti abrak:
%   1) grid -> BESS toltesi es BESS -> load kisutesi hatasfokok
%   2) ekvivalens ciklusszam, final SoH es koltsegmerleg
%   3) vesztesegkomponensek abszolut es szazalekos bontasban

    out = struct();
    out.outputFolder = "";
    out.figureFiles = strings(0, 1);
    out.tableFiles = strings(0, 1);

    objectiveMode = lower(string(objectiveMode));

    Tdc = local_get_metric_table(runResult, cfgBase, objectiveMode, "dc");
    Tac = local_get_metric_table(runResult, cfgBase, objectiveMode, "ac");

    if nargin < 4 || isempty(candidateList)
        candidateList = 1:min(height(Tdc), height(Tac));
    end

    candidateList = unique(candidateList(:).', 'stable');
    candidateList = candidateList(candidateList >= 1 & candidateList <= height(Tdc) & candidateList <= height(Tac));

    if isempty(candidateList)
        fprintf('AC/DC diagnostic comparison skipped: no valid candidate index.\n');
        return;
    end

    outFolder = fullfile( ...
        cfgBase.paths.results, ...
        char(objectiveMode), ...
        'diagnostics', ...
        'ac_dc_comparison');

    if ~exist(outFolder, 'dir')
        mkdir(outFolder);
    end

    out.outputFolder = string(outFolder);

    metricRows = repmat(local_empty_metric_struct(), 0, 1);

    for ii = 1:numel(candidateList)

        candidateIndex = candidateList(ii);

        if local_is_baseline_candidate(Tdc, candidateIndex)
            continue;
        end

        metricRows(end+1, 1) = local_collect_metrics(Tdc, candidateIndex, "DC"); %#ok<AGROW>
        metricRows(end+1, 1) = local_collect_metrics(Tac, candidateIndex, "AC"); %#ok<AGROW>
    end

    if isempty(metricRows)
        fprintf('AC/DC diagnostic comparison skipped: only baseline candidates were selected.\n');
        return;
    end

    metricTable = struct2table(metricRows);

    selectedCandidateText = local_candidate_file_suffix(unique(metricTable.candidateIndex));
    tableFile = fullfile(outFolder, sprintf('ac_dc_diagnostic_comparison_%s.csv', selectedCandidateText));
    writetable(metricTable, tableFile);
    out.tableFiles(end+1, 1) = string(tableFile);

    fig1 = local_plot_efficiency_chain(metricTable);
    fileBase1 = fullfile(outFolder, sprintf('ac_dc_01_bess_energy_path_efficiency_%s', selectedCandidateText));
    local_safe_save_figure(fig1, fileBase1);
    out.figureFiles(end+1, 1) = string([fileBase1, '.png']);

    fig2 = local_plot_technical_and_cost_summary(metricTable);
    fileBase2 = fullfile(outFolder, sprintf('ac_dc_02_cycles_soh_cost_balance_%s', selectedCandidateText));
    local_safe_save_figure(fig2, fileBase2);
    out.figureFiles(end+1, 1) = string([fileBase2, '.png']);

    fig3 = local_plot_loss_components(metricTable);
    fileBase3 = fullfile(outFolder, sprintf('ac_dc_03_loss_components_%s', selectedCandidateText));
    local_safe_save_figure(fig3, fileBase3);
    out.figureFiles(end+1, 1) = string([fileBase3, '.png']);

    fprintf('AC/DC diagnostic comparison saved for full simulated period:\n%s\n', outFolder);
end


function M = local_collect_metrics(T, rowIdx, coupling)

    M = local_empty_metric_struct();

    M.coupling = string(coupling);
    M.candidateIndex = rowIdx;
    M.candidateLabel = string(local_candidate_label(T, rowIdx));

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

    M.bessCharge_kWh = local_metric(T, rowIdx, 'bessCharge_kWh');
    M.bessDischarge_kWh = local_metric(T, rowIdx, 'bessDischarge_kWh');
    M.bessThroughput_kWh = local_metric(T, rowIdx, 'bessThroughput_kWh');
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
    M.overall_gridToBess_to_load_eff_pct = ...
        M.gridToBess_charge_eff_pct .* M.bessDischarge_to_load_eff_pct ./ 100;

    M.equivalentCycles = local_first_existing_metric(T, rowIdx, { ...
        'equivalentCycles', ...
        'equivalentCycleCount', ...
        'bessEquivalentCycles'});

    if ~isfinite(M.equivalentCycles)
        M.equivalentCycles = local_safe_divide(M.bessThroughput_kWh, 2 * M.E_BESS_kWh);
    end

    if ~isfinite(M.equivalentCycles)
        M.equivalentCycles = 0;
    end

    M.finalSoH_pct = local_first_existing_metric(T, rowIdx, { ...
        'finalSoH', ...
        'SOH_end', ...
        'SoH_final', ...
        'finalSOH'});

    if isfinite(M.finalSoH_pct) && M.finalSoH_pct <= 1.5
        M.finalSoH_pct = 100 * M.finalSoH_pct;
    end

    M.energyCostNoBess_HUF = local_metric(T, rowIdx, 'energyCostNoBess_HUF');
    M.energyCost_HUF = local_metric(T, rowIdx, 'energyCost_HUF');
    M.energyCostSaving_HUF = M.energyCostNoBess_HUF - M.energyCost_HUF;

    M.degradationCost_HUF = local_zero_if_nan(local_metric(T, rowIdx, 'degradationCost_HUF'));
    M.overrunCost_HUF = local_zero_if_nan(local_metric(T, rowIdx, 'overrunCost_HUF'));
    M.contractCost_HUF = local_zero_if_nan(local_metric(T, rowIdx, 'contractCost_HUF'));

    M.costBalance_HUF = ...
        local_zero_if_nan(M.energyCostSaving_HUF) - ...
        M.degradationCost_HUF - ...
        M.overrunCost_HUF - ...
        M.contractCost_HUF;

    M.gridToBessImportCost_HUF = local_metric(T, rowIdx, 'gridToBessImportCost_HUF');
    M.gridToBessStoredImportEquivCost_HUF = local_metric(T, rowIdx, 'gridToBessStoredImportEquivCost_HUF');
    M.bessDischargeBeforeConversionImportEquivCost_HUF = local_metric(T, rowIdx, 'bessDischargeBeforeConversionImportEquivCost_HUF');
    M.bessToLoadImportEquivCost_HUF = local_metric(T, rowIdx, 'bessToLoadImportEquivCost_HUF');

    M.gridToBessChargeLossValue_HUF = ...
        M.gridToBessImportCost_HUF - M.gridToBessStoredImportEquivCost_HUF;

    M.bessDischargePathLossValue_HUF = ...
        M.bessDischargeBeforeConversionImportEquivCost_HUF - M.bessToLoadImportEquivCost_HUF;
end


function fig = local_plot_efficiency_chain(M)

    P = local_prepare_plot_data(M);

    fig = figure( ...
        'Name', 'AC/DC BESS energy path efficiency comparison', ...
        'Position', [60, 40, 1650, 1120]);

    tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    % ------------------------------------------------------------------
    % 1) Grid -> BESS charge path
    % ------------------------------------------------------------------
    ax1 = nexttile;
    hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');

    dcStored = P.dc.gridToBessStored_kWh ./ 1000;
    acStored = P.ac.gridToBessStored_kWh ./ 1000;
    dcLoss = max(P.dc.gridToBess_kWh - P.dc.gridToBessStored_kWh, 0) ./ 1000;
    acLoss = max(P.ac.gridToBess_kWh - P.ac.gridToBessStored_kWh, 0) ./ 1000;

    yyaxis(ax1, 'left');
    bDC = bar(ax1, P.xDC, [dcStored, dcLoss], P.barWidth, 'stacked');
    bAC = bar(ax1, P.xAC, [acStored, acLoss], P.barWidth, 'stacked');
    ylabel(ax1, 'Energia [MWh / teljes időszak]');

    yyaxis(ax1, 'right');
    pDC = local_plot_curve(ax1, P.xDC, P.dc.gridToBess_charge_eff_pct, '-o', 'DC töltési hatásfok');
    pAC = local_plot_curve(ax1, P.xAC, P.ac.gridToBess_charge_eff_pct, '-s', 'AC töltési hatásfok');
    ylabel(ax1, 'Hatásfok [%]');
    local_set_pct_ylim(ax1, [P.dc.gridToBess_charge_eff_pct; P.ac.gridToBess_charge_eff_pct]);

    title(ax1, 'Grid -> BESS töltés: importált energia, eltárolt energia és töltési hatásfok');
    local_format_candidate_axis(ax1, P);
    local_add_topology_tags(ax1, P);
    legend(ax1, [bDC(1), bDC(2), pDC, pAC], { ...
        'Ténylegesen eltárolt energia', ...
        'Töltési veszteség', ...
        'DC hatásfok', ...
        'AC hatásfok'}, ...
        'Location', 'bestoutside');
    local_annotate_efficiency(ax1, P.xDC, P.dc.gridToBess_charge_eff_pct, '%.1f %%');
    local_annotate_efficiency(ax1, P.xAC, P.ac.gridToBess_charge_eff_pct, '%.1f %%');

    % ------------------------------------------------------------------
    % 2) BESS discharge path
    % ------------------------------------------------------------------
    ax2 = nexttile;
    hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');

    dcUseful = P.dc.bessToLoad_kWh ./ 1000;
    acUseful = P.ac.bessToLoad_kWh ./ 1000;
    dcDisLoss = max(P.dc.bessDischargeBeforeConversion_kWh - P.dc.bessToLoad_kWh, 0) ./ 1000;
    acDisLoss = max(P.ac.bessDischargeBeforeConversion_kWh - P.ac.bessToLoad_kWh, 0) ./ 1000;

    yyaxis(ax2, 'left');
    bDC = bar(ax2, P.xDC, [dcUseful, dcDisLoss], P.barWidth, 'stacked');
    bAC = bar(ax2, P.xAC, [acUseful, acDisLoss], P.barWidth, 'stacked');
    ylabel(ax2, 'Energia [MWh / teljes időszak]');

    yyaxis(ax2, 'right');
    pDC = local_plot_curve(ax2, P.xDC, P.dc.bessDischarge_to_load_eff_pct, '-o', 'DC kisütési hatásfok');
    pAC = local_plot_curve(ax2, P.xAC, P.ac.bessDischarge_to_load_eff_pct, '-s', 'AC kisütési hatásfok');
    ylabel(ax2, 'Hatásfok [%]');
    local_set_pct_ylim(ax2, [P.dc.bessDischarge_to_load_eff_pct; P.ac.bessDischarge_to_load_eff_pct]);

    title(ax2, 'BESS kisütés: konverzió előtti energia, fogyasztóra jutó energia és kisütési hatásfok');
    local_format_candidate_axis(ax2, P);
    local_add_topology_tags(ax2, P);
    legend(ax2, [bDC(1), bDC(2), pDC, pAC], { ...
        'Fogyasztóra jutó BESS energia', ...
        'Kisütési út vesztesége', ...
        'DC hatásfok', ...
        'AC hatásfok'}, ...
        'Location', 'bestoutside');
    local_annotate_efficiency(ax2, P.xDC, P.dc.bessDischarge_to_load_eff_pct, '%.1f %%');
    local_annotate_efficiency(ax2, P.xAC, P.ac.bessDischarge_to_load_eff_pct, '%.1f %%');

    % ------------------------------------------------------------------
    % 3) Overall efficiency
    % ------------------------------------------------------------------
    ax3 = nexttile;
    hold(ax3, 'on'); grid(ax3, 'on'); box(ax3, 'on');

    bar(ax3, P.xDC, P.dc.overall_gridToBess_to_load_eff_pct, P.barWidth);
    bar(ax3, P.xAC, P.ac.overall_gridToBess_to_load_eff_pct, P.barWidth);
    local_plot_curve(ax3, P.xDC, P.dc.overall_gridToBess_to_load_eff_pct, '-o', 'DC összesített hatásfok');
    local_plot_curve(ax3, P.xAC, P.ac.overall_gridToBess_to_load_eff_pct, '-s', 'AC összesített hatásfok');
    yline(ax3, 100, '--', '100 % referencia', 'LabelHorizontalAlignment', 'left');
    ylabel(ax3, 'Összesített hatásfok [%]');
    title(ax3, 'Összesített energiaút-hatásfok: töltési hatásfok × kisütési hatásfok');
    local_format_candidate_axis(ax3, P);
    local_add_topology_tags(ax3, P);
    legend(ax3, {'DC', 'AC', 'DC görbe', 'AC görbe'}, 'Location', 'bestoutside');
    local_set_pct_ylim(ax3, [P.dc.overall_gridToBess_to_load_eff_pct; P.ac.overall_gridToBess_to_load_eff_pct]);

    sgtitle(fig, 'AC/DC BESS energiaút-hatásfokok a teljes szimulált időszakra');
end


function fig = local_plot_technical_and_cost_summary(M)

    P = local_prepare_plot_data(M);

    fig = figure( ...
        'Name', 'AC/DC cycles SoH and cost balance comparison', ...
        'Position', [70, 45, 1650, 1120]);

    tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    % ------------------------------------------------------------------
    % 1) Equivalent cycles
    % ------------------------------------------------------------------
    ax1 = nexttile;
    hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');
    bar(ax1, P.xDC, P.dc.equivalentCycles, P.barWidth);
    bar(ax1, P.xAC, P.ac.equivalentCycles, P.barWidth);
    local_plot_curve(ax1, P.xDC, P.dc.equivalentCycles, '-o', 'DC');
    local_plot_curve(ax1, P.xAC, P.ac.equivalentCycles, '-s', 'AC');
    ylabel(ax1, 'Ekvivalens ciklusszám [-]');
    title(ax1, 'BESS évesített/összesített ekvivalens ciklusszám');
    local_format_candidate_axis(ax1, P);
    local_add_topology_tags(ax1, P);
    legend(ax1, {'DC', 'AC', 'DC görbe', 'AC görbe'}, 'Location', 'bestoutside');

    % ------------------------------------------------------------------
    % 2) Final SoH
    % ------------------------------------------------------------------
    ax2 = nexttile;
    hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');
    bar(ax2, P.xDC, P.dc.finalSoH_pct, P.barWidth);
    bar(ax2, P.xAC, P.ac.finalSoH_pct, P.barWidth);
    local_plot_curve(ax2, P.xDC, P.dc.finalSoH_pct, '-o', 'DC');
    local_plot_curve(ax2, P.xAC, P.ac.finalSoH_pct, '-s', 'AC');
    ylabel(ax2, 'Végső SoH [%]');
    title(ax2, 'Akkumulátor végső egészségi állapota a szimuláció végén');
    local_format_candidate_axis(ax2, P);
    local_add_topology_tags(ax2, P);
    legend(ax2, {'DC', 'AC', 'DC görbe', 'AC görbe'}, 'Location', 'bestoutside');

    % ------------------------------------------------------------------
    % 3) Cost differences and balance
    % ------------------------------------------------------------------
    ax3 = nexttile;
    hold(ax3, 'on'); grid(ax3, 'on'); box(ax3, 'on');

    dcCosts = [ ...
        P.dc.energyCostSaving_HUF, ...
        -P.dc.degradationCost_HUF, ...
        -P.dc.overrunCost_HUF, ...
        -P.dc.contractCost_HUF] ./ 1e6;

    acCosts = [ ...
        P.ac.energyCostSaving_HUF, ...
        -P.ac.degradationCost_HUF, ...
        -P.ac.overrunCost_HUF, ...
        -P.ac.contractCost_HUF] ./ 1e6;

    bDC = bar(ax3, P.xDC, dcCosts, P.barWidth, 'stacked');
    bAC = bar(ax3, P.xAC, acCosts, P.barWidth, 'stacked');
    pDC = local_plot_curve(ax3, P.xDC, P.dc.costBalance_HUF ./ 1e6, '-o', 'DC költségmérleg');
    pAC = local_plot_curve(ax3, P.xAC, P.ac.costBalance_HUF ./ 1e6, '-s', 'AC költségmérleg');
    yline(ax3, 0, 'k-');
    ylabel(ax3, 'Költségkülönbség [millió HUF / teljes időszak]');
    title(ax3, 'NoBESS-hez viszonyított költségkülönbségek és teljes költségmérleg');
    local_format_candidate_axis(ax3, P);
    local_add_topology_tags(ax3, P);
    legend(ax3, [bDC(1), bDC(2), bDC(3), bDC(4), pDC, pAC], { ...
        'Villamosenergia-költség megtakarítás', ...
        'BESS degradációs költség', ...
        'Túllépési költség', ...
        'Szerződött teljesítmény költség', ...
        'DC költségmérleg', ...
        'AC költségmérleg'}, ...
        'Location', 'bestoutside');

    sgtitle(fig, 'AC/DC technikai és pénzügyi összefoglaló a teljes szimulált időszakra');
end

function M = local_empty_metric_struct()

    M = struct();
    M.coupling = "";
    M.candidateIndex = NaN;
    M.candidateLabel = "";

    numericFields = { ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'E_BESS_kWh', ...
        'BESS_PV_ratio', ...
        'gridImportNoBess_kWh', ...
        'gridImport_kWh', ...
        'gridToLoad_kWh', ...
        'gridToBess_kWh', ...
        'gridToBessStored_kWh', ...
        'pvToBess_kWh', ...
        'pvToBessStored_kWh', ...
        'bessCharge_kWh', ...
        'bessDischarge_kWh', ...
        'bessThroughput_kWh', ...
        'bessDischargeBeforeConversion_kWh', ...
        'bessToLoad_kWh', ...
        'gridToBessLoss_kWh', ...
        'pvToBessLoss_kWh', ...
        'bessToLoadConversionLoss_kWh', ...
        'centralInverterLoss_kWh', ...
        'dcdcLoss_kWh', ...
        'pcsbInverterLoss_kWh', ...
        'bessInternalLoss_kWh', ...
        'totalConverterLoss_kWh', ...
        'trackedPathConverterLoss_kWh', ...
        'otherConverterLoss_kWh', ...
        'gridImportReduction_kWh', ...
        'gridImport_pct_of_noBess', ...
        'gridImportReduction_pct', ...
        'gridToBess_pct_of_noBess', ...
        'gridToBess_charge_eff_pct', ...
        'bessDischarge_to_load_eff_pct', ...
        'overall_gridToBess_to_load_eff_pct', ...
        'equivalentCycles', ...
        'finalSoH_pct', ...
        'energyCostNoBess_HUF', ...
        'energyCost_HUF', ...
        'energyCostSaving_HUF', ...
        'degradationCost_HUF', ...
        'overrunCost_HUF', ...
        'contractCost_HUF', ...
        'costBalance_HUF', ...
        'gridToBessImportCost_HUF', ...
        'gridToBessStoredImportEquivCost_HUF', ...
        'bessDischargeBeforeConversionImportEquivCost_HUF', ...
        'bessToLoadImportEquivCost_HUF', ...
        'gridToBessChargeLossValue_HUF', ...
        'bessDischargePathLossValue_HUF'};

    for i = 1:numel(numericFields)
        M.(numericFields{i}) = NaN;
    end
end


function fig = local_plot_loss_components(M)

    P = local_prepare_plot_data(M);

    fig = figure( ...
        'Name', 'AC/DC loss components comparison', ...
        'Position', [80, 50, 1650, 900]);

    tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    lossNames = { ...
        'Grid -> BESS konverziós veszteség', ...
        'PV -> BESS konverziós veszteség', ...
        'BESS -> fogyasztó konverziós veszteség', ...
        'Egyéb konverziós veszteség', ...
        'BESS belső veszteség'};

    dcLossMWh = [ ...
        P.dc.gridToBessLoss_kWh, ...
        P.dc.pvToBessLoss_kWh, ...
        P.dc.bessToLoadConversionLoss_kWh, ...
        P.dc.otherConverterLoss_kWh, ...
        P.dc.bessInternalLoss_kWh] ./ 1000;

    acLossMWh = [ ...
        P.ac.gridToBessLoss_kWh, ...
        P.ac.pvToBessLoss_kWh, ...
        P.ac.bessToLoadConversionLoss_kWh, ...
        P.ac.otherConverterLoss_kWh, ...
        P.ac.bessInternalLoss_kWh] ./ 1000;

    ax1 = nexttile;
    hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');
    bDC = bar(ax1, P.xDC, dcLossMWh, P.barWidth, 'stacked');
    bar(ax1, P.xAC, acLossMWh, P.barWidth, 'stacked');
    ylabel(ax1, 'Veszteség [MWh / teljes időszak]');
    title(ax1, 'Veszteségkomponensek abszolút értékben');
    local_format_candidate_axis(ax1, P);
    local_add_topology_tags(ax1, P);
    legend(ax1, bDC, lossNames, 'Location', 'bestoutside');

    dcTotal = sum(dcLossMWh, 2);
    acTotal = sum(acLossMWh, 2);
    dcLossPct = 100 * dcLossMWh ./ max(dcTotal, eps);
    acLossPct = 100 * acLossMWh ./ max(acTotal, eps);
    dcLossPct(dcTotal <= 1e-12, :) = 0;
    acLossPct(acTotal <= 1e-12, :) = 0;

    ax2 = nexttile;
    hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');
    bDC = bar(ax2, P.xDC, dcLossPct, P.barWidth, 'stacked');
    bar(ax2, P.xAC, acLossPct, P.barWidth, 'stacked');
    ylabel(ax2, 'Részarány [%]');
    title(ax2, 'Veszteségkomponensek aránya a teljes veszteségen belül');
    local_format_candidate_axis(ax2, P);
    local_add_topology_tags(ax2, P);
    ylim(ax2, [0 100]);
    legend(ax2, bDC, lossNames, 'Location', 'bestoutside');

    sgtitle(fig, 'AC/DC veszteségkomponensek a teljes szimulált időszakra');
end


function P = local_prepare_plot_data(M)

    P = struct();
    P.candidates = unique(M.candidateIndex(:).', 'stable');
    P.n = numel(P.candidates);
    P.xBase = 1:P.n;
    P.barWidth = 0.34;
    P.xDC = P.xBase - 0.19;
    P.xAC = P.xBase + 0.19;
    P.labels = strings(P.n, 1);

    fields = M.Properties.VariableNames;

    for i = 1:P.n
        row = find(M.candidateIndex == P.candidates(i), 1, 'first');
        if isempty(row)
            P.labels(i) = sprintf('C%d', P.candidates(i));
        else
            P.labels(i) = string(M.candidateLabel(row));
        end
    end

    P.dc = struct();
    P.ac = struct();

    for k = 1:numel(fields)
        f = fields{k};

        if strcmp(f, 'coupling') || strcmp(f, 'candidateLabel')
            continue;
        end

        P.dc.(f) = local_series(M, P.candidates, "DC", f);
        P.ac.(f) = local_series(M, P.candidates, "AC", f);
    end
end


function v = local_series(M, candidates, coupling, fieldName)

    v = NaN(numel(candidates), 1);

    if ~ismember(fieldName, M.Properties.VariableNames)
        return;
    end

    for i = 1:numel(candidates)
        idx = find(M.candidateIndex == candidates(i) & string(M.coupling) == string(coupling), 1, 'first');
        if isempty(idx)
            continue;
        end

        value = M.(fieldName)(idx);
        if isnumeric(value) && isscalar(value)
            v(i) = value;
        end
    end
end


function local_format_candidate_axis(ax, P)

    set(ax, 'XTick', P.xBase, 'XTickLabel', cellstr(P.labels));
    xtickangle(ax, 25);

    if P.n == 1
        xlim(ax, [0, 1.55]);
    else
        xlim(ax, [0.5, P.n + 0.5]);
    end
end


function local_add_topology_tags(ax, P)

    yl = ylim(ax);
    yText = yl(1) - 0.07 * max(diff(yl), eps);

    for i = 1:P.n
        text(ax, P.xDC(i), yText, 'DC', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top', ...
            'FontSize', 8);
        text(ax, P.xAC(i), yText, 'AC', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top', ...
            'FontSize', 8);
    end
end


function p = local_plot_curve(ax, x, y, lineSpec, displayName)

    x = x(:).';
    y = y(:).';

    if numel(x) == 1
        p = plot(ax, [0, x], [0, y], lineSpec, ...
            'LineWidth', 1.6, ...
            'MarkerSize', 6, ...
            'DisplayName', displayName);
    else
        p = plot(ax, x, y, lineSpec, ...
            'LineWidth', 1.6, ...
            'MarkerSize', 6, ...
            'DisplayName', displayName);
    end
end


function local_set_pct_ylim(ax, values)

    values = values(isfinite(values));

    if isempty(values)
        ylim(ax, [0 100]);
        return;
    end

    ymax = max(110, 1.15 * max(values));
    ylim(ax, [0 ymax]);
end


function local_annotate_efficiency(ax, x, effPct, fmt)

    yl = ylim(ax);
    y = yl(2) - 0.08 * max(diff(yl), eps);

    for i = 1:numel(x)
        if ~isfinite(effPct(i))
            continue;
        end
        text(ax, x(i), y, sprintf(fmt, effPct(i)), ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top', ...
            'FontSize', 8, ...
            'FontWeight', 'bold');
    end
end


function tf = local_is_baseline_candidate(T, rowIdx)

    tf = false;

    if ismember('BESS_PV_ratio', T.Properties.VariableNames)
        tf = abs(T.BESS_PV_ratio(rowIdx)) < 1e-12;
    elseif ismember('E_BESS_kWh', T.Properties.VariableNames)
        tf = T.E_BESS_kWh(rowIdx) <= 0;
    end
end


function label = local_candidate_label(T, rowIdx)

    pv = local_metric(T, rowIdx, 'P_PV_kW');
    bess = local_metric(T, rowIdx, 'E_BESS_kWh');
    ratio = local_metric(T, rowIdx, 'BESS_PV_ratio');

    if isfinite(pv) && isfinite(bess)
        label = sprintf('C%d | PV %.0f kWp | BESS %.0f kWh', rowIdx, pv, bess);
    elseif isfinite(ratio)
        label = sprintf('C%d | BESS/PV %.2f', rowIdx, ratio);
    else
        label = sprintf('C%d', rowIdx);
    end
end


function suffix = local_candidate_file_suffix(candidateIndices)

    candidateIndices = unique(candidateIndices(:).', 'stable');

    if numel(candidateIndices) == 1
        suffix = sprintf('candidate_%06d', candidateIndices(1));
    else
        suffix = sprintf('candidates_%06d_to_%06d_n%d', ...
            min(candidateIndices), max(candidateIndices), numel(candidateIndices));
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


function y = local_zero_if_nan(x)

    if isempty(x) || ~isfinite(x)
        y = 0;
    else
        y = x;
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

function T = local_get_metric_table(runResult, cfgBase, objectiveMode, coupling)

    coupling = lower(string(coupling));

    if isfield(runResult, char(coupling)) && ...
       isfield(runResult.(char(coupling)), 'candidateMetrics')

        T = runResult.(char(coupling)).candidateMetrics;
        return;
    end

    if isfield(runResult, char(coupling)) && ...
       isfield(runResult.(char(coupling)), 'DB') && ...
       isfield(runResult.(char(coupling)).DB, 'candidateTable')

        % Fallback: ha még nincs cache, akkor a memóriában lévő DB-ből
        % dolgozunk. Ez főleg átmeneti kompatibilitás miatt kell.
        T = runResult.(char(coupling)).DB.candidateTable;
        return;
    end

    % Utolsó fallback: próbáljuk meg fájlból betölteni a cache-t.
    T = load_canonical_candidate_metrics( ...
        cfgBase, ...
        objectiveMode, ...
        coupling);
end
