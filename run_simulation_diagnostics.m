function diagnostics = run_simulation_diagnostics(cfg)
% RUN_SIMULATION_DIAGNOSTICS
%
% Ipari DC peak shaving + energia arbitrázs + contract search diagnosztika.
%
% Egy véletlen, nem nulla BESS-es candidate-et futtat teljes horizonra,
% majd elkészíti a run_single_bess_contract_search-ben használt ábrákat.

    if nargin < 1 || isempty(cfg)
        basePath = fileparts(mfilename('fullpath'));
        cfg = create_configurations(basePath);
    end

    if cfg.system.bessCoupling ~= "dc"
        error('A diagnosztikai függvény jelenleg csak DC-csatolt rendszerre van implementálva.');
    end

    fprintf('\n=== INDUSTRIAL DC DIAGNOSTIC RUN ===\n');

    % =====================================================================
    % 1) Data + context
    % =====================================================================
    data = build_data(cfg);

    industrialCtx = prepare_industrial_simulation_context(data, cfg);

    DB = init_candidate_database_structures(data, cfg);

    % =====================================================================
    % 2) Random nonzero BESS candidate
    % =====================================================================
    if ~ismember('E_BESS_kWh', DB.candidateTable.Properties.VariableNames)
        error('A candidateTable nem tartalmaz E_BESS_kWh oszlopot.');
    end

    nonzeroIdx = find(DB.candidateTable.E_BESS_kWh > 0);

    if isempty(nonzeroIdx)
        error('Nincs nem nulla BESS-es candidate a diagnosztikához.');
    end

    rng(42);
    selectedIdx = nonzeroIdx(randi(numel(nonzeroIdx)));

    fprintf('Selected diagnostic candidate index: %d\n', selectedIdx);
    fprintf('E_BESS_kWh = %.2f\n', DB.candidateTable.E_BESS_kWh(selectedIdx));
    fprintf('P_BESS_kW = %.2f\n', DB.candidateTable.P_BESS_kW(selectedIdx));

    design = local_table_row_to_design(DB.candidateTable(selectedIdx, :));

    % =====================================================================
    % 3) Részletes diagnosztika bekapcsolása
    % =====================================================================
    cfgDiag = cfg;
    cfgDiag.diagnostics.storeCandidateDetail = true;

    % =====================================================================
    % 4) Candidate horizon futtatás
    % =====================================================================
    [running, simSummary, detail] = simulate_industrial_candidate_horizon( ...
        industrialCtx, ...
        design, ...
        cfgDiag);

    % =====================================================================
    % 5) Eredmények DB-be írása is, hogy a metrikák ellenőrizhetők legyenek
    % =====================================================================
    DB = finalize_candidate_result( ...
        DB, ...
        selectedIdx, ...
        running, ...
        simSummary.contractSearchRuntime_s + simSummary.fullHorizonRuntime_s, ...
        cfgDiag);

    % =====================================================================
    % 6) Plotok
    % =====================================================================
    full_result = simSummary.full_result;

    if ~isfield(full_result, 'detail_days')
        full_result.detail_days = detail.detail_days;
    end

    if ~isfield(full_result, 'overrun_detail_days')
        full_result.overrun_detail_days = detail.overrun_detail_days;
    end

    if ~isfield(full_result, 'detail_cfg')
        full_result.detail_cfg = detail.detail_cfg;
    end

    plot_contract_search_summary_4y(simSummary.search_result);
    plot_full_horizon_summary_4y(full_result, simSummary.bestContract_kW);
    plot_final_day_detail_4y(full_result, simSummary.pars);
    plot_selected_day_details_4y(full_result, simSummary.pars);

    % =====================================================================
    % 7) Kimenet
    % =====================================================================
    diagnostics = struct();

    diagnostics.createdAt = datetime('now');
    diagnostics.selectedCandidateIndex = selectedIdx;
    diagnostics.design = design;
    diagnostics.running = running;
    diagnostics.summary = simSummary;
    diagnostics.detail = detail;
    diagnostics.DB = DB;

    fprintf('\nDiagnostic run finished.\n');
end


function design = local_table_row_to_design(row)

    design = struct();

    names = row.Properties.VariableNames;

    for i = 1:numel(names)

        name = names{i};
        value = row.(name);

        if iscell(value)
            value = value{1};
        elseif isstring(value) || isnumeric(value) || islogical(value)
            value = value(1);
        end

        design.(name) = value;
    end
end