function compareResult = compare_ac_dc_results_for_mode(cfgBase, objectiveMode)
% COMPARE_AC_DC_RESULTS_FOR_MODE
%
% Teljes sweep utan osszehasonlitja az AC es DC eredmenyeket ugyanarra a
% mukodesi modra.
%
% Dolgozati kiertekeleshez keszitett kimenetek:
%   - noBESS + legjobb DC + legjobb AC osszefoglalo tabla
%   - mukodesi mod szerinti sweep abrak
%   - koltsegkomponens abra
%   - energiaaramlas / BESS-hasznalat abra
%
% Fontos BESS gazdasagi logika:
%   Az eves BESS CAPEX+OPEX koltseg definicioja:
%       C_BESS_year = deltaSoH_year / 0.2 * CAPEX_BESS + OPEX_BESS
%
%   Mivel a candidateTable jelenleg a teljes szimulacio vegso SoH erteket
%   tartalmazza, az eves deltaSoH-t ekvivalens eves romlaskent szamitjuk:
%       deltaSoH_year_eq = (1 - finalSoH) / simYears
%
%   Igy a teljes szimulacios idoszakra:
%       C_BESS_total = (1 - finalSoH) / 0.2 * CAPEX_BESS
%                    + simYears * OPEX_BESS

    objectiveMode = lower(string(objectiveMode));

    allowedModes = ["peak_only", "energy_only", "combined"];

    if ~any(objectiveMode == allowedModes)
        error('Invalid objectiveMode: %s', objectiveMode);
    end

    resultRoot = fullfile(cfgBase.paths.results, char(objectiveMode));

    dcPath = fullfile(resultRoot, sprintf('results_dc_%s.mat', objectiveMode));
    acPath = fullfile(resultRoot, sprintf('results_ac_%s.mat', objectiveMode));

    if ~isfile(dcPath)
        error('Missing DC result file: %s', dcPath);
    end

    if ~isfile(acPath)
        error('Missing AC result file: %s', acPath);
    end

    Tdc = local_load_candidate_table(dcPath, "dc");
    Tac = local_load_candidate_table(acPath, "ac");

    tableAll = [Tdc; Tac];
    tableAll = local_add_thesis_economic_columns(tableAll, cfgBase);

    noBessRow = local_select_no_bess_row(tableAll);
    tableAll = local_add_no_bess_comparison_columns(tableAll, noBessRow, cfgBase);

    local_require_columns(tableAll, { ...
        'wasSimulated', ...
        'hasError', ...
        'coupling', ...
        'BESS_PV_ratio', ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'bestContract_kW', ...
        'objectiveCost_HUF', ...
        'energyCost_HUF', ...
        'contractCost_HUF', ...
        'overrunCost_HUF', ...
        'degradationCost_HUF', ...
        'gridImport_kWh', ...
        'gridImportNoBess_kWh', ...
        'bessThroughput_kWh', ...
        'peakReductionVsNoBess_pct', ...
        'thesisTotalCost_HUF'});

    validMask = logical(tableAll.wasSimulated) & ...
                ~logical(tableAll.hasError) & ...
                isfinite(tableAll.thesisTotalCost_HUF);

    validTable = tableAll(validMask, :);

    if isempty(validTable) || height(validTable) == 0
        error('No valid AC/DC candidates to compare.');
    end

    bestByCoupling = local_select_best_by_coupling(validTable);

    reportTable = local_build_report_table(noBessRow, bestByCoupling);

    outputFolder = fullfile(resultRoot, 'evaluation_ac_dc_comparison');

    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    writetable(tableAll, fullfile(outputFolder, 'comparison_all_candidates.csv'));
    writetable(validTable, fullfile(outputFolder, 'comparison_valid_candidates.csv'));
    writetable(reportTable, fullfile(outputFolder, 'thesis_best_candidates_table.csv'));

    figSweep = local_plot_mode_sweep(validTable, objectiveMode, outputFolder);
    figCost = local_plot_cost_components_report(reportTable, outputFolder);
    figEnergy = local_plot_energy_report(reportTable, outputFolder);
    figBess = local_plot_bess_report(reportTable, outputFolder);

    figPeakSavings = [];
    if objectiveMode == "peak_only"
        figPeakSavings = local_plot_peak_only_savings_bar(validTable, outputFolder);
    end

    compareResult = struct();
    compareResult.objectiveMode = objectiveMode;
    compareResult.tableAll = tableAll;
    compareResult.validTable = validTable;
    compareResult.noBessRow = noBessRow;
    compareResult.bestByCoupling = bestByCoupling;
    compareResult.reportTable = reportTable;
    compareResult.outputFolder = outputFolder;
    compareResult.figures = struct();
    compareResult.figures.modeSweep = figSweep;
    compareResult.figures.costComponents = figCost;
    compareResult.figures.energyReport = figEnergy;
    compareResult.figures.bessReport = figBess;
    compareResult.figures.peakSavings = figPeakSavings;

    save(fullfile(outputFolder, 'comparison_result.mat'), ...
        'compareResult', ...
        '-v7.3');

    fprintf('\nAC/DC thesis comparison saved:\n%s\n', outputFolder);
