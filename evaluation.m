function evaluationResult = evaluation(cfg, evalCfg)
% EVALUATION
%
% Ipari PV+BESS peak shaving + energia arbitrazs + contract optimalizalas
% eredmenyeinek kiertekelese.
%
% Ez a valtozat:
%   - a candidateTable alapu DB struktura eredmenyeit olvassa be,
%   - 1D-ben ertekel BESS_PV_ratio menten,
%   - megtartja a MATLAB table alapu menteseket,
%   - szamol netto jelenerteket, teljes eletciklus koltseget,
%     beruhazasi koltseget, eves megtakaritast,
%   - abrazolja a fontosabb mutatokat 1D gorbekent,
%   - azonos tipusu mutatokat egy figure-ben abrazol.
%
% Elvart fontos candidateTable oszlopok:
%   BESS_PV_ratio
%   P_PV_kW
%   P_inv_kW
%   E_BESS_kWh
%   P_BESS_kW
%   objectiveCost_HUF
%   energyCost_HUF
%   energyCostNoBess_HUF
%   degradationCost_HUF
%   overrunCost_HUF
%   contractCost_HUF
%   bestContract_kW
%   gridImport_kWh
%   gridImportNoBess_kWh
%   bessThroughput_kWh
%   maxGridImportPeak_kW
%   maxGridImportNoBessPeak_kW
%
% Fontos:
%   A gazdasagi NPV a BESS_PV_ratio = 0 baseline candidate-hez kepest
%   ertelmezett. Ezert kell egy sikeresen lefutott 0-s candidate.

    % =====================================================================
    % 1) Input validalas
    % =====================================================================
    local_validate_inputs(cfg, evalCfg);

    % =====================================================================
    % 2) DB betoltes
    % =====================================================================
    DB = local_load_candidate_database(evalCfg.input.resultFilePath);

    if ~isfield(DB, 'candidateTable')
        error('A betoltott DB nem tartalmaz candidateTable mezot.');
    end

    Traw = DB.candidateTable;

    if isempty(Traw) || height(Traw) == 0
        error('A DB.candidateTable ures.');
    end

    % =====================================================================
    % 3) Sikeres candidate-ek szurese
    % =====================================================================
    requiredStatusColumns = {'wasSimulated', 'hasError'};
    local_require_table_columns(Traw, requiredStatusColumns, 'DB.candidateTable');

    validMask = logical(Traw.wasSimulated) & ~logical(Traw.hasError);

    if ~any(validMask)
        error('Nincs sikeresen lefutott candidate a candidateTable-ben.');
    end

    T = Traw(validMask, :);

    % =====================================================================
    % 4) Szükséges oszlopok ellenőrzése
    % =====================================================================
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
        'maxGridImportPeak_kW', ...
        'maxGridImportNoBessPeak_kW'};

    local_require_table_columns(T, requiredColumns, 'filtered candidateTable');

    % =====================================================================
    % 5) Rendezés BESS/PV arány szerint
    % =====================================================================
    T = sortrows(T, 'BESS_PV_ratio');

    % =====================================================================
    % 6) Baseline candidate ellenőrzése
    % =====================================================================
    baselineMask = abs(T.BESS_PV_ratio) < 1e-12;

    if ~any(baselineMask)
        error(['Az evaluation-hoz kell egy sikeresen lefutott baseline candidate: ', ...
               'BESS_PV_ratio = 0.']);
    end

    if sum(baselineMask) > 1
        error('Tobb BESS_PV_ratio = 0 baseline candidate talalhato. Ez nem egyertelmu.');
    end

    baselineRow = T(baselineMask, :);

    % =====================================================================
    % 7) Szarmaztatott energetikai es peak mutatok
    % =====================================================================
    T = local_add_technical_derived_metrics(T);

    % =====================================================================
    % 8) Gazdasagi mutatok szamitasa
    % =====================================================================
    T = local_add_economic_metrics(T, baselineRow, cfg, evalCfg);

    % =====================================================================
    % 9) Legjobb candidate kivalasztasa
    % =====================================================================
    [bestIdx, selectionInfo] = local_select_best_candidate(T, evalCfg);
    bestCandidate = T(bestIdx, :);

    % =====================================================================
    % 10) Riport tablazatok
    % =====================================================================
    keyMetricsTable = local_build_key_metrics_table(baselineRow, bestCandidate);
    bestCandidateTable = bestCandidate;

    % =====================================================================
    % 11) Kimeneti mappa
    % =====================================================================
    outputFolder = evalCfg.output.baseFolder;

    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    tableFolder = fullfile(outputFolder, 'tables');

    if ~exist(tableFolder, 'dir')
        mkdir(tableFolder);
    end

    figureFolder = fullfile(outputFolder, 'figures');

    if ~exist(figureFolder, 'dir')
        mkdir(figureFolder);
    end

    % =====================================================================
    % 12) MATLAB table mentesek
    % =====================================================================
    if evalCfg.output.saveReportTables

        writetable(T, fullfile(tableFolder, 'evaluation_candidate_economics_table.csv'));
        writetable(bestCandidateTable, fullfile(tableFolder, 'best_candidate_table.csv'));
        writetable(keyMetricsTable, fullfile(tableFolder, 'key_metrics_table.csv'));

        save(fullfile(tableFolder, 'evaluation_tables.mat'), ...
            'T', ...
            'bestCandidateTable', ...
            'keyMetricsTable');
    end

    if evalCfg.output.saveEvaluationCsv
        writetable(T, fullfile(outputFolder, 'evaluation_candidate_economics_table.csv'));
    end

    % =====================================================================
    % 13) Abrak
    % =====================================================================
    figureHandles = struct();

    if evalCfg.plots.makePlots

        figureHandles.costComponents = local_plot_cost_components(T, bestCandidate, figureFolder);

        figureHandles.lifecycleEconomics = local_plot_lifecycle_economics( ...
            T, bestCandidate, figureFolder);

        figureHandles.contractAndPeak = local_plot_contract_and_peak( ...
            T, bestCandidate, figureFolder);

        figureHandles.energyAndSavings = local_plot_energy_and_savings( ...
            T, bestCandidate, figureFolder);

        figureHandles.bessUtilization = local_plot_bess_utilization( ...
            T, bestCandidate, figureFolder);
    end

    % =====================================================================
    % 14) evaluationResult
    % =====================================================================
    evaluationResult = struct();

    evaluationResult.createdAt = datetime('now');
    evaluationResult.inputFile = evalCfg.input.resultFilePath;
    evaluationResult.selectionInfo = selectionInfo;

    evaluationResult.candidateEconomicsTable = T;
    evaluationResult.bestCandidateTable = bestCandidateTable;
    evaluationResult.keyMetricsTable = keyMetricsTable;

    evaluationResult.bestCandidate = table2struct(bestCandidate);
    evaluationResult.figureHandles = figureHandles;

    evaluationResult.baselineCandidate = table2struct(baselineRow);

    % =====================================================================
    % 15) Evaluation .mat mentes
    % =====================================================================
    if evalCfg.output.saveEvaluationMat

        save(fullfile(outputFolder, 'evaluation_result.mat'), ...
            'evaluationResult', ...
            '-v7.3');
    end

    % =====================================================================
    % 16) Konzolos osszefoglalo
    % =====================================================================
    fprintf('\n================ EVALUATION SUMMARY ================\n');
    fprintf('Input file: %s\n', evalCfg.input.resultFilePath);
    fprintf('Valid candidates: %d\n', height(T));
    fprintf('Selection mode: %s\n', string(evalCfg.selection.mode));

    fprintf('\nBest candidate:\n');
    fprintf('  BESS/PV ratio:                %.3f\n', bestCandidate.BESS_PV_ratio);
    fprintf('  E_BESS:                       %.2f kWh\n', bestCandidate.E_BESS_kWh);
    fprintf('  P_BESS:                       %.2f kW\n', bestCandidate.P_BESS_kW);
    fprintf('  Best contract:                %.2f kW\n', bestCandidate.bestContract_kW);
    fprintf('  Objective cost:               %.2f million HUF\n', bestCandidate.objectiveCost_HUF / 1e6);
    fprintf('  Total lifecycle cost:         %.2f million HUF\n', bestCandidate.totalLifecycleCost_HUF / 1e6);
    fprintf('  NPV vs baseline:              %.2f million HUF\n', bestCandidate.NPV_HUF / 1e6);
    fprintf('  Peak reduction:               %.2f %%\n', bestCandidate.peakReduction_pct);
    fprintf('  Equivalent cycles:            %.2f\n', bestCandidate.equivalentCycles);
    fprintf('====================================================\n');
