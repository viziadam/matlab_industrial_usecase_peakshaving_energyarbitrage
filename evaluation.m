function evaluationResult = evaluation(cfg, evalCfg, DB_in)
% EVALUATION
%
% Ipari PV+BESS peak shaving + energia arbitrazs + contract optimalizalas
% eredmenyeinek kiertekelese.
%
% Mukodes:
%   - normal teljes sweep utan ugyanazt a candidateTable-t ertekeli;
%   - diagnosztikai modban a baseline + valasztott candidate-eket ertekeli;
%   - no-BESS baseline-hoz kepest szamol megtakaritasokat;
%   - kulon bontja:
%       1) lekotott teljesitmeny / peak shaving nyereseg,
%       2) energiaoldali nyereseg: arbitrazs + onfogyasztas + PV hasznositas,
%       3) BESS koltsegek,
%       4) netto BESS hozzaadott ertek,
%       5) BESS-only LCOE/LCOS jellegu mutato.

    if nargin < 3
        DB_in = [];
    end

    local_validate_inputs(cfg, evalCfg);

    if isempty(DB_in)
        DB = local_load_candidate_database(evalCfg.input.resultFilePath);
    else
        DB = DB_in;
    end

    if ~isfield(DB, 'candidateTable')
        error('A DB nem tartalmaz candidateTable mezot.');
    end

    Traw = DB.candidateTable;

    if isempty(Traw) || height(Traw) == 0
        error('A DB.candidateTable ures.');
    end

    local_require_table_columns(Traw, {'wasSimulated', 'hasError'}, 'DB.candidateTable');

    validMask = logical(Traw.wasSimulated) & ~logical(Traw.hasError);

    if ~any(validMask)
        error('Nincs sikeresen lefutott candidate a candidateTable-ben.');
    end

    T = Traw(validMask, :);

    requiredColumns = { ...
        'BESS_PV_ratio', ...
        'P_PV_kW', ...
        'P_inv_kW', ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'objectiveCost_HUF', ...
        'energyCost_HUF', ...
        'energyCostNoBess_HUF', ...
        'degradationCost_HUF', ...
        'overrunCost_HUF', ...
        'contractCost_HUF', ...
        'bestContract_kW', ...
        'gridImport_kWh', ...
        'gridImportNoBess_kWh', ...
        'bessThroughput_kWh', ...
        'bessDischarge_kWh', ...
        'maxGridImportPeak_kW', ...
        'maxGridImportNoBessPeak_kW'};

    local_require_table_columns(T, requiredColumns, 'filtered candidateTable');

    T = sortrows(T, 'BESS_PV_ratio');

    baselineMask = abs(T.BESS_PV_ratio) < 1e-12;

    if ~any(baselineMask)
        error('Az evaluation-hoz kell sikeresen lefutott baseline candidate: BESS_PV_ratio = 0.');
    end

    if sum(baselineMask) > 1
        error('Tobb BESS_PV_ratio = 0 baseline candidate talalhato.');
    end

    % =====================================================================
    % Metrikak
    % =====================================================================
    T = local_add_technical_metrics(T);

    T = local_add_capex_metrics(T, cfg, evalCfg);

    % A baselineRow-t mindig frissíteni kell, miután T új oszlopokat kapott.
    baselineRow = T(baselineMask, :);

    T = local_add_value_stack_metrics(T, baselineRow, cfg, evalCfg);

    baselineRow = T(baselineMask, :);

    T = local_add_lifecycle_metrics(T, baselineRow, cfg, evalCfg);

    T = local_add_bess_lcoe_metrics(T, cfg, evalCfg);

    % Végső frissítés, hogy a riporttáblákhoz már minden új metrika meglegyen.
    baselineRow = T(baselineMask, :);

    [bestIdx, selectionInfo] = local_select_best_candidate(T, evalCfg);
    bestCandidate = T(bestIdx, :);

    keyMetricsTable = local_build_key_metrics_table(baselineRow, bestCandidate);

    % =====================================================================
    % Output folders
    % =====================================================================
    outputFolder = evalCfg.output.baseFolder;

    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    tableFolder = fullfile(outputFolder, 'tables');
    figureFolder = fullfile(outputFolder, 'figures');

    if ~exist(tableFolder, 'dir')
        mkdir(tableFolder);
    end

    if ~exist(figureFolder, 'dir')
        mkdir(figureFolder);
    end

    % =====================================================================
    % Mentesek
    % =====================================================================
    if evalCfg.output.saveReportTables
        writetable(T, fullfile(tableFolder, 'evaluation_candidate_table.csv'));
        writetable(bestCandidate, fullfile(tableFolder, 'best_candidate_table.csv'));
        writetable(keyMetricsTable, fullfile(tableFolder, 'key_metrics_table.csv'));

        save(fullfile(tableFolder, 'evaluation_tables.mat'), ...
            'T', ...
            'bestCandidate', ...
            'keyMetricsTable');
    end

    if evalCfg.output.saveEvaluationCsv
        writetable(T, fullfile(outputFolder, 'evaluation_candidate_table.csv'));
    end

    % =====================================================================
    % Abrak
    % =====================================================================
    figureHandles = struct();

    if evalCfg.plots.makePlots

        if evalCfg.plots.makeCandidateSweepPlots

            figureHandles.costStack = local_plot_cost_stack(T, bestCandidate, figureFolder);
            figureHandles.valueStack = local_plot_value_stack(T, bestCandidate, figureFolder);
            figureHandles.lifecycle = local_plot_lifecycle(T, bestCandidate, figureFolder);
            figureHandles.technical = local_plot_technical(T, bestCandidate, figureFolder);
            figureHandles.bessLcoe = local_plot_bess_lcoe(T, bestCandidate, figureFolder);

        end
    end

    % =====================================================================
    % Eredmeny
    % =====================================================================
    evaluationResult = struct();

    evaluationResult.createdAt = datetime('now');
    evaluationResult.selectionInfo = selectionInfo;
    evaluationResult.candidateTable = T;
    evaluationResult.bestCandidateTable = bestCandidate;
    evaluationResult.bestCandidate = table2struct(bestCandidate);
    evaluationResult.baselineCandidate = table2struct(baselineRow);
    evaluationResult.keyMetricsTable = keyMetricsTable;
    evaluationResult.figureHandles = figureHandles;

    if evalCfg.output.saveEvaluationMat
        save(fullfile(outputFolder, 'evaluation_result.mat'), ...
            'evaluationResult', ...
            '-v7.3');
    end

    fprintf('\n================ EVALUATION SUMMARY ================\n');
    fprintf('Valid candidates: %d\n', height(T));
    fprintf('Selection mode: %s\n', string(evalCfg.selection.mode));

    fprintf('\nBest candidate:\n');
    fprintf('  BESS/PV ratio:                  %.3f\n', bestCandidate.BESS_PV_ratio);
    fprintf('  E_BESS:                         %.2f kWh\n', bestCandidate.E_BESS_kWh);
    fprintf('  P_BESS:                         %.2f kW\n', bestCandidate.P_BESS_kW);
    fprintf('  Best contract:                  %.2f kW\n', bestCandidate.bestContract_kW);
    fprintf('  Objective cost:                 %.2f million HUF\n', bestCandidate.objectiveCost_HUF / 1e6);
    fprintf('  Annual contract saving:         %.2f million HUF/year\n', bestCandidate.annualContractSaving_HUF / 1e6);
    fprintf('  Annual energy saving:           %.2f million HUF/year\n', bestCandidate.annualEnergySaving_HUF / 1e6);
    fprintf('  Annual BESS added value:        %.2f million HUF/year\n', bestCandidate.annualBessAddedValue_HUF / 1e6);
    fprintf('  NPV vs baseline:                %.2f million HUF\n', bestCandidate.NPV_HUF / 1e6);
    fprintf('  BESS LCOE/LCOS:                 %.2f HUF/kWh\n', bestCandidate.BESS_LCOE_HUF_per_kWh);
    fprintf('====================================================\n');