end


function T = local_load_candidate_table(matPath, coupling)

    S = load(matPath);

    if isfield(S, 'configurationDatabase')
        DB = S.configurationDatabase;
    elseif isfield(S, 'DB')
        DB = S.DB;
    else
        error('MAT file does not contain configurationDatabase or DB: %s', matPath);
    end

    if ~isfield(DB, 'candidateTable')
        error('Result DB missing candidateTable: %s', matPath);
    end

    T = DB.candidateTable;
    T.coupling = repmat(string(coupling), height(T), 1);
end


function T = local_add_thesis_economic_columns(T, cfg)

    n = height(T);

    local_require_columns(T, { ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'objectiveCost_HUF', ...
        'finalSoH'});

    simYears = cfg.analysis.simYears;

    capexBess = ...
        T.E_BESS_kWh .* cfg.cost.bess_huf_per_kWh + ...
        T.P_BESS_kW   .* cfg.cost.bess_power_huf_per_kW;

    opexBessAnnual = capexBess .* cfg.cost.bess_opex_frac_per_year;

    finalSoH = T.finalSoH;
    finalSoH(~isfinite(finalSoH)) = 1;

    deltaSoHTotal = max(0, 1 - finalSoH);
    deltaSoHAnnualEq = deltaSoHTotal ./ simYears;

    bessSohCapexTotal = (deltaSoHTotal ./ 0.2) .* capexBess;
    bessOpexTotal = simYears .* opexBessAnnual;
    bessCapexOpexTotal = bessSohCapexTotal + bessOpexTotal;

    bessAnnualCapexOpex = ...
        (deltaSoHAnnualEq ./ 0.2) .* capexBess + opexBessAnnual;

    zeroMask = T.E_BESS_kWh <= 0 | T.P_BESS_kW <= 0;

    capexBess(zeroMask) = 0;
    opexBessAnnual(zeroMask) = 0;
    deltaSoHTotal(zeroMask) = 0;
    deltaSoHAnnualEq(zeroMask) = 0;
    bessSohCapexTotal(zeroMask) = 0;
    bessOpexTotal(zeroMask) = 0;
    bessCapexOpexTotal(zeroMask) = 0;
    bessAnnualCapexOpex(zeroMask) = 0;

    T.bessCapex_HUF = capexBess;
    T.bessOpexAnnual_HUF = opexBessAnnual;
    T.deltaSoHTotal = deltaSoHTotal;
    T.deltaSoHAnnualEq = deltaSoHAnnualEq;
    T.bessSohCapexTotal_HUF = bessSohCapexTotal;
    T.bessOpexTotal_HUF = bessOpexTotal;
    T.bessCapexOpexTotal_HUF = bessCapexOpexTotal;
    T.bessAnnualCapexOpex_HUF = bessAnnualCapexOpex;
    T.thesisTotalCost_HUF = T.objectiveCost_HUF + bessCapexOpexTotal;
    T.thesisAnnualCost_HUF_per_year = T.thesisTotalCost_HUF ./ simYears;

    if ~ismember('energyCostSaving_HUF', T.Properties.VariableNames)
        T.energyCostSaving_HUF = NaN(n, 1);
    end

    if ~ismember('gridImportReduction_pct', T.Properties.VariableNames)
        T.gridImportReduction_pct = NaN(n, 1);
    end

    if ~ismember('equivalentCycles', T.Properties.VariableNames)
        T.equivalentCycles = local_safe_divide_vec(T.bessThroughput_kWh, 2 .* T.E_BESS_kWh);
        T.equivalentCycles(zeroMask) = 0;
    end
