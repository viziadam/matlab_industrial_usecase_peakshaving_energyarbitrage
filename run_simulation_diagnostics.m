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

    plot_planner_execution_debug(full_result);

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

    % =====================================================================
    % 8) Automatikus diagnosztikai ellenőrzések
    % =====================================================================
    fprintf('\n--- DIAGNOSTIC CONSISTENCY CHECKS ---\n');

    T = DB.candidateTable;

    if ~DB.candidateTable.wasSimulated(selectedIdx)
        error('Diagnostic candidate wasSimulated értéke false.');
    end

    if DB.candidateTable.hasError(selectedIdx)
        error('Diagnostic candidate hasError értéke true.');
    end

    requiredScalarFields = { ...
        'objectiveCost_HUF', ...
    'energyCost_HUF', ...
    'degradationCost_HUF', ...
    'overrunCost_HUF', ...
    'contractCost_HUF', ...
    'gridImport_kWh', ...
    'gridImportNoBess_kWh', ...
    'bessThroughput_kWh', ...
    'maxGridImportPeak_kW', ...
    'maxGridImportNoBessPeak_kW'};

    for k = 1:numel(requiredScalarFields)

        f = requiredScalarFields{k};

        if ~ismember(f, T.Properties.VariableNames)
            error('Hiányzó candidateTable oszlop: %s', f);
        end

        val = T.(f)(selectedIdx);

        if isempty(val) || isnan(val) || ~isfinite(val)
            error('Érvénytelen érték a candidateTable.%s mezőben.', f);
        end
    end

    costSum = ...
        T.energyCost_HUF(selectedIdx) + ...
        T.degradationCost_HUF(selectedIdx) + ...
        T.overrunCost_HUF(selectedIdx) + ...
        T.contractCost_HUF(selectedIdx);

    costErr = abs(costSum - T.objectiveCost_HUF(selectedIdx));

    if costErr > 1e-3 * max(1, abs(T.objectiveCost_HUF(selectedIdx)))
        error('Költségösszegzési hiba: objectiveCost_HUF nem egyezik a komponensek összegével.');
    end

    if T.gridImport_kWh(selectedIdx) < 0
        error('Negatív gridImport_kWh.');
    end

    if T.bessThroughput_kWh(selectedIdx) < 0
        error('Negatív bessThroughput_kWh.');
    end

    if T.maxGridImportPeak_kW(selectedIdx) < 0
        error('Negatív maxGridImportPeak_kW.');
    end

    if isempty(simSummary.full_result.final_day)
        error('A full_result.final_day üres. Az utolsó napi részletes diagnosztika nem mentődött.');
    end

    if ~isfield(simSummary.full_result, 'daily_peak_with_bess')
        error('Hiányzik: full_result.daily_peak_with_bess');
    end

    if any(isnan(simSummary.full_result.daily_peak_with_bess))
        error('NaN található a daily_peak_with_bess vektorban.');
    end

    fprintf('OK: candidate sikeresen lefutott.\n');
    fprintf('OK: költségkomponensek összege egyezik.\n');
    fprintf('OK: fő energetikai és peak metrikák érvényesek.\n');
    fprintf('OK: részletes final day mentés létezik.\n');
    fprintf('Diagnostic consistency checks passed.\n');
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

