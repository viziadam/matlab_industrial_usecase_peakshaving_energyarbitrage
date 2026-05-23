function out = run_ac_dc_fast_milp_comparison_test(objectiveMode, candidateList, monthIndex, opts)
% RUN_FAST_MILP_AC_DC_MONTH_TEST
%
% Command windowbol kozvetlenul hivhato havi AC/DC fast MILP teszt.
%
% Peldak:
%   out = run_fast_milp_ac_dc_month_test;
%   out = run_fast_milp_ac_dc_month_test("energy_only", 2, 1);
%   out = run_fast_milp_ac_dc_month_test("combined", [2 3], 1);
%
% Ez a fajl csak:
%   - cfg-t letrehoz
%   - dayList-et beallit
%   - opts-ot beallit
%   - meghivja a milp_fast_test_environment fuggvenyt

    if nargin < 1 || strlength(string(objectiveMode)) == 0
        objectiveMode = "energy_only";
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

    if ~(objectiveMode == "peak_only" || objectiveMode == "energy_only" || objectiveMode == "combined")
        error('Invalid objectiveMode: %s', objectiveMode);
    end

    if numel(monthIndex) ~= 1
        error('monthIndex must be scalar. Use opts.dayList for explicit day lists.');
    end

    opts = local_set_default(opts, 'nDays', 30);
    opts = local_set_default(opts, 'nRepeat', 1);
    opts = local_set_default(opts, 'makePlots', false);
    opts = local_set_default(opts, 'saveResult', true);
    opts = local_set_default(opts, 'validationTol_kW', 1e-5);
    opts = local_set_default(opts, 'lpSimultaneousPowerTolerance_kW', 1e-5);

    opts = local_set_default(opts, 'objectiveRelTol_pct', 1e-6);
    opts = local_set_default(opts, 'objectiveAbsTol_HUF', 1e-3);
    opts = local_set_default(opts, 'trajectoryPowerTol_kW', 1e-5);
    opts = local_set_default(opts, 'trajectorySocTol', 1e-7);

    basePath = fileparts(mfilename('fullpath'));

    cfg = create_configurations(basePath);
    cfg.dispatch.objectiveMode = objectiveMode;
    cfg.paths.results = fullfile(cfg.paths.results, char(objectiveMode));

    if isfield(opts, 'dayList') && ~isempty(opts.dayList)
        dayList = opts.dayList(:).';
    else
        startDay = (monthIndex - 1) * opts.nDays + 1;
        dayList = startDay:(startDay + opts.nDays - 1);
    end

    couplingList = ["dc", "ac"];

    fprintf('\n====================================================\n');
    fprintf('Fast MILP AC/DC monthly test\n');
    fprintf('Objective mode : %s\n', objectiveMode);
    fprintf('Candidate list : %s\n', mat2str(candidateList));
    fprintf('Month index    : %d\n', monthIndex);
    fprintf('Day list       : %s\n', mat2str(dayList));
    fprintf('nRepeat        : %d\n', opts.nRepeat);
    fprintf('====================================================\n');

    out = milp_fast_test_environment( ...
        cfg, ...
        objectiveMode, ...
        couplingList, ...
        candidateList, ...
        dayList, ...
        opts);

    out.monthIndex = monthIndex;
end


function opts = local_set_default(opts, fieldName, defaultValue)

    if ~isfield(opts, fieldName) || isempty(opts.(fieldName))
        opts.(fieldName) = defaultValue;
    end
end