end


function T = local_add_no_bess_comparison_columns(T, noBessRow, cfg)

    simYears = cfg.analysis.simYears;

    noBessObjective = noBessRow.objectiveCost_HUF(1);
    noBessEnergy = noBessRow.energyCost_HUF(1);
    noBessContract = noBessRow.contractCost_HUF(1);
    noBessOverrun = noBessRow.overrunCost_HUF(1);
    noBessPeak = noBessRow.maxGridImportPeak_kW(1);

    T.operationalSavingVsNoBess_HUF = noBessObjective - T.objectiveCost_HUF;
    T.energySavingVsNoBess_HUF = noBessEnergy - T.energyCost_HUF;
    T.contractSavingVsNoBess_HUF = noBessContract - T.contractCost_HUF;
    T.overrunSavingVsNoBess_HUF = noBessOverrun - T.overrunCost_HUF;

    T.operationalSavingVsNoBess_HUF_per_year = ...
        T.operationalSavingVsNoBess_HUF ./ simYears;
    T.energySavingVsNoBess_HUF_per_year = ...
        T.energySavingVsNoBess_HUF ./ simYears;
    T.contractSavingVsNoBess_HUF_per_year = ...
        T.contractSavingVsNoBess_HUF ./ simYears;
    T.overrunSavingVsNoBess_HUF_per_year = ...
        T.overrunSavingVsNoBess_HUF ./ simYears;

    T.netSavingVsNoBess_HUF = ...
        T.operationalSavingVsNoBess_HUF - T.bessCapexOpexTotal_HUF;
    T.netAnnualSavingVsNoBess_HUF_per_year = ...
        T.netSavingVsNoBess_HUF ./ simYears;

    T.noBessReferencePeak_kW = repmat(noBessPeak, height(T), 1);
    T.peakReductionVsNoBess_kW = noBessPeak - T.maxGridImportPeak_kW;
    T.peakReductionVsNoBess_pct = 100 .* local_safe_divide_vec( ...
        T.peakReductionVsNoBess_kW, ...
        noBessPeak .* ones(height(T), 1));

    zeroMask = T.E_BESS_kWh <= 0 | T.P_BESS_kW <= 0;

    T.operationalSavingVsNoBess_HUF(zeroMask) = 0;
    T.energySavingVsNoBess_HUF(zeroMask) = 0;
    T.contractSavingVsNoBess_HUF(zeroMask) = 0;
    T.overrunSavingVsNoBess_HUF(zeroMask) = 0;
    T.operationalSavingVsNoBess_HUF_per_year(zeroMask) = 0;
    T.energySavingVsNoBess_HUF_per_year(zeroMask) = 0;
    T.contractSavingVsNoBess_HUF_per_year(zeroMask) = 0;
    T.overrunSavingVsNoBess_HUF_per_year(zeroMask) = 0;
    T.netSavingVsNoBess_HUF(zeroMask) = 0;
    T.netAnnualSavingVsNoBess_HUF_per_year(zeroMask) = 0;
    T.peakReductionVsNoBess_kW(zeroMask) = 0;
    T.peakReductionVsNoBess_pct(zeroMask) = 0;
end


function row = local_select_no_bess_row(T)

    local_require_columns(T, {'BESS_PV_ratio'});

    idx = find(abs(T.BESS_PV_ratio) < 1e-12, 1, 'first');

    if isempty(idx)
        error('No noBESS baseline candidate found: BESS_PV_ratio = 0.');
    end

    row = T(idx, :);
    row.scenarioLabel = "noBESS";