end


% =========================================================================
% INPUT VALIDATION
% =========================================================================
function local_validate_inputs(cfg, evalCfg)

    if nargin < 1 || isempty(cfg)
        error('Hiányzó bemenet: cfg.');
    end

    if nargin < 2 || isempty(evalCfg)
        error('Hiányzó bemenet: evalCfg.');
    end

    requiredCfgFields = {'cost'};
    local_require_struct_fields(cfg, requiredCfgFields, 'cfg');

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

    local_require_struct_fields(evalCfg.input, {'resultFilePath'}, 'evalCfg.input');

    requiredOutputFields = { ...
        'baseFolder', ...
        'saveEvaluationMat', ...
        'saveEvaluationCsv', ...
        'saveReportTables'};

    local_require_struct_fields(evalCfg.output, requiredOutputFields, 'evalCfg.output');

    local_require_struct_fields(evalCfg.plots, {'makePlots'}, 'evalCfg.plots');

    local_require_struct_fields(evalCfg.selection, {'mode'}, 'evalCfg.selection');

    requiredEconomicsFields = { ...
        'simYears', ...
        'projectLifetime_years', ...
        'discountRate'};

    local_require_struct_fields(evalCfg.economics, requiredEconomicsFields, 'evalCfg.economics');

    if ~isfile(evalCfg.input.resultFilePath)
        error('Az evaluation input file nem letezik: %s', evalCfg.input.resultFilePath);
    end

    if evalCfg.economics.simYears <= 0
        error('evalCfg.economics.simYears legyen pozitiv.');
    end

    if evalCfg.economics.projectLifetime_years <= 0
        error('evalCfg.economics.projectLifetime_years legyen pozitiv.');
    end

    if evalCfg.economics.discountRate < 0
        error('evalCfg.economics.discountRate nem lehet negativ.');
    end