end


% =========================================================================
% VALIDATION
% =========================================================================
function local_validate_inputs(cfg, evalCfg)

    if nargin < 1 || isempty(cfg)
        error('Hiányzó bemenet: cfg.');
    end

    if nargin < 2 || isempty(evalCfg)
        error('Hiányzó bemenet: evalCfg.');
    end

    local_require_struct_fields(cfg, {'cost'}, 'cfg');

    requiredCostFields = { ...
        'pv_huf_per_kWp', ...
        'bess_huf_per_kWh', ...
        'bess_power_huf_per_kW', ...
        'inverter_huf_per_kW', ...
        'pv_opex_frac_per_year', ...
        'bess_opex_frac_per_year', ...
        'inverter_opex_frac_per_year'};

    local_require_struct_fields(cfg.cost, requiredCostFields, 'cfg.cost');

    requiredEvalTopFields = {'input', 'output', 'plots', 'selection', 'economics'};
    local_require_struct_fields(evalCfg, requiredEvalTopFields, 'evalCfg');

    local_require_struct_fields(evalCfg.output, ...
        {'baseFolder', 'saveEvaluationMat', 'saveEvaluationCsv', 'saveReportTables'}, ...
        'evalCfg.output');

    local_require_struct_fields(evalCfg.plots, {'makePlots'}, 'evalCfg.plots');
    local_require_struct_fields(evalCfg.selection, {'mode'}, 'evalCfg.selection');

    local_require_struct_fields(evalCfg.economics, ...
        {'simYears', 'projectLifetime_years', 'discountRate'}, ...
        'evalCfg.economics');