% =========================================================================
% ÁBRÁK
% =========================================================================
function plot_contract_search_summary_4y(search_result)

    hist = search_result.proxy_history.history;
    proxy_contracts = [hist.contract_kW];
    proxy_costs     = [hist.total_cost_huf];

    [proxy_contracts_sorted, idx_sort] = sort(proxy_contracts);
    proxy_costs_sorted = proxy_costs(idx_sort);
    [proxy_contracts_unique, ia] = unique(proxy_contracts_sorted, 'last');
    proxy_costs_unique = proxy_costs_sorted(ia);

    validation_results = search_result.validation_results;
    val_contracts = [validation_results.contract_kW];
    val_total     = [validation_results.total_cost_period_huf];
    val_energy    = [validation_results.energy_cost_period_huf];
    val_deg       = [validation_results.degradation_cost_period_huf];
    val_over      = [validation_results.overrun_cost_period_huf];
    val_contractc = [validation_results.contract_cost_period_huf];
    val_runtime   = [validation_results.runtime_s];

    [val_contracts, idxv] = sort(val_contracts);
    val_total     = val_total(idxv);
    val_energy    = val_energy(idxv);
    val_deg       = val_deg(idxv);
    val_over      = val_over(idxv);
    val_contractc = val_contractc(idxv);
    val_runtime   = val_runtime(idxv);

    figure('Name', '4 éves contract keresés összesítő', 'Position', [80, 80, 1350, 900]);

    subplot(2,2,1); hold on; grid on;
    plot(proxy_contracts_unique, proxy_costs_unique, 'k--o', 'LineWidth', 1.5, 'DisplayName', 'Proxy költség');
    plot(val_contracts, val_total, 'b-o', 'LineWidth', 2, 'DisplayName', 'Validált költség');
    xline(search_result.best_contract_kW, 'r--', 'LineWidth', 1.5, ...
        'DisplayName', sprintf('Optimum = %.0f kW', search_result.best_contract_kW));
    xlabel('Contract [kW]');
    ylabel('Költség [HUF]');
    title('Contract keresés');
    legend('Location', 'best');

    subplot(2,2,2); hold on; grid on;
    plot(val_contracts, val_energy,    'k-', 'LineWidth', 1.5, 'DisplayName', 'Energia');
    plot(val_contracts, val_deg,       'b-', 'LineWidth', 1.5, 'DisplayName', 'Degradáció');
    plot(val_contracts, val_over,      'r-', 'LineWidth', 1.5, 'DisplayName', 'Overrun');
    plot(val_contracts, val_contractc, 'm-', 'LineWidth', 1.5, 'DisplayName', 'Fix contract');
    xlabel('Contract [kW]');
    ylabel('Költség [HUF]');
    title('Költségkomponensek');
    legend('Location', 'best');

    subplot(2,2,3); hold on; grid on;
    max_peak = arrayfun(@(s) max(s.daily_peak_with_bess), validation_results);
    mean_peak = arrayfun(@(s) mean(s.daily_peak_with_bess), validation_results);
    p95_peak = arrayfun(@(s) prctile(s.daily_peak_with_bess, 95), validation_results);
    max_peak = max_peak(idxv);
    mean_peak = mean_peak(idxv);
    p95_peak = p95_peak(idxv);

    plot(val_contracts, max_peak, 'b-o', 'LineWidth', 1.5, 'DisplayName', 'Max peak');
    plot(val_contracts, mean_peak, 'k-s', 'LineWidth', 1.5, 'DisplayName', 'Átlag peak');
    plot(val_contracts, p95_peak, 'c-^', 'LineWidth', 1.5, 'DisplayName', 'P95 peak');
    xline(search_result.best_contract_kW, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Optimum');
    xlabel('Contract [kW]');
    ylabel('Peak [kW]');
    title('Peak statisztikák');
    legend('Location', 'best');

    subplot(2,2,4); hold on; grid on;
    bar(val_contracts, val_runtime, 'FaceColor', [0.2 0.6 0.8], 'DisplayName', 'Runtime');
    xlabel('Contract [kW]');
    ylabel('Futásidő [s]');
    title('Validációs futásidők');
end


function plot_full_horizon_summary_4y(full_result, best_contract)

    days_axis = full_result.days_axis(:).';

    daily_peak_no_bess    = full_result.daily_peak_no_bess(:).';
    daily_peak_with_bess  = full_result.daily_peak_with_bess(:).';
    daily_energy_cost     = full_result.daily_energy_cost(:).';
    daily_deg_cost        = full_result.daily_deg_cost(:).';
    daily_overrun_cost    = full_result.daily_overrun_cost(:).';
    daily_total_cost      = full_result.daily_total_cost(:).';
    daily_bess_throughput = full_result.daily_bess_throughput(:).';
    daily_planned_peak    = full_result.daily_planned_peak(:).';
    daily_ref_contract    = full_result.daily_ref_contract(:).';

    figure('Name', 'Teljes 4 éves futás összesítő', 'Position', [120, 80, 1400, 980]);

    subplot(4,1,1); hold on; grid on;
    plot(days_axis, daily_peak_no_bess,   'k-', 'LineWidth', 1.0, 'DisplayName', 'Peak BESS nélkül');
    plot(days_axis, daily_peak_with_bess, 'b-', 'LineWidth', 1.2, 'DisplayName', 'Peak BESS-sel');
    plot(days_axis, daily_planned_peak,   'm-', 'LineWidth', 1.0, 'DisplayName', 'MILP peak jelölt');
    yline(best_contract, 'r--', 'LineWidth', 1.5, 'DisplayName', sprintf('Contract = %.0f kW', best_contract));
    ylabel('Peak [kW]');
    title('Napi peak-ek a teljes időszakon');
    legend('Location', 'best');

    subplot(4,1,2); hold on; grid on;
    plot(days_axis, daily_energy_cost,  'k-', 'LineWidth', 1.0, 'DisplayName', 'Energia');
    plot(days_axis, daily_deg_cost,     'b-', 'LineWidth', 1.0, 'DisplayName', 'Degradáció');
    plot(days_axis, daily_overrun_cost, 'r-', 'LineWidth', 1.0, 'DisplayName', 'Overrun');
    plot(days_axis, daily_total_cost,   'm-', 'LineWidth', 1.5, 'DisplayName', 'Összes napi költség');
    ylabel('Költség [HUF]');
    title('Napi költségek');
    legend('Location', 'best');

    subplot(4,1,3); hold on; grid on;
    bar(days_axis, daily_bess_throughput, 'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'none');
    ylabel('kWh/nap');
    title('Napi BESS throughput');

    subplot(4,1,4); hold on; grid on;
    plot(days_axis, daily_planned_peak,  'm-', 'LineWidth', 1.2, 'DisplayName', 'MILP peak jelölt');
    plot(days_axis, daily_ref_contract,  'r--', 'LineWidth', 1.2, 'DisplayName', 'Contract');
    plot(days_axis, daily_peak_with_bess,'b:', 'LineWidth', 1.2, 'DisplayName', 'Tényleges peak');
    ylabel('Teljesítmény [kW]');
    xlabel('Nap index');
    title('Peak és contract viszony');
    legend('Location', 'best');
end


function plot_final_day_detail_4y(full_result, pars, day_label)

    if nargin < 3 || isempty(day_label)
        day_label = 'Utolsó nap';
    end

    if isempty(full_result.final_day.plan)
        return;
    end

    plot_plan  = full_result.final_day.plan;
    plot_res   = full_result.final_day.res;
    plot_load  = full_result.final_day.load;
    plot_pv    = full_result.final_day.pv;
    plot_price = full_result.final_day.price;
    soc_start  = full_result.final_day.soc_start;

    time_hours = linspace(0, 24, length(plot_load));
    dt_plot = 24 / length(plot_load);

    % Tényleges hálózati import teljesítmény [kW]
    P_grid_import = plot_res.E_grid_import(:) / dt_plot;

    figure('Name', [day_label, ' részletes nézet'], 'Position', [100, 60, 1250, 1100]);

    % =====================================================================
    % 1) Teljesítményáramlások
    % =====================================================================
    subplot(4,1,1); hold on; grid on;
    title([day_label, ': teljesítményáramlások']);

    P_pv_ac = plot_pv * pars.inv_eta;
    P_pv_to_load = min(P_pv_ac, plot_load);
    residual_after_pv = max(plot_load - P_pv_to_load, 0);

    P_bess_to_load = min(plot_res.E_discharged / dt_plot, residual_after_pv);
    P_grid_to_load = max(plot_load - P_pv_to_load - P_bess_to_load, 0);
    P_bess_charge = plot_res.E_stored / dt_plot;

    h = area(time_hours, [P_pv_to_load', P_bess_to_load', P_grid_to_load']);
    h(1).FaceColor = [0.4660 0.6740 0.1880]; h(1).DisplayName = 'PV -> Load';
    h(2).FaceColor = [0.0000 0.4470 0.7410]; h(2).DisplayName = 'BESS -> Load';
    h(3).FaceColor = [0.6350 0.0780 0.1840]; h(3).DisplayName = 'Grid -> Load';

    plot(time_hours, P_bess_charge, 'Color', [0.9290 0.6940 0.1250], ...
        'LineWidth', 2, 'DisplayName', 'BESS töltés');
    plot(time_hours, plot_load, 'k-', 'LineWidth', 1.2, 'DisplayName', 'Összes load');

    yline(plot_plan.P_contract, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Contract');

    ylabel('Teljesítmény [kW]');
    xlim([0 24]);
    legend('Location', 'northeastoutside');

    % =====================================================================
    % 2) Ár és töltési/kisütési ablakok
    % =====================================================================
    subplot(4,1,2); hold on; grid on;
    title([day_label, ': ár és töltési/kisütési ablakok']);

    plot(time_hours, plot_price.buy_huf, 'k', 'LineWidth', 1.5, 'DisplayName', 'Vételi ár');

    buy_idx = find(plot_plan.trade_buy_mask);
    if ~isempty(buy_idx)
        plot(time_hours(buy_idx), plot_price.buy_huf(buy_idx), 'g.', ...
            'MarkerSize', 15, 'DisplayName', 'Töltési ablak');
    end

    sell_idx = find(plot_plan.trade_sell_mask);
    if ~isempty(sell_idx)
        plot(time_hours(sell_idx), plot_price.buy_huf(sell_idx), 'r.', ...
            'MarkerSize', 15, 'DisplayName', 'Kisütési ablak');
    end

    ylabel('Ár [HUF/kWh]');
    xlim([0 24]);
    legend('Location', 'best');

    % =====================================================================
    % 3) Hálózati import vs. lekötött teljesítmény
    % =====================================================================
    subplot(4,1,3); hold on; grid on;
    title([day_label, ': hálózatból felvett teljesítmény és contract']);

    plot(time_hours, P_grid_import, 'k-', 'LineWidth', 1.5, ...
        'DisplayName', 'Grid import');
    yline(plot_plan.P_contract, 'r--', 'LineWidth', 1.5, ...
        'DisplayName', 'Contract');

    ylabel('Teljesítmény [kW]');
    xlim([0 24]);
    legend('Location', 'best');

    % =====================================================================
    % 4) SOC és BESS teljesítmény
    % =====================================================================
    subplot(4,1,4); yyaxis left; hold on; grid on;
    title([day_label, ': SOC és BESS teljesítmény']);

    E_net_kWh = plot_res.E_stored - plot_res.E_discharged;
    SOC_approx = soc_start + cumsum(E_net_kWh) / pars.E_cap_nom;
    plot(time_hours, SOC_approx * 100, 'b', 'LineWidth', 2, 'DisplayName', 'SOC');

    ylabel('SOC [%]');
    ylim([0 100]);

    yyaxis right;
    bar(time_hours, plot_res.E_bess_dc / dt_plot, ...
        'FaceColor', [0.3010 0.7450 0.9330], ...
        'EdgeColor', 'none', 'BarWidth', 1, ...
        'DisplayName', 'BESS DC P');

    ylabel('BESS P [kW]');
    xlabel('Idő [óra]');
    xlim([0 24]);
    legend('Location', 'best');
end

function plot_selected_day_details_4y(full_result, pars)
% PLOT_SELECTED_DAY_DETAILS_4Y
%
% Meghívja a meglévő részletes napi plotolót:
%   1) a legnagyobb túllépéses napokra,
%   2) néhány reprezentáns / validációs napra.
%
% A szimulációt nem futtatja újra, csak a run_full_horizon_for_fixed_contract
% által eltárolt napi részleteket használja.

    fprintf('\n--- RÉSZLETES DIAGNOSZTIKAI NAPI ÁBRÁK ---\n');

    if isfield(full_result, 'overrun_detail_days') && ~isempty(full_result.overrun_detail_days)
        over_days = full_result.overrun_detail_days;

        fprintf('Túllépéses részletes napok száma: %d\n', numel(over_days));

        for i = 1:numel(over_days)
            tmp = struct();
            tmp.final_day = over_days(i).final_day;

            label = sprintf('Túllépéses nap | day\\_cache index = %d | abs day = %d | peak = %.1f kW | túllépés = %.1f kW', ...
                over_days(i).day_index, ...
                over_days(i).abs_day, ...
                over_days(i).peak_kW, ...
                over_days(i).overrun_margin_kW);

            plot_final_day_detail_4y(tmp, pars, label);
        end
    else
        fprintf('Nem volt eltárolt túllépéses részletes nap.\n');
    end

    if isfield(full_result, 'detail_days') && ~isempty(full_result.detail_days)
        rep_days = full_result.detail_days;

        if isfield(full_result, 'overrun_detail_days') && ~isempty(full_result.overrun_detail_days)
            over_idx = [full_result.overrun_detail_days.day_index];
            rep_idx = [rep_days.day_index];
            rep_days = rep_days(~ismember(rep_idx, over_idx));
        end

        if isempty(rep_days)
            fprintf('Nincs külön reprezentáns nap, ami nem szerepelt már túllépéses napként.\n');
            return;
        end

        max_rep_plots = 8;
        if isfield(full_result, 'detail_cfg') && ...
           isfield(full_result.detail_cfg, 'max_representative_plots')
            max_rep_plots = full_result.detail_cfg.max_representative_plots;
        end

        nPlot = min(max_rep_plots, numel(rep_days));

        fprintf('Reprezentáns részletes napok plottolása: %d db\n', nPlot);

        for i = 1:nPlot
            tmp = struct();
            tmp.final_day = rep_days(i).final_day;

            label = sprintf('Reprezentáns nap | day\\_cache index = %d | abs day = %d | peak = %.1f kW | margin = %.1f kW', ...
                rep_days(i).day_index, ...
                rep_days(i).abs_day, ...
                rep_days(i).peak_kW, ...
                rep_days(i).overrun_margin_kW);

            plot_final_day_detail_4y(tmp, pars, label);
        end
    else
        fprintf('Nem volt eltárolt reprezentáns részletes nap.\n');
    end