end


function local_require_struct_fields(S, fieldNames, structName)

    for i = 1:numel(fieldNames)

        f = fieldNames{i};

        if ~isfield(S, f)
            error('Hiányzó mező: %s.%s', structName, f);
        end
    end
end


% =========================================================================
% LOAD DB
% =========================================================================
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

    error(['A MAT file nem tartalmaz DB vagy configurationDatabase valtozot: ', ...
           '%s'], resultFilePath);
end


% =========================================================================
% TABLE VALIDATION
% =========================================================================
function local_require_table_columns(T, requiredColumns, tableName)

    varNames = T.Properties.VariableNames;

    for i = 1:numel(requiredColumns)

        col = requiredColumns{i};

        if ~ismember(col, varNames)
            error('A(z) %s nem tartalmazza a szukseges oszlopot: %s', ...
                tableName, col);
        end
    end
end


% =========================================================================
% TECHNICAL DERIVED METRICS
% =========================================================================
function T = local_add_technical_derived_metrics(T)

    if any(T.gridImportNoBess_kWh <= 0)
        error('gridImportNoBess_kWh nem lehet nulla vagy negativ a szazalekos csokkenteshez.');
    end

    if any(T.maxGridImportNoBessPeak_kW <= 0)
        error('maxGridImportNoBessPeak_kW nem lehet nulla vagy negativ a peak csokkenteshez.');
    end

    T.gridImportReduction_kWh = T.gridImportNoBess_kWh - T.gridImport_kWh;

    T.gridImportReduction_pct = ...
        100 * T.gridImportReduction_kWh ./ T.gridImportNoBess_kWh;

    T.peakReduction_kW = ...
        T.maxGridImportNoBessPeak_kW - T.maxGridImportPeak_kW;

    T.peakReduction_pct = ...
        100 * T.peakReduction_kW ./ T.maxGridImportNoBessPeak_kW;

    T.energyCostSaving_HUF = ...
        T.energyCostNoBess_HUF - T.energyCost_HUF;

    T.equivalentCycles = zeros(height(T), 1);

    nonzeroBess = T.E_BESS_kWh > 0;

    T.equivalentCycles(nonzeroBess) = ...
        T.bessThroughput_kWh(nonzeroBess) ./ ...
        (2 * T.E_BESS_kWh(nonzeroBess));

    T.equivalentCycles(~nonzeroBess) = 0;
end