end


function bestByCoupling = local_select_best_by_coupling(validTable)

    couplings = ["dc", "ac"];
    bestByCoupling = table();

    for i = 1:numel(couplings)

        c = couplings(i);
        sub = validTable(validTable.coupling == c & validTable.BESS_PV_ratio > 0, :);

        if isempty(sub) || height(sub) == 0
            error('No valid BESS candidates for coupling: %s', c);
        end

        [~, idx] = min(sub.thesisTotalCost_HUF);
        selected = sub(idx, :);
        selected.scenarioLabel = "best_" + c;

        bestByCoupling = [bestByCoupling; selected]; %#ok<AGROW>
    end
end


function reportTable = local_build_report_table(noBessRow, bestByCoupling)

    reportTable = [noBessRow; bestByCoupling];

    preferredColumns = { ...
        'scenarioLabel', ...
        'coupling', ...
        'candidateID', ...
        'BESS_PV_ratio', ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'bestContract_kW', ...
        'thesisTotalCost_HUF', ...
        'thesisAnnualCost_HUF_per_year', ...
        'objectiveCost_HUF', ...
        'energyCost_HUF', ...
        'contractCost_HUF', ...
        'overrunCost_HUF', ...
        'degradationCost_HUF', ...
        'bessAnnualCapexOpex_HUF', ...
        'bessCapexOpexTotal_HUF', ...
        'operationalSavingVsNoBess_HUF', ...
        'contractSavingVsNoBess_HUF', ...
        'overrunSavingVsNoBess_HUF', ...
        'netSavingVsNoBess_HUF', ...
        'netAnnualSavingVsNoBess_HUF_per_year', ...
        'gridImport_kWh', ...
        'gridImportNoBess_kWh', ...
        'gridImportReduction_kWh', ...
        'gridImportReduction_pct', ...
        'energyCostSaving_HUF', ...
        'bessThroughput_kWh', ...
        'equivalentCycles', ...
        'maxGridImportPeak_kW', ...
        'maxGridImportNoBessPeak_kW', ...
        'peakReduction_kW', ...
        'peakReduction_pct', ...
        'peakReductionVsNoBess_kW', ...
        'peakReductionVsNoBess_pct', ...
        'deltaSoHTotal', ...
        'finalSoC', ...
        'finalSoH', ...
        'runtime_s'};

    preferredColumns = preferredColumns(ismember(preferredColumns, reportTable.Properties.VariableNames));
    reportTable = reportTable(:, preferredColumns);
end


function fig = local_plot_mode_sweep(T, objectiveMode, outputFolder)

    switch objectiveMode
        case "peak_only"
            metrics = { ...
                'bestContract_kW', 'Optimal contracted power [kW]'; ...
                'peakReductionVsNoBess_pct', 'Peak reduction vs noBESS [%]'; ...
                'overrunCost_HUF', 'Overrun cost [HUF]'; ...
                'netAnnualSavingVsNoBess_HUF_per_year', 'Net annual saving vs noBESS [HUF/year]' };
            figTitle = 'Peak-only evaluation - AC/DC sweep';

        case "energy_only"
            metrics = { ...
                'thesisTotalCost_HUF', 'Total cost incl. BESS SoH CAPEX+OPEX [HUF]'; ...
                'energyCostSaving_HUF', 'Energy cost saving [HUF]'; ...
                'gridImportReduction_pct', 'Grid import reduction [%]'; ...
                'bessThroughput_kWh', 'BESS throughput [kWh]' };
            figTitle = 'Energy-only evaluation - AC/DC sweep';

        case "combined"
            metrics = { ...
                'thesisTotalCost_HUF', 'Total cost incl. BESS SoH CAPEX+OPEX [HUF]'; ...
                'bestContract_kW', 'Optimal contracted power [kW]'; ...
                'peakReductionVsNoBess_pct', 'Peak reduction vs noBESS [%]'; ...
                'energyCostSaving_HUF', 'Energy cost saving [HUF]' };
            figTitle = 'Combined evaluation - AC/DC sweep';

        otherwise
            error('Invalid objectiveMode: %s', objectiveMode);
    end

    fig = figure('Name', figTitle, 'Position', [100, 80, 1250, 950]);

    for k = 1:size(metrics, 1)

        metricName = metrics{k, 1};
        yLabelText = metrics{k, 2};

        subplot(size(metrics, 1), 1, k);
        hold on;
        grid on;

        local_plot_metric_by_coupling(T, metricName);

        ylabel(yLabelText);

        if k == 1
            title(figTitle);
        end

        if k == size(metrics, 1)
            xlabel('BESS/PV ratio [-]');
        end

        legend('Location', 'best');
    end

    local_save_figure(fig, outputFolder, sprintf('thesis_%s_sweep_ac_dc', objectiveMode));
