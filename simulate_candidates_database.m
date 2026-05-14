function DB = simulate_candidates_database(data, DB, cfg, industrialCtx)
% SIMULATE_CANDIDATES_DATABASE
%
% Lefuttatja az összes ipari PV+BESS candidate-et.
%
% Fontos:
%   - A candidate loop megmarad.
%   - A metrikák cfg.output alapján kerülnek mentésre.
%   - A DC/AC topológia cfg.system.bessCoupling alapján választódik ki.
%   - DC esetben kész a peak shaving + arbitrázs + contract optimalizálás.
%   - AC esetben ugyanaz az interfész megvan, de a planner/topology placeholder.

    if nargin < 4 || isempty(industrialCtx)
        industrialCtx = prepare_industrial_simulation_context(data, cfg);
    end

    nCandidates = DB.nCandidates;

    % =====================================================================
    % Diagnostic mode
    % =====================================================================
    diagnosticMode = isfield(cfg, 'diagnostics') && ...
                     isfield(cfg.diagnostics, 'testMode') && ...
                     cfg.diagnostics.testMode;

    if diagnosticMode

        if ~isfield(cfg.diagnostics, 'candidateIndex') || ...
           isempty(cfg.diagnostics.candidateIndex)

            error('cfg.diagnostics.testMode = true, de cfg.diagnostics.candidateIndex nincs megadva.');
        end

        candidateList = cfg.diagnostics.candidateIndex(:).';

        if any(candidateList < 1) || any(candidateList > nCandidates)
            error('Érvénytelen diagnostics candidateIndex.');
        end

        fprintf('\nDIAGNOSTIC TEST MODE ACTIVE\n');
        fprintf('Only selected candidate(s) will be simulated.\n');
        disp(candidateList);

    else
        candidateList = 1:nCandidates;
    end

    % =====================================================================
    % Candidate loop
    % =====================================================================
    for cLoop = 1:numel(candidateList)

        c = candidateList(cLoop);
        candidateID = DB.candidateTable.candidateID(c);

        fprintf('\n====================================================\n');
        fprintf('Running candidate %d / %d: %s\n', c, nCandidates, candidateID);
        fprintf('Coupling: %s\n', string(cfg.system.bessCoupling));
        fprintf('====================================================\n');

        tCandidate = tic;

        try
            % -------------------------------------------------------------
            % Candidate design
            % -------------------------------------------------------------
            design = table_row_to_design(DB.candidateTable(c, :));

            % -------------------------------------------------------------
            % Horizon-level candidate simulation
            % -------------------------------------------------------------
            [running, simSummary, detail] = simulate_industrial_candidate_horizon( ...
                industrialCtx, ...
                design, ...
                cfg);

            runtime_s = toc(tCandidate);

            % -------------------------------------------------------------
            % Runtime summary
            % -------------------------------------------------------------
            running.summary.runtime_s = runtime_s;

            if isfield(running.summary, 'contractSearchRuntime_s')
                running.summary.contractSearchRuntime_s = simSummary.contractSearchRuntime_s;
            end

            if isfield(running.summary, 'fullHorizonRuntime_s')
                running.summary.fullHorizonRuntime_s = simSummary.fullHorizonRuntime_s;
            end

            % -------------------------------------------------------------
            % Candidate result finalization
            % -------------------------------------------------------------
            DB = finalize_candidate_result( ...
                DB, ...
                c, ...
                running, ...
                runtime_s, ...
                cfg);

            % -------------------------------------------------------------
            % Detailed diagnostics
            % -------------------------------------------------------------
            if diagnosticMode

                if ~isfield(DB, 'diagnostics') || isempty(DB.diagnostics)
                    DB.diagnostics = struct();
                end

                fieldName = sprintf('candidate_%d', c);

                DB.diagnostics.(fieldName) = struct();
                DB.diagnostics.(fieldName).design = design;
                DB.diagnostics.(fieldName).summary = simSummary;
                DB.diagnostics.(fieldName).detail = detail;
            end

        catch ME

            runtime_s = toc(tCandidate);

            warning('Candidate %d failed: %s', c, ME.message);

            DB.candidateTable.wasSimulated(c) = false;
            DB.candidateTable.hasError(c) = true;
            DB.candidateTable.errorMessage(c) = string(ME.message);
            DB.candidateTable.runtime_s(c) = runtime_s;
        end

        % -----------------------------------------------------------------
        % Partial save
        % -----------------------------------------------------------------
        if isfield(cfg, 'sim') && ...
           isfield(cfg.sim, 'saveAfterEachCandidate') && ...
           cfg.sim.saveAfterEachCandidate

            save_candidates_database(DB, cfg);
        end
    end
end


% =========================================================================
% DESIGN STRUCTURE FROM TABLE ROW
% =========================================================================
function design = table_row_to_design(row)

    design = struct();

    varNames = row.Properties.VariableNames;

    for k = 1:numel(varNames)

        name = varNames{k};
        value = row.(name);

        if istable(value)
            continue;
        end

        if iscell(value)
            value = value{1};
        elseif isstring(value)
            value = value(1);
        elseif isnumeric(value) || islogical(value)
            value = value(1);
        end

        design.(name) = value;
    end

    requiredFields = {'P_PV_kW', 'P_inv_kW', 'E_BESS_kWh', 'P_BESS_kW'};

    for k = 1:numel(requiredFields)

        f = requiredFields{k};

        if ~isfield(design, f)
            error('A design struktúra hiányzó mezője: %s', f);
        end
    end
end