end


function local_require_struct_fields(S, fieldNames, structName)

    for i = 1:numel(fieldNames)
        f = fieldNames{i};

        if ~isfield(S, f)
            error('Hiányzó mező: %s.%s', structName, f);
        end
    end
end


function local_require_table_columns(T, requiredColumns, tableName)

    varNames = T.Properties.VariableNames;

    for i = 1:numel(requiredColumns)
        col = requiredColumns{i};

        if ~ismember(col, varNames)
            error('A(z) %s nem tartalmazza a szükséges oszlopot: %s', tableName, col);
        end
    end
end


function DB = local_load_candidate_database(resultFilePath)

    S = load(resultFilePath);

    if isfield(S, 'DB')
        DB = S.DB;
        return;
    end

    if isfield(S, 'configurationDatabase')
        DB = S.configurationDatabase;
        return;
    end

    error('A MAT file nem tartalmaz DB vagy configurationDatabase változót: %s', resultFilePath);
end


% =========================================================================
% METRICS
% =========================================================================
function T = local_add_technical_metrics(T)

    T.gridImportReduction_kWh = T.gridImportNoBess_kWh - T.gridImport_kWh;

    T.gridImportReduction_pct = ...
        100 * T.gridImportReduction_kWh ./ max(T.gridImportNoBess_kWh, eps);

    T.peakReduction_kW = ...
        T.maxGridImportNoBessPeak_kW - T.maxGridImportPeak_kW;

    T.peakReduction_pct = ...
        100 * T.peakReduction_kW ./ max(T.maxGridImportNoBessPeak_kW, eps);

    T.energyCostSaving_HUF = T.energyCostNoBess_HUF - T.energyCost_HUF;

    T.equivalentCycles = zeros(height(T), 1);

    hasBess = T.E_BESS_kWh > 0;

    T.equivalentCycles(hasBess) = ...
        T.bessThroughput_kWh(hasBess) ./ ...
        max(2 * T.E_BESS_kWh(hasBess), eps);
end