% =========================================================================
% ECONOMIC METRICS
% =========================================================================
function T = local_add_economic_metrics(T, baselineRow, cfg, evalCfg)

    simYears = evalCfg.economics.simYears;
    projectLifetime_years = evalCfg.economics.projectLifetime_years;
    discountRate = evalCfg.economics.discountRate;

    % ---------------------------------------------------------------------
    % CAPEX
    % ---------------------------------------------------------------------
    T.capexPV_HUF = T.P_PV_kW .* cfg.cost.pv_huf_per_kWp;

    T.capexBESS_HUF = ...
        T.E_BESS_kWh .* cfg.cost.bess_huf_per_kWh + ...
        T.P_BESS_kW .* cfg.cost.bess_power_huf_per_kW;

    T.capexInverter_HUF = ...
        T.P_inv_kW .* cfg.cost.inverter_huf_per_kW;

    T.initialCapex_HUF = ...
        T.capexPV_HUF + ...
        T.capexBESS_HUF + ...
        T.capexInverter_HUF;

    % ---------------------------------------------------------------------
    % Annualized simulated operation
    % ---------------------------------------------------------------------
    T.annualObjectiveCost_HUF = T.objectiveCost_HUF ./ simYears;

    T.annualEnergyCost_HUF = T.energyCost_HUF ./ simYears;
    T.annualContractCost_HUF = T.contractCost_HUF ./ simYears;
    T.annualOverrunCost_HUF = T.overrunCost_HUF ./ simYears;
    T.annualDegradationCost_HUF = T.degradationCost_HUF ./ simYears;

    T.annualEnergyCostNoBess_HUF = T.energyCostNoBess_HUF ./ simYears;

    % ---------------------------------------------------------------------
    % OPEX
    % ---------------------------------------------------------------------
    T.annualPV_OPEX_HUF = ...
        T.capexPV_HUF .* cfg.cost.pv_opex_frac_per_year;

    T.annualBESS_OPEX_HUF = ...
        T.capexBESS_HUF .* cfg.cost.bess_opex_frac_per_year;

    T.annualInverter_OPEX_HUF = ...
        T.capexInverter_HUF .* cfg.cost.inverter_opex_frac_per_year;

    T.annualOPEX_HUF = ...
        T.annualPV_OPEX_HUF + ...
        T.annualBESS_OPEX_HUF + ...
        T.annualInverter_OPEX_HUF;

    T.annualSystemCost_HUF = ...
        T.annualObjectiveCost_HUF + ...
        T.annualOPEX_HUF;

    % ---------------------------------------------------------------------
    % Baseline
    % ---------------------------------------------------------------------
    baselineCapexPV_HUF = baselineRow.P_PV_kW * cfg.cost.pv_huf_per_kWp;

    baselineCapexBESS_HUF = ...
        baselineRow.E_BESS_kWh * cfg.cost.bess_huf_per_kWh + ...
        baselineRow.P_BESS_kW * cfg.cost.bess_power_huf_per_kW;

    baselineCapexInverter_HUF = ...
        baselineRow.P_inv_kW * cfg.cost.inverter_huf_per_kW;

    baselineInitialCapex_HUF = ...
        baselineCapexPV_HUF + ...
        baselineCapexBESS_HUF + ...
        baselineCapexInverter_HUF;

    baselineAnnualPV_OPEX_HUF = ...
        baselineCapexPV_HUF * cfg.cost.pv_opex_frac_per_year;

    baselineAnnualBESS_OPEX_HUF = ...
        baselineCapexBESS_HUF * cfg.cost.bess_opex_frac_per_year;

    baselineAnnualInverter_OPEX_HUF = ...
        baselineCapexInverter_HUF * cfg.cost.inverter_opex_frac_per_year;

    baselineAnnualOPEX_HUF = ...
        baselineAnnualPV_OPEX_HUF + ...
        baselineAnnualBESS_OPEX_HUF + ...
        baselineAnnualInverter_OPEX_HUF;

    baselineAnnualObjectiveCost_HUF = ...
        baselineRow.objectiveCost_HUF / simYears;

    baselineAnnualSystemCost_HUF = ...
        baselineAnnualObjectiveCost_HUF + ...
        baselineAnnualOPEX_HUF;

    baselineTotalLifecycleCost_HUF = ...
        baselineInitialCapex_HUF + ...
        local_present_value_annuity( ...
            baselineAnnualSystemCost_HUF, ...
            discountRate, ...
            projectLifetime_years);

    % ---------------------------------------------------------------------
    % Incremental economics vs baseline
    % ---------------------------------------------------------------------
    T.incrementalCapex_HUF = ...
        T.initialCapex_HUF - baselineInitialCapex_HUF;

    T.incrementalAnnualOPEX_HUF = ...
        T.annualOPEX_HUF - baselineAnnualOPEX_HUF;

    T.annualGrossOperationalSaving_HUF = ...
        baselineAnnualObjectiveCost_HUF - T.annualObjectiveCost_HUF;

    T.annualNetSaving_HUF = ...
        baselineAnnualSystemCost_HUF - T.annualSystemCost_HUF;

    T.NPV_HUF = ...
        -T.incrementalCapex_HUF + ...
        local_present_value_annuity( ...
            T.annualNetSaving_HUF, ...
            discountRate, ...
            projectLifetime_years);

    T.totalLifecycleCost_HUF = ...
        T.initialCapex_HUF + ...
        local_present_value_annuity( ...
            T.annualSystemCost_HUF, ...
            discountRate, ...
            projectLifetime_years);

    T.lifecycleCostSaving_HUF = ...
        baselineTotalLifecycleCost_HUF - T.totalLifecycleCost_HUF;

    T.discountedPayback_years = ...
        local_discounted_payback( ...
            T.incrementalCapex_HUF, ...
            T.annualNetSaving_HUF, ...
            discountRate, ...
            projectLifetime_years);

    T.simplePayback_years = ...
        local_simple_payback( ...
            T.incrementalCapex_HUF, ...
            T.annualNetSaving_HUF);

    % ---------------------------------------------------------------------
    % Report-friendly units
    % ---------------------------------------------------------------------
    T.initialCapex_millionHUF = T.initialCapex_HUF / 1e6;
    T.incrementalCapex_millionHUF = T.incrementalCapex_HUF / 1e6;
    T.objectiveCost_millionHUF = T.objectiveCost_HUF / 1e6;
    T.totalLifecycleCost_millionHUF = T.totalLifecycleCost_HUF / 1e6;
    T.lifecycleCostSaving_millionHUF = T.lifecycleCostSaving_HUF / 1e6;
    T.NPV_millionHUF = T.NPV_HUF / 1e6;
    T.annualNetSaving_millionHUF = T.annualNetSaving_HUF / 1e6;
