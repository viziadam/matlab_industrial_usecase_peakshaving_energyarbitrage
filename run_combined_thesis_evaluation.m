function evalResult = run_combined_thesis_evaluation(basePath)
% RUN_COMBINED_THESIS_EVALUATION
%
% Csak a combined mukodesi mod dolgozati kiertekeleset kesziti el a mentett
% AC/DC candidate eredmenyekbol.
%
% Nem keszit "legjobb DC / legjobb AC / noBESS" report abrakat.
% A teljes BESS/PV merethalot mutatja.
%
% Hasznalat:
%   evalResult = run_combined_thesis_evaluation();
%   evalResult = run_combined_thesis_evaluation(pwd);
%
% Fontos:
%   A fo teljesitmeny- es gazdasagi abrak regi eredmenyekbol is elkeszulnek.
%   Az energiaaramlasi es veszteseg abrakhoz a combined futast az uj
%   metrikamentesi logikaval kell lefuttatni:
%       run_all_topologies_for_mode("combined", [])

    if nargin < 1 || isempty(basePath)
        basePath = fileparts(mfilename('fullpath'));
    end

    cfg = create_configurations(basePath);
    cfg.dispatch.objectiveMode = "combined";
    cfg = add_energy_only_evaluation_metrics_to_cfg(cfg);

    resultRoot = fullfile(cfg.paths.results, 'combined');
    outputFolder = fullfile(resultRoot, 'evaluation_combined_thesis');

    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    dcPath = fullfile(resultRoot, 'results_dc_combined.mat');
    acPath = fullfile(resultRoot, 'results_ac_combined.mat');

    if ~isfile(dcPath)
        error('Missing DC result file: %s', dcPath);
    end

    if ~isfile(acPath)
        error('Missing AC result file: %s', acPath);
    end

    Tdc = local_load_candidate_table(dcPath, "dc");
    Tac = local_load_candidate_table(acPath, "ac");

    T = [Tdc; Tac];
    T = local_add_thesis_economics(T, cfg);

    noBessRow = local_select_no_bess_row(T);
    T = local_add_no_bess_savings(T, noBessRow, cfg);

    validMask = logical(T.wasSimulated) & ...
                ~logical(T.hasError) & ...
                isfinite(T.netAnnualSavingVsNoBess_HUF_per_year);

    validTable = T(validMask, :);

    writetable(T, fullfile(outputFolder, 'combined_all_candidates.csv'));
    writetable(validTable, fullfile(outputFolder, 'combined_valid_candidates.csv'));

    figs = plot_combined_thesis_evaluation(validTable, cfg, outputFolder);

    evalResult = struct();
    evalResult.cfg = cfg;
    evalResult.tableAll = T;
    evalResult.validTable = validTable;
    evalResult.noBessRow = noBessRow;
    evalResult.outputFolder = outputFolder;
    evalResult.figures = figs;

    save(fullfile(outputFolder, 'combined_thesis_evaluation_result.mat'), ...
        'evalResult', ...
        '-v7.3');

    fprintf('\nCombined thesis evaluation saved:\n%s\n', outputFolder);
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


function T = local_add_thesis_economics(T, cfg)

    local_require_columns(T, { ...
        'E_BESS_kWh', ...
        'P_BESS_kW', ...
        'objectiveCost_HUF', ...
        'degradationCost_HUF', ...
        'energyCost_HUF', ...
        'contractCost_HUF', ...
        'overrunCost_HUF', ...
        'finalSoH'});

    simYears = cfg.analysis.simYears;

    capexBess = ...
        T.E_BESS_kWh .* cfg.cost.bess_huf_per_kWh + ...
        T.P_BESS_kW .* cfg.cost.bess_power_huf_per_kW;

    opexBessAnnual = capexBess .* cfg.cost.bess_opex_frac_per_year;

    finalSoH = T.finalSoH;
    finalSoH(~isfinite(finalSoH)) = 1;

    deltaSoHTotal = max(0, 1 - finalSoH);
    deltaSoHAnnualEq = deltaSoHTotal ./ simYears;

    bessSohCapexAnnual = (deltaSoHAnnualEq ./ 0.2) .* capexBess;
    bessAnnualCapexOpex = bessSohCapexAnnual + opexBessAnnual;
    bessCapexOpexTotal = simYears .* bessAnnualCapexOpex;

    zeroMask = T.E_BESS_kWh <= 0 | T.P_BESS_kW <= 0;

    capexBess(zeroMask) = 0;
    opexBessAnnual(zeroMask) = 0;
    deltaSoHTotal(zeroMask) = 0;
    deltaSoHAnnualEq(zeroMask) = 0;
    bessSohCapexAnnual(zeroMask) = 0;
    bessAnnualCapexOpex(zeroMask) = 0;
    bessCapexOpexTotal(zeroMask) = 0;

    T.bessCapex_HUF = capexBess;
    T.bessOpexAnnual_HUF = opexBessAnnual;
    T.deltaSoHTotal = deltaSoHTotal;
    T.deltaSoHAnnualEq = deltaSoHAnnualEq;
    T.bessSohCapexAnnual_HUF = bessSohCapexAnnual;
    T.bessAnnualCapexOpex_HUF = bessAnnualCapexOpex;
    T.bessCapexOpexTotal_HUF = bessCapexOpexTotal;

    T.dispatchDegradationCost_HUF = T.degradationCost_HUF;
    T.operationalCostNoDispatchDeg_HUF = ...
        T.objectiveCost_HUF - T.degradationCost_HUF;