function T = local_add_capex_metrics(T, cfg, evalCfg)

    projectYears = evalCfg.economics.projectLifetime_years;
    discountRate = evalCfg.economics.discountRate;

    T.capexPV_HUF = T.P_PV_kW .* cfg.cost.pv_huf_per_kWp;

    T.capexBESS_HUF = ...
        T.E_BESS_kWh .* cfg.cost.bess_huf_per_kWh + ...
        T.P_BESS_kW .* cfg.cost.bess_power_huf_per_kW;

    T.capexInverter_HUF = T.P_inv_kW .* cfg.cost.inverter_huf_per_kW;

    T.initialCapex_HUF = ...
        T.capexPV_HUF + ...
        T.capexBESS_HUF + ...
        T.capexInverter_HUF;

    crf = local_capital_recovery_factor(discountRate, projectYears);

    T.annualizedPVCapex_HUF = T.capexPV_HUF .* crf;
    T.annualizedBessCapex_HUF = T.capexBESS_HUF .* crf;
    T.annualizedInverterCapex_HUF = T.capexInverter_HUF .* crf;

    T.annualizedCapex_HUF = ...
        T.annualizedPVCapex_HUF + ...
        T.annualizedBessCapex_HUF + ...
        T.annualizedInverterCapex_HUF;

    T.annualPV_OPEX_HUF = T.capexPV_HUF .* cfg.cost.pv_opex_frac_per_year;
    T.annualBESS_OPEX_HUF = T.capexBESS_HUF .* cfg.cost.bess_opex_frac_per_year;
    T.annualInverter_OPEX_HUF = T.capexInverter_HUF .* cfg.cost.inverter_opex_frac_per_year;

    T.annualOPEX_HUF = ...
        T.annualPV_OPEX_HUF + ...
        T.annualBESS_OPEX_HUF + ...
        T.annualInverter_OPEX_HUF;
end


function T = local_add_value_stack_metrics(T, baselineRow, cfg, evalCfg) %#ok<INUSD>

    simYears = evalCfg.economics.simYears;

    T.annualObjectiveCost_HUF = T.objectiveCost_HUF ./ simYears;

    T.annualEnergyCost_HUF = T.energyCost_HUF ./ simYears;
    T.annualEnergyCostNoBess_HUF = T.energyCostNoBess_HUF ./ simYears;

    T.annualContractCost_HUF = T.contractCost_HUF ./ simYears;
    T.annualOverrunCost_HUF = T.overrunCost_HUF ./ simYears;
    T.annualDegradationCost_HUF = T.degradationCost_HUF ./ simYears;

    baselineAnnualEnergyCost_HUF = baselineRow.energyCost_HUF / simYears;
    baselineAnnualContractCost_HUF = baselineRow.contractCost_HUF / simYears;
    baselineAnnualOverrunCost_HUF = baselineRow.overrunCost_HUF / simYears;
    baselineAnnualObjectiveCost_HUF = baselineRow.objectiveCost_HUF / simYears;

    T.annualContractSaving_HUF = ...
        baselineAnnualContractCost_HUF - T.annualContractCost_HUF;

    T.annualEnergySaving_HUF = ...
        baselineAnnualEnergyCost_HUF - T.annualEnergyCost_HUF;

    T.annualOverrunSaving_HUF = ...
        baselineAnnualOverrunCost_HUF - T.annualOverrunCost_HUF;

    T.annualGrossOperationalSaving_HUF = ...
        baselineAnnualObjectiveCost_HUF - T.annualObjectiveCost_HUF;

    T.annualBessCost_HUF = ...
        T.annualizedBessCapex_HUF + ...
        T.annualBESS_OPEX_HUF + ...
        T.annualDegradationCost_HUF;

    T.annualBessAddedValue_HUF = ...
        T.annualContractSaving_HUF + ...
        T.annualEnergySaving_HUF + ...
        T.annualOverrunSaving_HUF - ...
        T.annualBessCost_HUF;

    T.annualSystemCost_HUF = ...
        T.annualObjectiveCost_HUF + ...
        T.annualOPEX_HUF + ...
        T.annualizedCapex_HUF;

    T.annualNetSaving_HUF = ...
        baselineAnnualObjectiveCost_HUF - T.annualObjectiveCost_HUF - ...
        T.annualBESS_OPEX_HUF - ...
        T.annualDegradationCost_HUF;
end


