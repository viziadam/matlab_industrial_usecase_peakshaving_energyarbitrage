function T = run_single_topology_diagnostic_plots_from_saved_results(objectiveMode, coupling, candidateList)
% RUN_SINGLE_TOPOLOGY_DIAGNOSTIC_PLOTS_FROM_SAVED_RESULTS
%
% Csak egy topológia candidate-metrikáit tölti be újraszimulálás nélkül.
% Ezt később külön DC vagy külön AC plotoló függvényekhez lehet használni.

    if nargin < 1 || strlength(string(objectiveMode)) == 0
        objectiveMode = "energy_only";
    end

    if nargin < 2 || strlength(string(coupling)) == 0
        coupling = "dc";
    end

    if nargin < 3
        candidateList = [];
    end

    objectiveMode = lower(string(objectiveMode));
    coupling = lower(string(coupling));

    basePath = fileparts(mfilename('fullpath'));

    cfgBase = create_configurations(basePath);
    cfgBase.dispatch.objectiveMode = objectiveMode;
    cfgBase.paths.results = fullfile(cfgBase.paths.results, char(objectiveMode));

    T = load_canonical_candidate_metrics( ...
        cfgBase, ...
        objectiveMode, ...
        coupling, ...
        candidateList);

    disp(T);
end