end


function pv = local_present_value_annuity(annualValue, discountRate, years)

    if years <= 0
        error('A present value annuity years parametere legyen pozitiv.');
    end

    if discountRate < 0
        error('A discountRate nem lehet negativ.');
    end

    if discountRate == 0
        pv = annualValue .* years;
    else
        annuityFactor = (1 - (1 + discountRate)^(-years)) / discountRate;
        pv = annualValue .* annuityFactor;
    end
end


function payback = local_simple_payback(incrementalCapex, annualSaving)

    payback = inf(size(incrementalCapex));

    positiveSaving = annualSaving > 0;

    payback(positiveSaving) = ...
        incrementalCapex(positiveSaving) ./ annualSaving(positiveSaving);

    baselineOrNegativeCapex = incrementalCapex <= 0 & annualSaving >= 0;

    payback(baselineOrNegativeCapex) = 0;
end


function payback = local_discounted_payback( ...
    incrementalCapex, annualSaving, discountRate, projectLifetime_years)

    payback = inf(size(incrementalCapex));

    for i = 1:numel(incrementalCapex)

        if incrementalCapex(i) <= 0 && annualSaving(i) >= 0
            payback(i) = 0;
            continue;
        end

        if annualSaving(i) <= 0
            payback(i) = inf;
            continue;
        end

        cumulativePV = 0;

        for y = 1:projectLifetime_years

            discountedSaving = annualSaving(i) / (1 + discountRate)^y;
            cumulativePV = cumulativePV + discountedSaving;

            if cumulativePV >= incrementalCapex(i)

                previousPV = cumulativePV - discountedSaving;
                missing = incrementalCapex(i) - previousPV;

                if discountedSaving <= 0
                    payback(i) = y;
                else
                    payback(i) = (y - 1) + missing / discountedSaving;
                end

                break;
            end
        end
    end
end


% =========================================================================
% BEST CANDIDATE SELECTION
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

        case "minObjectiveCost"

            [bestValue, bestIdx] = min(T.objectiveCost_HUF);
            selectedField = "objectiveCost_HUF";

        case "maxLifecycleCostSaving"

            [bestValue, bestIdx] = max(T.lifecycleCostSaving_HUF);
            selectedField = "lifecycleCostSaving_HUF";

        otherwise

            error(['Ismeretlen evalCfg.selection.mode: %s. ', ...
                   'Hasznalhato: minTotalLifecycleCost, maxNPV, ', ...
                   'minObjectiveCost, maxLifecycleCostSaving.'], mode);
    end

    selectionInfo = struct();
    selectionInfo.mode = mode;
    selectionInfo.selectedField = selectedField;
    selectionInfo.bestValue = bestValue;
    selectionInfo.bestIdxInFilteredTable = bestIdx;