end


function local_plot_metric_by_coupling(T, metricName)

    couplings = ["dc", "ac"];

    for i = 1:numel(couplings)

        c = couplings(i);
        sub = T(T.coupling == c, :);
        sub = sortrows(sub, 'BESS_PV_ratio');

        if ~ismember(metricName, sub.Properties.VariableNames)
            y = NaN(height(sub), 1);
        else
            y = sub.(metricName);
        end

        plot(sub.BESS_PV_ratio, y, '-o', ...
            'LineWidth', 1.5, ...
            'MarkerSize', 4, ...
            'DisplayName', upper(c));
    end
end


function fig = local_plot_peak_only_savings_bar(T, outputFolder)

    fig = figure('Name', 'Peak-only savings and BESS annual cost', ...
        'Position', [120, 80, 1350, 850]);

    couplings = ["dc", "ac"];

    for i = 1:numel(couplings)

        c = couplings(i);
        sub = T(T.coupling == c & T.BESS_PV_ratio > 0, :);
        sub = sortrows(sub, 'BESS_PV_ratio');

        xLabels = string(sub.BESS_PV_ratio);

        Y = [ ...
            sub.contractSavingVsNoBess_HUF_per_year, ...
            sub.overrunSavingVsNoBess_HUF_per_year, ...
            sub.bessAnnualCapexOpex_HUF, ...
            sub.netAnnualSavingVsNoBess_HUF_per_year] ./ 1e6;

        subplot(numel(couplings), 1, i);
        bar(categorical(xLabels), Y, 'grouped');
        grid on;
        ylabel('million HUF/year');
        title(sprintf('Peak-only savings vs noBESS - %s coupling', upper(c)));
        legend({ ...
            'Contract cost saving', ...
            'Overrun cost saving', ...
            'BESS annual SoH CAPEX+OPEX', ...
            'Net annual saving'}, ...
            'Location', 'bestoutside');

        if i == numel(couplings)
            xlabel('BESS/PV ratio [-]');
        end
    end

    local_save_figure(fig, outputFolder, 'thesis_peak_only_savings_vs_noBESS_ac_dc');
end


function fig = local_plot_cost_components_report(reportTable, outputFolder)

    fig = figure('Name', 'Cost components - noBESS, best DC, best AC', ...
        'Position', [120, 80, 1200, 800]);

    labels = local_report_labels(reportTable);

    components = [ ...
        local_col(reportTable, 'energyCost_HUF'), ...
        local_col(reportTable, 'contractCost_HUF'), ...
        local_col(reportTable, 'overrunCost_HUF'), ...
        local_col(reportTable, 'degradationCost_HUF'), ...
        local_col(reportTable, 'bessCapexOpexTotal_HUF')] / 1e6;

    subplot(2,1,1);
    bar(categorical(labels), components, 'stacked');
    grid on;
    ylabel('Cost over simulation [million HUF]');
    title('Cost components');
    legend({'Energy', 'Contract', 'Overrun', 'Degradation', 'BESS SoH CAPEX+OPEX'}, ...
        'Location', 'bestoutside');

    subplot(2,1,2);
    bar(categorical(labels), local_col(reportTable, 'thesisAnnualCost_HUF_per_year') / 1e6);
    grid on;
    ylabel('Equivalent annual cost [million HUF/year]');
    title('Equivalent annual total cost');

    local_save_figure(fig, outputFolder, 'thesis_cost_components_noBESS_bestDC_bestAC');
