function out = run_ac_dc_diagnostic_plots_from_saved_results(objectiveMode, candidateList)
% RUN_AC_DC_DIAGNOSTIC_PLOTS_FROM_SAVED_RESULTS
%
% Csak az AC/DC teljes idoszakos diagnosztikai osszehasonlito abrakat
% kesziti ujra a korabban elmentett eredmenyfajlokbol.
%
% Nem futtat szimulaciot, nem hivja az optimalizalot es nem modositja a
% candidate eredmenyeket.
%
% Pelda:
%   run_ac_dc_diagnostic_plots_from_saved_results("energy_only", 9)
%   run_ac_dc_diagnostic_plots_from_saved_results("combined", [9 12 15])

    if nargin < 1 || strlength(string(objectiveMode)) == 0
        objectiveMode = "energy_only";
    end

    if nargin < 2
        candidateList = [];
    end

    objectiveMode = lower(string(objectiveMode));

    if ~(objectiveMode == "peak_only" || objectiveMode == "energy_only" || objectiveMode == "combined")
        error('Invalid objectiveMode: %s', objectiveMode);
    end

    basePath = fileparts(mfilename('fullpath'));
    cfgBase = create_configurations(basePath);
    cfgBase.dispatch.objectiveMode = objectiveMode;
    cfgBase.paths.results = fullfile(cfgBase.paths.results, char(objectiveMode));

    dcPath = fullfile(cfgBase.paths.results, sprintf('results_dc_%s.mat', objectiveMode));
    acPath = fullfile(cfgBase.paths.results, sprintf('results_ac_%s.mat', objectiveMode));

    if ~exist(dcPath, 'file')
        error('Missing saved DC result file: %s', dcPath);
    end

    if ~exist(acPath, 'file')
        error('Missing saved AC result file: %s', acPath);
    end

    Sdc = load(dcPath, 'configurationDatabase');
    Sac = load(acPath, 'configurationDatabase');

    if ~isfield(Sdc, 'configurationDatabase')
        error('Saved DC result does not contain variable configurationDatabase: %s', dcPath);
    end

    if ~isfield(Sac, 'configurationDatabase')
        error('Saved AC result does not contain variable configurationDatabase: %s', acPath);
    end

    runResult = struct();
    runResult.objectiveMode = objectiveMode;
    runResult.dc = struct();
    runResult.ac = struct();
    runResult.dc.DB = Sdc.configurationDatabase;
    runResult.ac.DB = Sac.configurationDatabase;

    if isempty(candidateList)
        nDc = height(runResult.dc.DB.candidateTable);
        nAc = height(runResult.ac.DB.candidateTable);
        candidateList = 1:min(nDc, nAc);
    end

    out = plot_ac_dc_diagnostic_comparison( ...
        runResult, ...
        cfgBase, ...
        objectiveMode, ...
        candidateList);

    fprintf('\nAC/DC diagnostic plots regenerated from saved results only.\n');
    fprintf('No simulation was executed.\n');
end
