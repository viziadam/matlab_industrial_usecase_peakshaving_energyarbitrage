function out = run_ac_dc_fast_milp_comparison_test(objectiveMode, candidateList, monthIndex, opts)
% RUN_FAST_MILP_AC_DC_MONTH_TEST
%
% Command windowbol kozvetlenul hivhato havi AC/DC fast MILP teszt.
%
% Alapertelmezett:
%   - mindharom uzemmod: energy_only, peak_only, combined
%   - AC es DC topologia
%   - 30 nap
%   - production MILP vs fast LP/MILP
%   - terv + topologiai vegrehajtas osszehasonlitas
%
% Peldak:
%   out = run_fast_milp_ac_dc_month_test;
%   out = run_fast_milp_ac_dc_month_test("energy_only", 2, 1);
%   out = run_fast_milp_ac_dc_month_test("all", 2, 1);
%
% Gyors 7 napos teszt:
%   opts = struct();
%   opts.nDays = 7;
%   opts.plotWorstN = 2;
%   out = run_fast_milp_ac_dc_month_test("all", 2, 1, opts);

    if nargin < 1 || strlength(string(objectiveMode)) == 0
        objectiveMode = "all";
    end

    if nargin < 2
        candidateList = [];
    end

    if nargin < 3 || isempty(monthIndex)
        monthIndex = 1;
    end

    if nargin < 4 || isempty(opts)
        opts = struct();
    end

    objectiveMode = lower(string(objectiveMode));

    if objectiveMode == "all"
        objectiveModes = ["energy_only", "peak_only", "combined"];
    else
        objectiveModes = objectiveMode;
    end

    validModes = ["energy_only", "peak_only", "combined"];

    for i = 1:numel(objectiveModes)
        if ~any(objectiveModes(i) == validModes)
            error('Invalid objectiveMode: %s', objectiveModes(i));
        end
    end

    if numel(monthIndex) ~= 1
        error('monthIndex must be scalar. Use opts.dayList for explicit day lists.');
    end

    opts = local_set_default(opts, 'nDays', 30);
    opts = local_set_default(opts, 'nRepeat', 1);
    opts = local_set_default(opts, 'makePlots', true);
    opts = local_set_default(opts, 'saveResult', true);
    opts = local_set_default(opts, 'validationTol_kW', 1e-5);
    opts = local_set_default(opts, 'lpSimultaneousPowerTolerance_kW', 1e-5);
    opts = local_set_default(opts, 'runTopologyExecution', true);
    opts = local_set_default(opts, 'plotWorstN', 2);
    opts = local_set_default(opts, 'plotOnlyWorstCases', true);

    basePath = fileparts(mfilename('fullpath'));

    allModeOutputs = cell(numel(objectiveModes), 1);
    allTables = cell(numel(objectiveModes), 1);

    for m = 1:numel(objectiveModes)

        mode = objectiveModes(m);

        cfg = create_configurations(basePath);
        cfg.dispatch.objectiveMode = mode;
        cfg.paths.results = fullfile(cfg.paths.results, char(mode));

        if isfield(opts, 'dayList') && ~isempty(opts.dayList)
            dayList = opts.dayList(:).';
        else
            startDay = (monthIndex - 1) * opts.nDays + 1;
            dayList = startDay:(startDay + opts.nDays - 1);
        end

        couplingList = ["dc", "ac"];

        fprintf('\n====================================================\n');
        fprintf('Fast MILP AC/DC monthly test\n');
        fprintf('Objective mode : %s\n', mode);
        fprintf('Candidate list : %s\n', mat2str(candidateList));
        fprintf('Month index    : %d\n', monthIndex);
        fprintf('Day list       : %s\n', mat2str(dayList));
        fprintf('nRepeat        : %d\n', opts.nRepeat);
        fprintf('====================================================\n');

        modeOut = milp_fast_test_environment( ...
            cfg, ...
            mode, ...
            couplingList, ...
            candidateList, ...
            dayList, ...
            opts);

        modeOut.monthIndex = monthIndex;

        allModeOutputs{m} = modeOut;
        allTables{m} = modeOut.summaryTable;
    end

    out = struct();
    out.objectiveModes = objectiveModes;
    out.monthIndex = monthIndex;
    out.modeOutputs = allModeOutputs;
    out.summaryTable = vertcat(allTables{:});
    out.statistics = local_build_global_statistics(out.summaryTable);

    if opts.saveResult
        cfgSave = create_configurations(basePath);
        resultDir = fullfile(cfgSave.paths.results, 'milp_fast_test_all_modes');

        if ~exist(resultDir, 'dir')
            mkdir(resultDir);
        end

        stamp = datestr(now, 'yyyymmdd_HHMMSS');

        out.savePath = fullfile(resultDir, ...
            sprintf('milp_fast_test_all_modes_m%d_%s.mat', monthIndex, stamp));

        out.csvPath = fullfile(resultDir, ...
            sprintf('milp_fast_test_all_modes_m%d_%s.csv', monthIndex, stamp));

        save(out.savePath, 'out', '-v7.3');
        writetable(out.summaryTable, out.csvPath);
    else
        out.savePath = "";
        out.csvPath = "";
    end

    local_print_global_summary(out);