end


% =========================================================================
% REPORT TABLES
% =========================================================================
function keyMetricsTable = local_build_key_metrics_table(baselineRow, bestCandidate)

    metricNames = strings(0, 1);
    units = strings(0, 1);
    baselineValues = [];
    bestValues = [];

    [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
        metricNames, units, baselineValues, bestValues, ...
        "BESS/PV arany", "-", ...
        baselineRow.BESS_PV_ratio, bestCandidate.BESS_PV_ratio);

    [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
        metricNames, units, baselineValues, bestValues, ...
        "BESS energia kapacitas", "kWh", ...
        baselineRow.E_BESS_kWh, bestCandidate.E_BESS_kWh);

    [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
        metricNames, units, baselineValues, bestValues, ...
        "BESS teljesitmeny", "kW", ...
        baselineRow.P_BESS_kW, bestCandidate.P_BESS_kW);

    [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
        metricNames, units, baselineValues, bestValues, ...
        "Optimalis lekotott teljesitmeny", "kW", ...
        baselineRow.bestContract_kW, bestCandidate.bestContract_kW);

    [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
        metricNames, units, baselineValues, bestValues, ...
        "Szimulalt idoszak objektiv koltsege", "million HUF", ...
        baselineRow.objectiveCost_HUF / 1e6, bestCandidate.objectiveCost_HUF / 1e6);

    [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
        metricNames, units, baselineValues, bestValues, ...
        "Teljes eletciklus koltseg", "million HUF", ...
        baselineRow.totalLifecycleCost_HUF / 1e6, bestCandidate.totalLifecycleCost_HUF / 1e6);

    [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
        metricNames, units, baselineValues, bestValues, ...
        "NPV baseline-hoz kepest", "million HUF", ...
        baselineRow.NPV_HUF / 1e6, bestCandidate.NPV_HUF / 1e6);

    [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
        metricNames, units, baselineValues, bestValues, ...
        "Eves netto megtakaritas", "million HUF/year", ...
        baselineRow.annualNetSaving_HUF / 1e6, bestCandidate.annualNetSaving_HUF / 1e6);

    [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
        metricNames, units, baselineValues, bestValues, ...
        "Peak csokkentes", "%", ...
        baselineRow.peakReduction_pct, bestCandidate.peakReduction_pct);

    [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
        metricNames, units, baselineValues, bestValues, ...
        "Grid import csokkentes", "%", ...
        baselineRow.gridImportReduction_pct, bestCandidate.gridImportReduction_pct);

    [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
        metricNames, units, baselineValues, bestValues, ...
        "Ekvivalens ciklusszam", "-", ...
        baselineRow.equivalentCycles, bestCandidate.equivalentCycles);

    keyMetricsTable = table( ...
        metricNames, ...
        units, ...
        baselineValues, ...
        bestValues, ...
        'VariableNames', { ...
            'Metric', ...
            'Unit', ...
            'BaselineValue', ...
            'BestCandidateValue'});
end


function [metricNames, units, baselineValues, bestValues] = local_add_metric_row( ...
    metricNames, units, baselineValues, bestValues, ...
    metricName, unitName, baselineValue, bestValue)

    metricNames(end+1, 1) = metricName;
    units(end+1, 1) = unitName;
    baselineValues(end+1, 1) = baselineValue;
    bestValues(end+1, 1) = bestValue;
end