function T = local_add_lifecycle_metrics(T, baselineRow, cfg, evalCfg) %#ok<INUSD>

    years = evalCfg.economics.projectLifetime_years;
    r = evalCfg.economics.discountRate;

    baselineInitialCapex_HUF = baselineRow.initialCapex_HUF;
    baselineAnnualSystemCost_HUF = baselineRow.annualSystemCost_HUF;

    baselineLifecycleCost_HUF = ...
        baselineInitialCapex_HUF + ...
        local_present_value_annuity(baselineAnnualSystemCost_HUF, r, years);

    T.incrementalCapex_HUF = T.initialCapex_HUF - baselineInitialCapex_HUF;

    T.totalLifecycleCost_HUF = ...
        T.initialCapex_HUF + ...
        local_present_value_annuity(T.annualSystemCost_HUF, r, years);

    T.lifecycleCostSaving_HUF = ...
        baselineLifecycleCost_HUF - T.totalLifecycleCost_HUF;

    T.NPV_HUF = ...
        -T.incrementalCapex_HUF + ...
        local_present_value_annuity(T.annualNetSaving_HUF, r, years);

    T.simplePayback_years = ...
        local_simple_payback(T.incrementalCapex_HUF, T.annualNetSaving_HUF);

    T.discountedPayback_years = ...
        local_discounted_payback(T.incrementalCapex_HUF, T.annualNetSaving_HUF, r, years);

    T.initialCapex_millionHUF = T.initialCapex_HUF / 1e6;
    T.NPV_millionHUF = T.NPV_HUF / 1e6;
    T.totalLifecycleCost_millionHUF = T.totalLifecycleCost_HUF / 1e6;
    T.annualBessAddedValue_millionHUF = T.annualBessAddedValue_HUF / 1e6;
end


function T = local_add_bess_lcoe_metrics(T, cfg, evalCfg) %#ok<INUSD>

    simYears = evalCfg.economics.simYears;

    T.annualBessDischarge_kWh = T.bessDischarge_kWh ./ simYears;

    T.BESS_LCOE_HUF_per_kWh = NaN(height(T), 1);

    hasBess = T.E_BESS_kWh > 0 & T.annualBessDischarge_kWh > 0;

    annualBessCost = ...
        T.annualizedBessCapex_HUF + ...
        T.annualBESS_OPEX_HUF + ...
        T.annualDegradationCost_HUF;

    T.BESS_LCOE_HUF_per_kWh(hasBess) = ...
        annualBessCost(hasBess) ./ ...
        T.annualBessDischarge_kWh(hasBess);
end


% =========================================================================
% BEST SELECTION
% =========================================================================
function [bestIdx, selectionInfo] = local_select_best_candidate(T, evalCfg)

    mode = string(evalCfg.selection.mode);

    switch mode

        case "minTotalLifecycleCost"
            [bestValue, bestIdx] = min(T.totalLifecycleCost_HUF);
            selectedField = "totalLifecycleCost_HUF";

        case "maxNPV"
            [bestValue, bestIdx] = max(T.NPV_HUF);
            selectedField = "NPV_HUF";

        case "maxBessAddedValue"
            [bestValue, bestIdx] = max(T.annualBessAddedValue_HUF);
            selectedField = "annualBessAddedValue_HUF";

        case "minObjectiveCost"
            [bestValue, bestIdx] = min(T.objectiveCost_HUF);
            selectedField = "objectiveCost_HUF";

        otherwise
            error('Ismeretlen evalCfg.selection.mode: %s', mode);
    end

    selectionInfo = struct();
    selectionInfo.mode = mode;
    selectionInfo.selectedField = selectedField;
    selectionInfo.bestValue = bestValue;
    selectionInfo.bestIdxInFilteredTable = bestIdx;
end