end


function opts = local_set_default(opts, fieldName, defaultValue)

    if ~isfield(opts, fieldName) || isempty(opts.(fieldName))
        opts.(fieldName) = defaultValue;
    end
end


function stats = local_build_global_statistics(T)

    stats = struct();

    stats.nRows = height(T);
    stats.nFeasibleBoth = sum(T.isFeasibleBoth);
    stats.nObjectiveEquivalent = sum(T.isObjectiveEquivalent);
    stats.nSafeDropInReplacement = sum(T.isSafeDropInReplacement);
    stats.nAlternativeOptimalPlan = sum(T.isAlternativeOptimalPlan);
    stats.nFastLpAccepted = sum(T.fastLpAccepted);
    stats.nFallback = sum(T.fastSolver == "milp_fallback_current_production");

    stats.meanSpeedup = mean(T.runtimeSpeedupFactor, 'omitnan');
    stats.maxObjectiveRelDiff_pct = max(abs(T.objectiveRelDiff_pct), [], 'omitnan');

    stats.maxAppliedGridDiff_kW = max(T.maxAbsDiffApplied_P_grid_plan, [], 'omitnan');
    stats.maxAppliedChargeDiff_kW = max(T.maxAbsDiffApplied_P_ch_plan, [], 'omitnan');
    stats.maxAppliedDischargeDiff_kW = max(T.maxAbsDiffApplied_P_dis_plan, [], 'omitnan');
    stats.maxAppliedSoCDiff = max(T.maxAbsDiffApplied_SoC_plan, [], 'omitnan');

    if ismember('fastTopoVsProdGridMaxAbsDiff_kW', T.Properties.VariableNames)
        stats.maxTopologyGridDiff_kW = max(T.fastTopoVsProdGridMaxAbsDiff_kW, [], 'omitnan');
        stats.maxTopologySoCDiff = max(T.fastTopoVsProdSoCMaxAbsDiff, [], 'omitnan');
    end
end


function local_print_global_summary(out)

    s = out.statistics;

    fprintf('\n====================================================\n');
    fprintf('GLOBAL FAST MILP TEST SUMMARY\n');
    fprintf('Modes                         : %s\n', strjoin(string(out.objectiveModes), ', '));
    fprintf('Rows                          : %d\n', s.nRows);
    fprintf('Feasible both                 : %d / %d\n', s.nFeasibleBoth, s.nRows);
    fprintf('Objective equivalent          : %d / %d\n', s.nObjectiveEquivalent, s.nRows);
    fprintf('Safe drop-in replacement      : %d / %d\n', s.nSafeDropInReplacement, s.nRows);
    fprintf('Alternative optimal plan      : %d / %d\n', s.nAlternativeOptimalPlan, s.nRows);
    fprintf('LP accepted rows              : %d / %d\n', s.nFastLpAccepted, s.nRows);
    fprintf('Fallback rows                 : %d / %d\n', s.nFallback, s.nRows);
    fprintf('Mean speedup                  : %.3f x\n', s.meanSpeedup);
    fprintf('Max objective rel diff        : %.8f %%\n', s.maxObjectiveRelDiff_pct);
    fprintf('Max applied Pgrid diff        : %.8f kW\n', s.maxAppliedGridDiff_kW);
    fprintf('Max applied Pcharge diff      : %.8f kW\n', s.maxAppliedChargeDiff_kW);
    fprintf('Max applied Pdischarge diff   : %.8f kW\n', s.maxAppliedDischargeDiff_kW);
    fprintf('Max applied SoC diff          : %.10f\n', s.maxAppliedSoCDiff);

    if isfield(s, 'maxTopologyGridDiff_kW')
        fprintf('Max topology grid diff        : %.8f kW\n', s.maxTopologyGridDiff_kW);
        fprintf('Max topology SoC diff         : %.10f\n', s.maxTopologySoCDiff);
    end

    if isfield(out, 'savePath') && strlength(string(out.savePath)) > 0
        fprintf('Saved MAT: %s\n', out.savePath);
        fprintf('Saved CSV: %s\n', out.csvPath);
    end

    fprintf('====================================================\n');
end