end


function noBessRow = local_select_no_bess_row(T)

    idx = find(abs(T.BESS_PV_ratio) < 1e-12, 1, 'first');

    if isempty(idx)
        error('No noBESS baseline candidate found: BESS_PV_ratio = 0.');
    end

    noBessRow = T(idx, :);
end


function T = local_add_no_bess_savings(T, noBessRow, cfg)

    simYears = cfg.analysis.simYears;

    noBessEnergy = noBessRow.energyCost_HUF(1);
    noBessContract = noBessRow.contractCost_HUF(1);
    noBessOverrun = noBessRow.overrunCost_HUF(1);
    noBessOperational = noBessRow.operationalCostNoDispatchDeg_HUF(1);

    if isfield(cfg, 'dispatch') && isfield(cfg.dispatch, 'noBessContract_kW')
        noBessContractReference = cfg.dispatch.noBessContract_kW;
    else
        noBessContractReference = noBessRow.bestContract_kW(1);
    end

    T.energySavingVsNoBess_HUF = noBessEnergy - T.energyCost_HUF;
    T.energySavingVsNoBess_HUF_per_year = ...
        T.energySavingVsNoBess_HUF ./ simYears;

    T.contractSavingVsNoBess_HUF = noBessContract - T.contractCost_HUF;
    T.overrunSavingVsNoBess_HUF = noBessOverrun - T.overrunCost_HUF;
    T.performanceSavingVsNoBess_HUF = ...
        T.contractSavingVsNoBess_HUF + T.overrunSavingVsNoBess_HUF;
    T.performanceSavingVsNoBess_HUF_per_year = ...
        T.performanceSavingVsNoBess_HUF ./ simYears;

    T.contractReductionVsNoBess_kW = noBessContractReference - T.bestContract_kW;
    T.contractReductionVsNoBess_pct = 100 .* local_safe_divide_vec( ...
        T.contractReductionVsNoBess_kW, ...
        noBessContractReference .* ones(height(T), 1));

    T.operationalSavingVsNoBess_HUF = ...
        noBessOperational - T.operationalCostNoDispatchDeg_HUF;

    T.netSavingVsNoBess_HUF = ...
        T.operationalSavingVsNoBess_HUF - T.bessCapexOpexTotal_HUF;

    T.netAnnualSavingVsNoBess_HUF_per_year = ...
        T.netSavingVsNoBess_HUF ./ simYears;

    zeroMask = T.E_BESS_kWh <= 0 | T.P_BESS_kW <= 0;

    T.energySavingVsNoBess_HUF(zeroMask) = 0;
    T.energySavingVsNoBess_HUF_per_year(zeroMask) = 0;
    T.contractSavingVsNoBess_HUF(zeroMask) = 0;
    T.overrunSavingVsNoBess_HUF(zeroMask) = 0;
    T.performanceSavingVsNoBess_HUF(zeroMask) = 0;
    T.performanceSavingVsNoBess_HUF_per_year(zeroMask) = 0;
    T.contractReductionVsNoBess_kW(zeroMask) = 0;
    T.contractReductionVsNoBess_pct(zeroMask) = 0;
    T.operationalSavingVsNoBess_HUF(zeroMask) = 0;
    T.netSavingVsNoBess_HUF(zeroMask) = 0;
    T.netAnnualSavingVsNoBess_HUF_per_year(zeroMask) = 0;
end


function y = local_safe_divide_vec(a, b)

    y = NaN(size(a));
    mask = isfinite(a) & isfinite(b) & abs(b) > 1e-12;
    y(mask) = a(mask) ./ b(mask);
end


function local_require_columns(T, colNames)

    for i = 1:numel(colNames)
        if ~ismember(colNames{i}, T.Properties.VariableNames)
            error('Missing required table column: %s', colNames{i});
        end
    end
end