% =========================================================================
% TABLES
% =========================================================================
function keyMetricsTable = local_build_key_metrics_table(baselineRow, bestCandidate)

    Metric = strings(0, 1);
    Unit = strings(0, 1);
    BaselineValue = [];
    BestCandidateValue = [];

    [Metric, Unit, BaselineValue, BestCandidateValue] = local_add_row(Metric, Unit, BaselineValue, BestCandidateValue, ...
        "BESS/PV arany", "-", baselineRow.BESS_PV_ratio, bestCandidate.BESS_PV_ratio);

    [Metric, Unit, BaselineValue, BestCandidateValue] = local_add_row(Metric, Unit, BaselineValue, BestCandidateValue, ...
        "BESS energia kapacitas", "kWh", baselineRow.E_BESS_kWh, bestCandidate.E_BESS_kWh);

    [Metric, Unit, BaselineValue, BestCandidateValue] = local_add_row(Metric, Unit, BaselineValue, BestCandidateValue, ...
        "BESS teljesitmeny", "kW", baselineRow.P_BESS_kW, bestCandidate.P_BESS_kW);

    [Metric, Unit, BaselineValue, BestCandidateValue] = local_add_row(Metric, Unit, BaselineValue, BestCandidateValue, ...
        "Optimalis lekotott teljesitmeny", "kW", baselineRow.bestContract_kW, bestCandidate.bestContract_kW);

    [Metric, Unit, BaselineValue, BestCandidateValue] = local_add_row(Metric, Unit, BaselineValue, BestCandidateValue, ...
        "Eves contract megtakaritas", "million HUF/year", baselineRow.annualContractSaving_HUF / 1e6, bestCandidate.annualContractSaving_HUF / 1e6);

    [Metric, Unit, BaselineValue, BestCandidateValue] = local_add_row(Metric, Unit, BaselineValue, BestCandidateValue, ...
        "Eves energiaoldali megtakaritas", "million HUF/year", baselineRow.annualEnergySaving_HUF / 1e6, bestCandidate.annualEnergySaving_HUF / 1e6);

    [Metric, Unit, BaselineValue, BestCandidateValue] = local_add_row(Metric, Unit, BaselineValue, BestCandidateValue, ...
        "Eves BESS hozzaadott ertek", "million HUF/year", baselineRow.annualBessAddedValue_HUF / 1e6, bestCandidate.annualBessAddedValue_HUF / 1e6);

    [Metric, Unit, BaselineValue, BestCandidateValue] = local_add_row(Metric, Unit, BaselineValue, BestCandidateValue, ...
        "NPV baseline-hoz kepest", "million HUF", baselineRow.NPV_HUF / 1e6, bestCandidate.NPV_HUF / 1e6);

    [Metric, Unit, BaselineValue, BestCandidateValue] = local_add_row(Metric, Unit, BaselineValue, BestCandidateValue, ...
        "BESS LCOE/LCOS", "HUF/kWh", baselineRow.BESS_LCOE_HUF_per_kWh, bestCandidate.BESS_LCOE_HUF_per_kWh);

    [Metric, Unit, BaselineValue, BestCandidateValue] = local_add_row(Metric, Unit, BaselineValue, BestCandidateValue, ...
        "Peak csokkentes", "%", baselineRow.peakReduction_pct, bestCandidate.peakReduction_pct);

    keyMetricsTable = table(Metric, Unit, BaselineValue, BestCandidateValue);
end


function [Metric, Unit, BaselineValue, BestCandidateValue] = local_add_row( ...
    Metric, Unit, BaselineValue, BestCandidateValue, metricName, unitName, baselineValue, bestValue)

    Metric(end+1, 1) = metricName;
    Unit(end+1, 1) = unitName;
    BaselineValue(end+1, 1) = baselineValue;
    BestCandidateValue(end+1, 1) = bestValue;
end


% =========================================================================
% PLOTS
% =========================================================================
function fig = local_plot_cost_stack(T, bestCandidate, figureFolder)

    x = T.BESS_PV_ratio;

    fig = figure('Name', 'Evaluation cost stack', 'Position', [100, 80, 1300, 850]);

    tiledlayout(2, 1);

    nexttile; hold on; grid on;
    plot(x, T.energyCost_HUF / 1e6, '-o', 'LineWidth', 1.5, 'DisplayName', 'Energy');
    plot(x, T.contractCost_HUF / 1e6, '-s', 'LineWidth', 1.5, 'DisplayName', 'Contract');
    plot(x, T.overrunCost_HUF / 1e6, '-^', 'LineWidth', 1.5, 'DisplayName', 'Overrun');
    plot(x, T.degradationCost_HUF / 1e6, '-d', 'LineWidth', 1.5, 'DisplayName', 'Degradation');
    plot(x, T.objectiveCost_HUF / 1e6, '-x', 'LineWidth', 2.0, 'DisplayName', 'Objective');
    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, 'DisplayName', 'Best');
    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Simulated period cost [million HUF]');
    title('Szimulalt idoszak koltsegkomponensei');
    legend('Location', 'best');

    nexttile; hold on; grid on;
    plot(x, T.annualizedBessCapex_HUF / 1e6, '-o', 'LineWidth', 1.5, 'DisplayName', 'Annualized BESS CAPEX');
    plot(x, T.annualBESS_OPEX_HUF / 1e6, '-s', 'LineWidth', 1.5, 'DisplayName', 'BESS OPEX');
    plot(x, T.annualDegradationCost_HUF / 1e6, '-^', 'LineWidth', 1.5, 'DisplayName', 'Degradation');
    plot(x, T.annualBessCost_HUF / 1e6, '-x', 'LineWidth', 2.0, 'DisplayName', 'Total BESS cost');
    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, 'DisplayName', 'Best');
    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Annual BESS cost [million HUF/year]');
    title('BESS evesitett koltsegei');
    legend('Location', 'best');

    local_save_figure(fig, figureFolder, 'evaluation_cost_stack');