% =========================================================================
% PLOTS
% =========================================================================
function fig = local_plot_cost_components(T, bestCandidate, figureFolder)

    x = T.BESS_PV_ratio;

    fig = figure('Name', 'Cost components vs BESS/PV ratio', ...
        'Position', [100, 80, 1300, 850]);

    tiledlayout(2, 1);

    nexttile;
    hold on;
    grid on;

    plot(x, T.objectiveCost_HUF / 1e6, '-o', 'LineWidth', 1.8, ...
        'DisplayName', 'Total objective');
    plot(x, T.energyCost_HUF / 1e6, '-s', 'LineWidth', 1.5, ...
        'DisplayName', 'Energy');
    plot(x, T.contractCost_HUF / 1e6, '-^', 'LineWidth', 1.5, ...
        'DisplayName', 'Contract');
    plot(x, T.degradationCost_HUF / 1e6, '-d', 'LineWidth', 1.5, ...
        'DisplayName', 'Degradation');
    plot(x, T.overrunCost_HUF / 1e6, '-x', 'LineWidth', 1.5, ...
        'DisplayName', 'Overrun');

    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, ...
        'DisplayName', 'Selected best');

    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Cost over simulated period [million HUF]');
    title('Szimulalt idoszak koltsegkomponensei');
    legend('Location', 'best');

    nexttile;
    hold on;
    grid on;

    plot(x, T.annualObjectiveCost_HUF / 1e6, '-o', 'LineWidth', 1.8, ...
        'DisplayName', 'Annual objective');
    plot(x, T.annualEnergyCost_HUF / 1e6, '-s', 'LineWidth', 1.5, ...
        'DisplayName', 'Annual energy');
    plot(x, T.annualContractCost_HUF / 1e6, '-^', 'LineWidth', 1.5, ...
        'DisplayName', 'Annual contract');
    plot(x, T.annualDegradationCost_HUF / 1e6, '-d', 'LineWidth', 1.5, ...
        'DisplayName', 'Annual degradation');
    plot(x, T.annualOverrunCost_HUF / 1e6, '-x', 'LineWidth', 1.5, ...
        'DisplayName', 'Annual overrun');

    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, ...
        'DisplayName', 'Selected best');

    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Annual cost [million HUF/year]');
    title('Evesitett koltsegkomponensek');
    legend('Location', 'best');

    local_save_figure(fig, figureFolder, 'cost_components_vs_bess_pv_ratio');
end


function fig = local_plot_lifecycle_economics(T, bestCandidate, figureFolder)

    x = T.BESS_PV_ratio;

    fig = figure('Name', 'Lifecycle economics vs BESS/PV ratio', ...
        'Position', [120, 100, 1300, 850]);

    tiledlayout(2, 1);

    nexttile;
    hold on;
    grid on;

    plot(x, T.totalLifecycleCost_HUF / 1e6, '-o', 'LineWidth', 1.8, ...
        'DisplayName', 'Total lifecycle cost');
    plot(x, T.initialCapex_HUF / 1e6, '-s', 'LineWidth', 1.5, ...
        'DisplayName', 'Initial CAPEX');
    plot(x, T.incrementalCapex_HUF / 1e6, '-^', 'LineWidth', 1.5, ...
        'DisplayName', 'Incremental CAPEX vs baseline');

    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, ...
        'DisplayName', 'Selected best');

    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Cost [million HUF]');
    title('Eletciklus koltseg es beruhazasi koltsegek');
    legend('Location', 'best');

    nexttile;
    hold on;
    grid on;

    plot(x, T.NPV_HUF / 1e6, '-o', 'LineWidth', 1.8, ...
        'DisplayName', 'NPV vs baseline');
    plot(x, T.lifecycleCostSaving_HUF / 1e6, '-s', 'LineWidth', 1.5, ...
        'DisplayName', 'Lifecycle cost saving');
    plot(x, T.annualNetSaving_HUF / 1e6, '-^', 'LineWidth', 1.5, ...
        'DisplayName', 'Annual net saving');

    yline(0, 'k--', 'LineWidth', 1.0, 'DisplayName', 'Zero');
    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, ...
        'DisplayName', 'Selected best');

    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Value [million HUF]');
    title('NPV es megtakaritasi mutatok');
    legend('Location', 'best');

    local_save_figure(fig, figureFolder, 'lifecycle_economics_vs_bess_pv_ratio');
end


function fig = local_plot_contract_and_peak(T, bestCandidate, figureFolder)

    x = T.BESS_PV_ratio;

    fig = figure('Name', 'Contract and peak metrics vs BESS/PV ratio', ...
        'Position', [140, 120, 1300, 850]);

    tiledlayout(2, 1);

    nexttile;
    hold on;
    grid on;

    plot(x, T.bestContract_kW, '-o', 'LineWidth', 1.8, ...
        'DisplayName', 'Optimal contract');
    plot(x, T.maxGridImportPeak_kW, '-s', 'LineWidth', 1.5, ...
        'DisplayName', 'Max grid import with BESS');
    plot(x, T.maxGridImportNoBessPeak_kW, '-^', 'LineWidth', 1.5, ...
        'DisplayName', 'Max grid import no BESS');

    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, ...
        'DisplayName', 'Selected best');

    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Power [kW]');
    title('Contract es peak teljesitmenyek');
    legend('Location', 'best');

    nexttile;
    hold on;
    grid on;

    plot(x, T.peakReduction_kW, '-o', 'LineWidth', 1.8, ...
        'DisplayName', 'Peak reduction');
    plot(x, T.peakReduction_pct, '-s', 'LineWidth', 1.5, ...
        'DisplayName', 'Peak reduction percent');

    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, ...
        'DisplayName', 'Selected best');

    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Reduction [kW] / [%]');
    title('Peak shaving hatas');
    legend('Location', 'best');

    local_save_figure(fig, figureFolder, 'contract_and_peak_vs_bess_pv_ratio');