end


function fig = local_plot_energy_report(reportTable, outputFolder)

    fig = figure('Name', 'Energy and peak results - noBESS, best DC, best AC', ...
        'Position', [140, 80, 1200, 900]);

    labels = local_report_labels(reportTable);

    subplot(3,1,1);
    bar(categorical(labels), [ ...
        local_col(reportTable, 'gridImport_kWh'), ...
        local_col(reportTable, 'gridImportNoBess_kWh')] / 1000);
    grid on;
    ylabel('Energy [MWh]');
    title('Grid import');
    legend({'With selected system', 'noBESS reference'}, 'Location', 'best');

    subplot(3,1,2);
    bar(categorical(labels), local_col(reportTable, 'gridImportReduction_pct'));
    grid on;
    ylabel('Reduction [%]');
    title('Grid import reduction');

    subplot(3,1,3);
    bar(categorical(labels), [ ...
        local_col(reportTable, 'maxGridImportPeak_kW'), ...
        local_col(reportTable, 'maxGridImportNoBessPeak_kW')]);
    grid on;
    ylabel('Power [kW]');
    title('Maximum grid import peak');
    legend({'With selected system', 'noBESS reference'}, 'Location', 'best');

    local_save_figure(fig, outputFolder, 'thesis_energy_peak_noBESS_bestDC_bestAC');
end


function fig = local_plot_bess_report(reportTable, outputFolder)

    fig = figure('Name', 'BESS utilization - best DC and best AC', ...
        'Position', [160, 80, 1200, 850]);

    labels = local_report_labels(reportTable);

    subplot(3,1,1);
    bar(categorical(labels), local_col(reportTable, 'bessThroughput_kWh') / 1000);
    grid on;
    ylabel('Throughput [MWh]');
    title('BESS throughput');

    subplot(3,1,2);
    bar(categorical(labels), local_col(reportTable, 'equivalentCycles'));
    grid on;
    ylabel('Cycles [-]');
    title('Equivalent full cycles');

    subplot(3,1,3);
    bar(categorical(labels), [ ...
        local_col(reportTable, 'deltaSoHTotal') * 100, ...
        local_col(reportTable, 'finalSoH') * 100]);
    grid on;
    ylabel('Percent [%]');
    title('Battery degradation and final SoH');
    legend({'Delta SoH', 'Final SoH'}, 'Location', 'best');

    local_save_figure(fig, outputFolder, 'thesis_bess_utilization_noBESS_bestDC_bestAC');
end


function labels = local_report_labels(reportTable)

    if ismember('scenarioLabel', reportTable.Properties.VariableNames)
        labels = string(reportTable.scenarioLabel);
    else
        labels = string(reportTable.coupling);
    end

    labels = matlab.lang.makeValidName(labels);
end


function y = local_col(T, colName)

    if ismember(colName, T.Properties.VariableNames)
        y = T.(colName);
    else
        y = NaN(height(T), 1);
    end
end


function local_require_columns(T, colNames)

    for i = 1:numel(colNames)
        if ~ismember(colNames{i}, T.Properties.VariableNames)
            error('Missing required table column: %s', colNames{i});
        end
    end
end


function y = local_safe_divide_vec(a, b)

    y = NaN(size(a));
    mask = isfinite(a) & isfinite(b) & abs(b) > 1e-12;
    y(mask) = a(mask) ./ b(mask);
end


function local_save_figure(fig, outputFolder, fileName)

    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    savefig(fig, fullfile(outputFolder, [fileName, '.fig']));

    try
        exportgraphics(fig, fullfile(outputFolder, [fileName, '.png']), 'Resolution', 150);
    catch
        saveas(fig, fullfile(outputFolder, [fileName, '.png']));
    end
end