end

function plot_planner_execution_debug(full_result)

    if ~isfield(full_result, 'planner_debug') || isempty(full_result.planner_debug)
        error('Nincs full_result.planner_debug mező.');
    end

    D = full_result.planner_debug;

    day = [D.day_index];

    figure('Name', 'Planner execution debug', 'Position', [120, 80, 1350, 900]);

    subplot(4,1,1); hold on; grid on;
    plot(day, [D.max_P_ch_plan], 'b-', 'LineWidth', 1.2, 'DisplayName', 'max P ch plan');
    plot(day, [D.max_P_dis_plan], 'r-', 'LineWidth', 1.2, 'DisplayName', 'max P dis plan');
    plot(day, [D.max_P_bess_req], 'k--', 'LineWidth', 1.2, 'DisplayName', 'max P bess req');
    ylabel('kW');
    title('Planner parancs vs. realtime BESS kérés');
    legend('Location', 'best');

    subplot(4,1,2); hold on; grid on;
    plot(day, [D.max_P_grid_plan], 'b-', 'LineWidth', 1.2, 'DisplayName', 'max grid plan');
    plot(day, [D.max_P_grid_actual], 'r--', 'LineWidth', 1.2, 'DisplayName', 'max grid actual');
    plot(day, [D.contract_kW], 'k:', 'LineWidth', 1.2, 'DisplayName', 'contract');
    ylabel('kW');
    title('Tervezett és tényleges grid peak');
    legend('Location', 'best');

    subplot(4,1,3); hold on; grid on;
    plot(day, [D.soc_plan_start], 'b-', 'LineWidth', 1.2, 'DisplayName', 'SoC plan start');
    plot(day, [D.soc_plan_end], 'r-', 'LineWidth', 1.2, 'DisplayName', 'SoC plan end');
    plot(day, [D.SoC_initial], 'k--', 'LineWidth', 1.2, 'DisplayName', 'actual SoC initial');
    ylabel('SoC');
    title('SoC terv és tényleges induló SoC');
    legend('Location', 'best');

    subplot(4,1,4); hold on; grid on;
    plot(day, [D.exitflag], 'ko-', 'LineWidth', 1.2, 'DisplayName', 'exitflag');
    ylabel('exitflag');
    xlabel('day index');
    title('MILP exitflag');
    legend('Location', 'best');
end