end


function fig = local_plot_energy_and_savings(T, bestCandidate, figureFolder)

    x = T.BESS_PV_ratio;

    fig = figure('Name', 'Energy and savings vs BESS/PV ratio', ...
        'Position', [160, 140, 1300, 850]);

    tiledlayout(2, 1);

    nexttile;
    hold on;
    grid on;

    plot(x, T.gridImport_kWh / 1000, '-o', 'LineWidth', 1.8, ...
        'DisplayName', 'Grid import with BESS');
    plot(x, T.gridImportNoBess_kWh / 1000, '-s', 'LineWidth', 1.5, ...
        'DisplayName', 'Grid import no BESS');
    plot(x, T.gridImportReduction_kWh / 1000, '-^', 'LineWidth', 1.5, ...
        'DisplayName', 'Grid import reduction');

    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, ...
        'DisplayName', 'Selected best');

    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Energy [MWh]');
    title('Halozati energiaigeny es csokkentes');
    legend('Location', 'best');

    nexttile;
    hold on;
    grid on;

    plot(x, T.energyCost_HUF / 1e6, '-o', 'LineWidth', 1.8, ...
        'DisplayName', 'Energy cost with BESS');
    plot(x, T.energyCostNoBess_HUF / 1e6, '-s', 'LineWidth', 1.5, ...
        'DisplayName', 'Energy cost no BESS');
    plot(x, T.energyCostSaving_HUF / 1e6, '-^', 'LineWidth', 1.5, ...
        'DisplayName', 'Energy cost saving');

    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, ...
        'DisplayName', 'Selected best');

    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Cost [million HUF]');
    title('Energiakoltseg es energiakoltseg-megtakaritas');
    legend('Location', 'best');

    local_save_figure(fig, figureFolder, 'energy_and_savings_vs_bess_pv_ratio');
end


function fig = local_plot_bess_utilization(T, bestCandidate, figureFolder)

    x = T.BESS_PV_ratio;

    fig = figure('Name', 'BESS utilization vs BESS/PV ratio', ...
        'Position', [180, 160, 1300, 850]);

    tiledlayout(2, 1);

    nexttile;
    hold on;
    grid on;

    plot(x, T.E_BESS_kWh, '-o', 'LineWidth', 1.8, ...
        'DisplayName', 'E_BESS');
    plot(x, T.P_BESS_kW, '-s', 'LineWidth', 1.5, ...
        'DisplayName', 'P_BESS');

    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, ...
        'DisplayName', 'Selected best');

    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('BESS size [kWh] / [kW]');
    title('BESS meretek');
    legend('Location', 'best');

    nexttile;
    hold on;
    grid on;

    plot(x, T.bessThroughput_kWh / 1000, '-o', 'LineWidth', 1.8, ...
        'DisplayName', 'BESS throughput');
    plot(x, T.equivalentCycles, '-s', 'LineWidth', 1.5, ...
        'DisplayName', 'Equivalent cycles');

    if ismember('finalSoH', T.Properties.VariableNames)
        plot(x, T.finalSoH * 100, '-^', 'LineWidth', 1.5, ...
            'DisplayName', 'Final SoH [%]');
    end

    xline(bestCandidate.BESS_PV_ratio, '--', 'LineWidth', 1.5, ...
        'DisplayName', 'Selected best');

    xlabel('BESS/PV ratio [kWh/kWp]');
    ylabel('Throughput [MWh] / cycles / SoH [%]');
    title('BESS kihasznaltsag es degradacios allapot');
    legend('Location', 'best');

    local_save_figure(fig, figureFolder, 'bess_utilization_vs_bess_pv_ratio');
end


function local_save_figure(fig, figureFolder, fileTag)

    figPath = fullfile(figureFolder, [fileTag, '.fig']);
    pngPath = fullfile(figureFolder, [fileTag, '.png']);

    savefig(fig, figPath);
    saveas(fig, pngPath);
end