function compareResult = compare_ac_dc_results_for_mode(cfgBase, objectiveMode)
% COMPARE_AC_DC_RESULTS_FOR_MODE
%
% Teljes sweep utan osszehasonlitja az AC es DC eredmenyeket ugyanarra a
% mukodesi modra.
%
% Bemenet:
%   cfgBase       - create_configurations(basePath) kimenete
%   objectiveMode - "peak_only", "energy_only" vagy "combined"
%
% Kimenet:
%   compareResult.tableAll
%   compareResult.bestByCoupling
%   compareResult.outputFolder

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

    if ~ismember('wasSimulated', tableAll.Properties.VariableNames)
        error('candidateTable missing wasSimulated column.');
    end

    if ~ismember('hasError', tableAll.Properties.VariableNames)
        error('candidateTable missing hasError column.');
    end

    validMask = logical(tableAll.wasSimulated) & ~logical(tableAll.hasError);
    validTable = tableAll(validMask, :);

    if isempty(validTable) || height(validTable) == 0
        error('No valid AC/DC candidates to compare.');
    end

    requiredColumns = { ...
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
        'peakReduction_pct'};

    for i = 1:numel(requiredColumns)
        if ~ismember(requiredColumns{i}, validTable.Properties.VariableNames)
            error('Comparison table missing required column: %s', requiredColumns{i});
        end
    end

    bestByCoupling = table();

    couplings = ["dc", "ac"];

    for i = 1:numel(couplings)

        c = couplings(i);
        sub = validTable(validTable.coupling == c, :);

        if isempty(sub) || height(sub) == 0
            error('No valid candidates for coupling: %s', c);
        end

        [~, idx] = min(sub.objectiveCost_HUF);
        bestByCoupling = [bestByCoupling; sub(idx, :)]; %#ok<AGROW>
    end

    detailColumns = { ...
        'coupling', ...
        'candidateID', ...
        'BESS_PV_ratio', ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'bestContract_kW', ...
        'objectiveCost_HUF', ...
        'energyCost_HUF', ...
        'contractCost_HUF', ...
        'overrunCost_HUF', ...
        'degradationCost_HUF', ...
        'gridImport_kWh', ...
        'gridImportNoBess_kWh', ...
        'bessThroughput_kWh', ...
        'maxGridImportPeak_kW', ...
        'maxGridImportNoBessPeak_kW', ...
        'peakReduction_kW', ...
        'peakReduction_pct', ...
        'finalSoC', ...
        'finalSoH', ...
        'runtime_s'};

    detailColumns = detailColumns(ismember(detailColumns, bestByCoupling.Properties.VariableNames));
    bestDetailTable = bestByCoupling(:, detailColumns);

    outputFolder = fullfile(resultRoot, 'evaluation_ac_dc_comparison');

    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    writetable(tableAll, fullfile(outputFolder, 'comparison_all_candidates.csv'));
    writetable(validTable, fullfile(outputFolder, 'comparison_valid_candidates.csv'));
    writetable(bestDetailTable, fullfile(outputFolder, 'best_ac_dc_candidates.csv'));

    fig1 = local_plot_metric_vs_ratio( ...
        validTable, ...
        'objectiveCost_HUF', ...
        'Objective cost [HUF]', ...
        'AC/DC objective cost', ...
        outputFolder, ...
        'objective_cost_ac_dc');

    fig2 = local_plot_metric_vs_ratio( ...
        validTable, ...
        'bestContract_kW', ...
        'Best contract [kW]', ...
        'AC/DC optimal contract', ...
        outputFolder, ...
        'best_contract_ac_dc');

    fig3 = local_plot_metric_vs_ratio( ...
        validTable, ...
        'peakReduction_pct', ...
        'Peak reduction [%]', ...
        'AC/DC peak reduction', ...
        outputFolder, ...
        'peak_reduction_ac_dc');

    fig4 = local_plot_cost_components_best(bestByCoupling, outputFolder);

    compareResult = struct();
    compareResult.objectiveMode = objectiveMode;
    compareResult.tableAll = tableAll;
    compareResult.validTable = validTable;
    compareResult.bestByCoupling = bestByCoupling;
    compareResult.bestDetailTable = bestDetailTable;
    compareResult.outputFolder = outputFolder;
    compareResult.figures = struct();
    compareResult.figures.objectiveCost = fig1;
    compareResult.figures.bestContract = fig2;
    compareResult.figures.peakReduction = fig3;
    compareResult.figures.costComponents = fig4;

    save(fullfile(outputFolder, 'comparison_result.mat'), ...
        'compareResult', ...
        '-v7.3');

    fprintf('\nAC/DC comparison saved:\n%s\n', outputFolder);
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
    T.coupling = repmat(coupling, height(T), 1);
end


function fig = local_plot_metric_vs_ratio(T, metricName, yLabelText, titleText, outputFolder, fileName)

    fig = figure('Name', titleText, 'Position', [100, 100, 1250, 700]);
    hold on;
    grid on;

    couplings = ["dc", "ac"];

    for i = 1:numel(couplings)

        c = couplings(i);
        sub = T(T.coupling == c, :);
        sub = sortrows(sub, 'BESS_PV_ratio');

        plot(sub.BESS_PV_ratio, sub.(metricName), '-o', ...
            'LineWidth', 1.8, ...
            'DisplayName', upper(c));
    end

    xlabel('BESS/PV ratio [-]');
    ylabel(yLabelText);
    title(titleText);
    legend('Location', 'best');

    local_save_figure(fig, outputFolder, fileName);
end


function fig = local_plot_cost_components_best(bestByCoupling, outputFolder)

    fig = figure('Name', 'Best AC/DC cost components', 'Position', [120, 100, 1200, 700]);
    hold on;
    grid on;

    components = [ ...
        bestByCoupling.energyCost_HUF, ...
        bestByCoupling.contractCost_HUF, ...
        bestByCoupling.overrunCost_HUF, ...
        bestByCoupling.degradationCost_HUF] / 1e6;

    bar(categorical(upper(string(bestByCoupling.coupling))), components, 'stacked');

    ylabel('Cost [million HUF]');
    title('Best AC/DC candidates - operational cost components');
    legend({'Energy', 'Contract', 'Overrun', 'Degradation'}, 'Location', 'best');

    local_save_figure(fig, outputFolder, 'best_ac_dc_cost_components');
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
