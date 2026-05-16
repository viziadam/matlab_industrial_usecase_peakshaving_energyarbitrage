function runResult = main()
% MAIN
%
% A create_configurations.m-ben kivalasztott mukodesi modra lefuttatja
% mindket topologiat:
%   - DC-csatolt PV+BESS
%   - AC-csatolt PV+BESS
%
% Mukodesi mod:
%   cfg.dispatch.objectiveMode = "peak_only" | "energy_only" | "combined"
%
% Diagnosztikai mod:
%   ha cfg.diagnostics.enabled = true, akkor mindket topologiara lefut
%   a baseline + cfg.diagnostics.candidateIndex lista.
%
% Teljes futas:
%   ha cfg.diagnostics.enabled = false, akkor mindket topologiara lefut
%   a teljes candidate sweep, majd elkeszul az AC/DC osszehasonlito
%   evaluation is.

    clc;
    close all;

    basePath = fileparts(mfilename('fullpath'));

    cfg = create_configurations(basePath);

    objectiveMode = lower(string(cfg.dispatch.objectiveMode));

    diagnosticCandidateIndex = [];

    if isfield(cfg, 'diagnostics') && ...
       isfield(cfg.diagnostics, 'enabled') && ...
       cfg.diagnostics.enabled

        diagnosticCandidateIndex = cfg.diagnostics.candidateIndex;
    end

    runResult = run_all_topologies_for_mode( ...
        objectiveMode, ...
        diagnosticCandidateIndex);

    fprintf('\nIndustrial PV+BESS AC/DC simulation finished.\n');
    fprintf('Objective mode: %s\n', objectiveMode);

    if isempty(diagnosticCandidateIndex)
        fprintf('Run type: full sweep. AC/DC comparison was created.\n');
    else
        fprintf('Run type: diagnostic. Selected candidates were simulated for AC and DC.\n');
    end
end