end


function fig = local_plot_value_stack(T, bestCandidate, figureFolder)

    x = T.BESS_PV_ratio;

    fig = figure('Name', 'Evaluation value stack', 'Position', [120, 80, 1300, 850]);

    tiledlayout(2, 1);

    nexttile; hold on; grid on;
    plot(x, T.annualContractSaving_HUF / 1e6, '-o', 'LineWidth', 1.5, 'DisplayName', 'Contract saving');
    plot(x, T.annualEnergySaving_HUF / 1e6, '-s', 'LineWidth', 1.5, 'DisplayName', 'Energy saving');
    plot(x, T.annualOverrunSaving_HUF / 1e6, '-^', 'LineWidth', 1.5, 'DisplayName', 'Overrun saving');
    plot(x, T.annualBessCost_HUF / 1e6, '-d', 'LineWidth', 1.5, 'DisplayName', 'BESS cost');
    plot(x, T.annualBessAddedValue_HUF / 1e6, '-x', 'LineWidth', 2.0, 'DisplayName', 'Net BESS value');
    yline(0, 'k--', 'LineWidth', 1.0);
    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, 'DisplayName', 'Best');
    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Annual value [million HUF/year]');
    title('BESS hozzaadott ertek es megtakaritasi komponensek');
    legend('Location', 'best');

    nexttile; hold on; grid on;
    bar(x, [ ...
        T.annualContractSaving_HUF, ...
        T.annualEnergySaving_HUF, ...
        T.annualOverrunSaving_HUF, ...
        -T.annualBessCost_HUF] / 1e6, 'stacked');
    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Annual value stack [million HUF/year]');
    title('Eves value stack: contract + energia + overrun - BESS koltseg');
    legend({'Contract saving', 'Energy saving', 'Overrun saving', 'BESS cost'}, 'Location', 'best');

    local_save_figure(fig, figureFolder, 'evaluation_value_stack');
end


function fig = local_plot_lifecycle(T, bestCandidate, figureFolder)

    x = T.BESS_PV_ratio;

    fig = figure('Name', 'Evaluation lifecycle economics', 'Position', [140, 80, 1300, 850]);

    tiledlayout(2, 1);

    nexttile; hold on; grid on;
    plot(x, T.NPV_HUF / 1e6, '-o', 'LineWidth', 1.8, 'DisplayName', 'NPV');
    plot(x, T.totalLifecycleCost_HUF / 1e6, '-s', 'LineWidth', 1.8, 'DisplayName', 'Lifecycle cost');
    yline(0, 'k--', 'LineWidth', 1.0);
    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, 'DisplayName', 'Best');
    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('million HUF');
    title('Eletciklus gazdasagi mutatok');
    legend('Location', 'best');

    nexttile; hold on; grid on;
    plot(x, T.simplePayback_years, '-o', 'LineWidth', 1.5, 'DisplayName', 'Simple payback');
    plot(x, T.discountedPayback_years, '-s', 'LineWidth', 1.5, 'DisplayName', 'Discounted payback');
    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, 'DisplayName', 'Best');
    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('years');
    title('Megterules');
    legend('Location', 'best');

    local_save_figure(fig, figureFolder, 'evaluation_lifecycle');
end


