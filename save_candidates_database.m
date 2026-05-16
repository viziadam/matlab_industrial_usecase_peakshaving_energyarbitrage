function save_candidates_database(configurationDatabase, cfg)
% SAVE_CANDIDATES_DATABASE
%
% Elmenti az aktualis futas candidate adatbazisat.
% A fajlnev tartalmazza:
%   - topologia: dc/ac
%   - mukodesi mod: peak_only/energy_only/combined
%
% Igy a kulonbozo futasok nem irjak felul egymast.

    if ~exist(cfg.paths.results, 'dir')
        mkdir(cfg.paths.results);
    end

    coupling = lower(string(cfg.system.bessCoupling));
    objectiveMode = lower(string(cfg.dispatch.objectiveMode));

    if ~(coupling == "dc" || coupling == "ac")
        error('Invalid cfg.system.bessCoupling: %s', coupling);
    end

    if ~(objectiveMode == "peak_only" || objectiveMode == "energy_only" || objectiveMode == "combined")
        error('Invalid cfg.dispatch.objectiveMode: %s', objectiveMode);
    end

    matName = sprintf('results_%s_%s.mat', coupling, objectiveMode);
    csvName = sprintf('results_%s_%s.csv', coupling, objectiveMode);

    matPath = fullfile(cfg.paths.results, matName);
    csvPath = fullfile(cfg.paths.results, csvName);

    configurationDatabase.runInfo = struct();
    configurationDatabase.runInfo.coupling = coupling;
    configurationDatabase.runInfo.objectiveMode = objectiveMode;
    configurationDatabase.runInfo.savedAt = datetime('now');

    save(matPath, 'configurationDatabase', '-v7.3');

    if isfield(configurationDatabase, 'summaryTable') && ~isempty(configurationDatabase.summaryTable)
        writetable(configurationDatabase.summaryTable, csvPath);
    elseif isfield(configurationDatabase, 'candidateTable') && ~isempty(configurationDatabase.candidateTable)
        writetable(configurationDatabase.candidateTable, csvPath);
    end

    fprintf('\nMain database saved:\n%s\n', matPath);
    fprintf('Summary table saved:\n%s\n', csvPath);
end