function fig = local_plot_technical(T, bestCandidate, figureFolder)

    x = T.BESS_PV_ratio;

    fig = figure('Name', 'Evaluation technical indicators', 'Position', [160, 80, 1300, 850]);

    tiledlayout(2, 1);

    nexttile; hold on; grid on;
    plot(x, T.bestContract_kW, '-o', 'LineWidth', 1.8, 'DisplayName', 'Best contract');
    plot(x, T.maxGridImportPeak_kW, '-s', 'LineWidth', 1.5, 'DisplayName', 'Max grid peak');
    plot(x, T.maxGridImportNoBessPeak_kW, '--', 'LineWidth', 1.5, 'DisplayName', 'No-BESS peak reference');
    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, 'DisplayName', 'Best');
    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Power [kW]');
    title('Lekotott teljesitmeny es peak mutatok');
    legend('Location', 'best');

    nexttile; hold on; grid on;
    plot(x, T.gridImportReduction_pct, '-o', 'LineWidth', 1.5, 'DisplayName', 'Grid import reduction');
    plot(x, T.peakReduction_pct, '-s', 'LineWidth', 1.5, 'DisplayName', 'Peak reduction');
    plot(x, T.equivalentCycles, '-^', 'LineWidth', 1.5, 'DisplayName', 'Equivalent cycles');
    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, 'DisplayName', 'Best');
    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('%, cycles');
    title('Technikai hatasmutatok');
    legend('Location', 'best');

    local_save_figure(fig, figureFolder, 'evaluation_technical');
end


function fig = local_plot_bess_lcoe(T, bestCandidate, figureFolder)

    x = T.BESS_PV_ratio;

    fig = figure('Name', 'BESS LCOE LCOS', 'Position', [180, 80, 1200, 650]);

    hold on; grid on;
    plot(x, T.BESS_LCOE_HUF_per_kWh, '-o', 'LineWidth', 1.8, 'DisplayName', 'BESS LCOE/LCOS');
    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, 'DisplayName', 'Best');
    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('HUF/kWh discharged');
    title('BESS-only fajlagos tarolasi koltseg');
    legend('Location', 'best');

    local_save_figure(fig, figureFolder, 'evaluation_bess_lcoe');
end


function local_save_figure(fig, figureFolder, fileName)

    if ~exist(figureFolder, 'dir')
        mkdir(figureFolder);
    end

    savefig(fig, fullfile(figureFolder, [fileName, '.fig']));

    try
        exportgraphics(fig, fullfile(figureFolder, [fileName, '.png']), 'Resolution', 150);
    catch
        saveas(fig, fullfile(figureFolder, [fileName, '.png']));
    end
end


% =========================================================================
% FINANCIAL HELPERS
% =========================================================================
function crf = local_capital_recovery_factor(r, n)

    if n <= 0
        error('A CRF evek szama legyen pozitiv.');
    end

    if r < 0
        error('A diszkontrata nem lehet negativ.');
    end

    if r == 0
        crf = 1 / n;
    else
        crf = r * (1 + r)^n / ((1 + r)^n - 1);
    end
end


function pv = local_present_value_annuity(annualValue, r, n)

    if n <= 0
        error('A present value annuity evek szama legyen pozitiv.');
    end

    if r < 0
        error('A diszkontrata nem lehet negativ.');
    end

    if r == 0
        pv = annualValue .* n;
    else
        pv = annualValue .* ((1 - (1 + r)^(-n)) / r);
    end
end


function payback = local_simple_payback(capex, annualSaving)

    payback = inf(size(capex));

    mask = annualSaving > 0;
    payback(mask) = capex(mask) ./ annualSaving(mask);

    payback(capex <= 0 & annualSaving >= 0) = 0;
end


function payback = local_discounted_payback(capex, annualSaving, r, n)

    payback = inf(size(capex));

    for i = 1:numel(capex)

        if capex(i) <= 0 && annualSaving(i) >= 0
            payback(i) = 0;
            continue;
        end

        if annualSaving(i) <= 0
            payback(i) = inf;
            continue;
        end

        cumulative = 0;

        for y = 1:n

            discounted = annualSaving(i) / (1 + r)^y;
            previous = cumulative;
            cumulative = cumulative + discounted;

            if cumulative >= capex(i)
                missing = capex(i) - previous;
                payback(i) = (y - 1) + missing / discounted;
                break;
            end
        end
    end
end