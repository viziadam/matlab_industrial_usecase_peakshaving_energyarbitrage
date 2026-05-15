function local_plot_embedded_dispatch_diagnostics(cfg, candidateIndex, design, simSummary, detail)
% LOCAL_PLOT_EMBEDDED_DISPATCH_DIAGNOSTICS
%
% A régi run_simulation_diagnostics-ból áthozott dispatch plotokat
% készíti el a normál szimulációs candidate loopon belül.
%
% Nem futtat új szimulációt, csak a már lefutott candidate simSummary/detail
% struktúráit használja.

    if ~isfield(simSummary, 'full_result')
        error('simSummary.full_result hiányzik a dispatch diagnosztikai plotokhoz.');
    end

    if ~isfield(simSummary, 'search_result')
        error('simSummary.search_result hiányzik a dispatch diagnosztikai plotokhoz.');
    end

    if ~isfield(simSummary, 'bestContract_kW')
        error('simSummary.bestContract_kW hiányzik a dispatch diagnosztikai plotokhoz.');
    end

    if ~isfield(simSummary, 'pars')
        error('simSummary.pars hiányzik a dispatch diagnosztikai plotokhoz.');
    end

    isBaseline = false;

    if isfield(design, 'BESS_PV_ratio')
        isBaseline = abs(design.BESS_PV_ratio) < 1e-12;
    elseif isfield(design, 'E_BESS_kWh')
        isBaseline = design.E_BESS_kWh <= 0;
    end

    if isBaseline

        if ~isfield(cfg.diagnostics, 'plotDispatchDiagnosticsForBaseline') || ...
           ~cfg.diagnostics.plotDispatchDiagnosticsForBaseline

            fprintf('Baseline candidate: dispatch diagnostic plots skipped.\n');
            return;
        end
    end

    full_result = simSummary.full_result;

    % Ha a detail külön tartalmazza a részletes napokat, de full_result-ben
    % valamiért nincs benne, akkor átemeljük a plot-kompatibilitás miatt.
    if ~isfield(full_result, 'detail_days') && isfield(detail, 'detail_days')
        full_result.detail_days = detail.detail_days;
    end

    if ~isfield(full_result, 'overrun_detail_days') && isfield(detail, 'overrun_detail_days')
        full_result.overrun_detail_days = detail.overrun_detail_days;
    end

    if ~isfield(full_result, 'detail_cfg') && isfield(detail, 'detail_cfg')
        full_result.detail_cfg = detail.detail_cfg;
    end

    outDir = fullfile( ...
        cfg.diagnostics.outputFolder, ...
        sprintf('candidate_%06d', candidateIndex), ...
        'dispatch_diagnostics');

    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    figBefore = double(findall(0, 'Type', 'figure'));

    % =====================================================================
    % Régi run_simulation_diagnostics plotok
    % =====================================================================
    plot_contract_search_summary_4y(simSummary.search_result);

    plot_full_horizon_summary_4y( ...
        full_result, ...
        simSummary.bestContract_kW);

    plot_final_day_detail_4y( ...
        full_result, ...
        simSummary.pars);

    plot_selected_day_details_4y( ...
        full_result, ...
        simSummary.pars);

    % =====================================================================
    % Új planner execution debug plot
    % =====================================================================
    if isfield(cfg.diagnostics, 'makePlannerExecutionDebugPlot') && ...
       cfg.diagnostics.makePlannerExecutionDebugPlot

        if isfield(full_result, 'planner_debug') && ~isempty(full_result.planner_debug)
            plot_planner_execution_debug(full_result);
        end
    end

    % =====================================================================
    % Mentés
    % =====================================================================
    if isfield(cfg.diagnostics, 'saveFigures') && cfg.diagnostics.saveFigures

        figAfter = findall(0, 'Type', 'figure');
        newFigMask = ~ismember(double(figAfter), figBefore);
        newFigs = figAfter(newFigMask);

        local_save_figure_list(newFigs, outDir);
    end

    if isfield(cfg.diagnostics, 'closeFiguresAfterSave') && ...
       cfg.diagnostics.closeFiguresAfterSave

        figAfter = findall(0, 'Type', 'figure');
        newFigMask = ~ismember(double(figAfter), figBefore);
        newFigs = figAfter(newFigMask);

        for i = 1:numel(newFigs)
            close(newFigs(i));
        end
    end

    fprintf('Dispatch diagnostic plots created for candidate %d.\n', candidateIndex);
    fprintf('Output folder:\n%s\n', outDir);
end


function local_save_figure_list(figList, outDir)

    if isempty(figList)
        return;
    end

    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    for i = 1:numel(figList)

        fig = figList(i);

        figName = get(fig, 'Name');

        if isempty(figName)
            figName = sprintf('figure_%02d', i);
        end

        figName = regexprep(figName, '[^\w\d\- áéíóöőúüűÁÉÍÓÖŐÚÜŰ]', '_');
        figName = strtrim(figName);

        if strlength(string(figName)) == 0
            figName = sprintf('figure_%02d', i);
        end

        fileBase = fullfile(outDir, sprintf('%02d_%s', i, figName));

        savefig(fig, [fileBase, '.fig']);

        try
            exportgraphics(fig, [fileBase, '.png'], 'Resolution', 150);
        catch
            saveas(fig, [fileBase, '.png']);
        end
    end

    fprintf('Dispatch diagnostic figures saved:\n%s\n', outDir);
end

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


% function plot_final_day_detail_4y(full_result, pars, day_label)
% 
%     if nargin < 3 || isempty(day_label)
%         day_label = 'Utolsó nap';
%     end
% 
%     if isempty(full_result.final_day.plan)
%         return;
%     end
% 
%     plot_plan  = full_result.final_day.plan;
%     plot_res   = full_result.final_day.res;
%     plot_load  = full_result.final_day.load;
%     plot_pv    = full_result.final_day.pv;
%     plot_price = full_result.final_day.price;
%     soc_start  = full_result.final_day.soc_start;
% 
%     time_hours = linspace(0, 24, length(plot_load));
%     dt_plot = 24 / length(plot_load);
% 
%     % Tényleges hálózati import teljesítmény [kW]
%     P_grid_import = plot_res.E_grid_import(:) / dt_plot;
% 
%     figure('Name', [day_label, ' részletes nézet'], 'Position', [100, 60, 1250, 1100]);
% 
%     % =====================================================================
%     % 1) Teljesítményáramlások
%     % =====================================================================
%     subplot(4,1,1); hold on; grid on;
%     title([day_label, ': teljesítményáramlások']);
% 
%     P_pv_ac = plot_pv * pars.inv_eta;
%     P_pv_to_load = min(P_pv_ac, plot_load);
%     residual_after_pv = max(plot_load - P_pv_to_load, 0);
% 
%     P_bess_to_load = min(plot_res.E_discharged / dt_plot, residual_after_pv);
%     P_grid_to_load = max(plot_load - P_pv_to_load - P_bess_to_load, 0);
%     P_bess_charge = plot_res.E_stored / dt_plot;
% 
%     h = area(time_hours, [P_pv_to_load', P_bess_to_load', P_grid_to_load']);
%     h(1).FaceColor = [0.4660 0.6740 0.1880]; h(1).DisplayName = 'PV -> Load';
%     h(2).FaceColor = [0.0000 0.4470 0.7410]; h(2).DisplayName = 'BESS -> Load';
%     h(3).FaceColor = [0.6350 0.0780 0.1840]; h(3).DisplayName = 'Grid -> Load';
% 
%     plot(time_hours, P_bess_charge, 'Color', [0.9290 0.6940 0.1250], ...
%         'LineWidth', 2, 'DisplayName', 'BESS töltés');
%     plot(time_hours, plot_load, 'k-', 'LineWidth', 1.2, 'DisplayName', 'Összes load');
% 
%     yline(plot_plan.P_contract, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Contract');
% 
%     ylabel('Teljesítmény [kW]');
%     xlim([0 24]);
%     legend('Location', 'northeastoutside');
% 
%     % =====================================================================
%     % 2) Ár és töltési/kisütési ablakok
%     % =====================================================================
%     subplot(4,1,2); hold on; grid on;
%     title([day_label, ': ár és töltési/kisütési ablakok']);
% 
%     plot(time_hours, plot_price.buy_huf, 'k', 'LineWidth', 1.5, 'DisplayName', 'Vételi ár');
% 
%     buy_idx = find(plot_plan.trade_buy_mask);
%     if ~isempty(buy_idx)
%         plot(time_hours(buy_idx), plot_price.buy_huf(buy_idx), 'g.', ...
%             'MarkerSize', 15, 'DisplayName', 'Töltési ablak');
%     end
% 
%     sell_idx = find(plot_plan.trade_sell_mask);
%     if ~isempty(sell_idx)
%         plot(time_hours(sell_idx), plot_price.buy_huf(sell_idx), 'r.', ...
%             'MarkerSize', 15, 'DisplayName', 'Kisütési ablak');
%     end
% 
%     ylabel('Ár [HUF/kWh]');
%     xlim([0 24]);
%     legend('Location', 'best');
% 
%     % =====================================================================
%     % 3) Hálózati import vs. lekötött teljesítmény
%     % =====================================================================
%     subplot(4,1,3); hold on; grid on;
%     title([day_label, ': hálózatból felvett teljesítmény és contract']);
% 
%     plot(time_hours, P_grid_import, 'k-', 'LineWidth', 1.5, ...
%         'DisplayName', 'Grid import');
%     yline(plot_plan.P_contract, 'r--', 'LineWidth', 1.5, ...
%         'DisplayName', 'Contract');
% 
%     ylabel('Teljesítmény [kW]');
%     xlim([0 24]);
%     legend('Location', 'best');
% 
%     % =====================================================================
%     % 4) SOC és BESS teljesítmény
%     % =====================================================================
%     subplot(4,1,4); yyaxis left; hold on; grid on;
%     title([day_label, ': SOC és BESS teljesítmény']);
% 
%     E_net_kWh = plot_res.E_stored - plot_res.E_discharged;
%     SOC_approx = soc_start + cumsum(E_net_kWh) / pars.E_cap_nom;
%     plot(time_hours, SOC_approx * 100, 'b', 'LineWidth', 2, 'DisplayName', 'SOC');
% 
%     ylabel('SOC [%]');
%     ylim([0 100]);
% 
%     yyaxis right;
%     bar(time_hours, plot_res.E_bess_dc / dt_plot, ...
%         'FaceColor', [0.3010 0.7450 0.9330], ...
%         'EdgeColor', 'none', 'BarWidth', 1, ...
%         'DisplayName', 'BESS DC P');
% 
%     ylabel('BESS P [kW]');
%     xlabel('Idő [óra]');
%     xlim([0 24]);
%     legend('Location', 'best');
% end

function plot_final_day_detail_4y(full_result, pars, day_label)

    if nargin < 3 || isempty(day_label)
        day_label = 'Utolsó nap';
    end

    if isempty(full_result.final_day.plan)
        return;
    end

    plot_plan  = full_result.final_day.plan;
    plot_res   = full_result.final_day.res;
    plot_load  = full_result.final_day.load(:);
    plot_pv    = full_result.final_day.pv(:);
    plot_price = full_result.final_day.price;
    soc_start  = full_result.final_day.soc_start;

    n = length(plot_load);
    time_hours = linspace(0, 24, n);
    dt_plot = 24 / n;

    % =====================================================================
    % Tényleges teljesítmények a topology eredményből
    % =====================================================================
    P_grid_import = plot_res.E_grid_import(:) / dt_plot;

    P_bess_charge_actual = plot_res.E_stored(:) / dt_plot;
    P_bess_dis_actual    = plot_res.E_discharged(:) / dt_plot;

    % Előjelhelyes BESS teljesítmény:
    %   pozitív = kisütés a load felé
    %   negatív = töltés
    P_bess_actual = P_bess_dis_actual - P_bess_charge_actual;

    if isfield(plot_res, 'E_bess_dc')
        P_bess_dc_plot = plot_res.E_bess_dc(:) / dt_plot;
    else
        P_bess_dc_plot = P_bess_actual;
    end

    % =====================================================================
    % Planner teljesítmények
    % =====================================================================
    P_grid_plan = local_get_plan_vector(plot_plan, 'P_grid_plan', n, NaN);

    P_ch_plan  = local_get_plan_vector(plot_plan, 'P_ch_plan', n, 0);
    P_dis_plan = local_get_plan_vector(plot_plan, 'P_dis_plan', n, 0);

    % Előjelhelyes planner BESS teljesítmény:
    %   pozitív = kisütés
    %   negatív = töltés
    P_bess_plan = P_dis_plan - P_ch_plan;

    if isfield(plot_plan, 'P_grid_limit')
        P_grid_limit = plot_plan.P_grid_limit;
    elseif isfield(plot_plan, 'P_contract_safety_factor') && isfield(plot_plan, 'P_contract')
        P_grid_limit = plot_plan.P_contract_safety_factor * plot_plan.P_contract;
    else
        P_grid_limit = NaN;
    end

    % =====================================================================
    % Figure
    % =====================================================================
    figure('Name', [day_label, ' részletes nézet'], 'Position', [80, 40, 1350, 1250]);

    % =====================================================================
    % 1) Teljesítményáramlások
    % =====================================================================
    subplot(5,1,1); hold on; grid on;
    title([day_label, ': teljesítményáramlások']);

    P_pv_ac = min(plot_pv * pars.inv_eta, pars.P_inv_limit_ac);

    % Ez továbbra is vizuális felbontás, nem feltétlenül az AC MILP pontos
    % energiaút-felbontása. Az új 5. subplot mutatja a planner vs actual eltérést.
    P_pv_to_load = min(P_pv_ac, plot_load);
    residual_after_pv = max(plot_load - P_pv_to_load, 0);

    P_bess_to_load = min(P_bess_dis_actual, residual_after_pv);
    P_grid_to_load = max(plot_load - P_pv_to_load - P_bess_to_load, 0);

    h = area(time_hours, [P_pv_to_load, P_bess_to_load, P_grid_to_load]);
    h(1).FaceColor = [0.4660 0.6740 0.1880]; h(1).DisplayName = 'PV -> Load';
    h(2).FaceColor = [0.0000 0.4470 0.7410]; h(2).DisplayName = 'BESS -> Load';
    h(3).FaceColor = [0.6350 0.0780 0.1840]; h(3).DisplayName = 'Grid -> Load';

    plot(time_hours, P_bess_charge_actual, 'Color', [0.9290 0.6940 0.1250], ...
        'LineWidth', 2, 'DisplayName', 'BESS töltés');

    plot(time_hours, plot_load, 'k-', 'LineWidth', 1.2, 'DisplayName', 'Összes load');

    yline(plot_plan.P_contract, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Contract');

    if isfinite(P_grid_limit)
        yline(P_grid_limit, 'm--', 'LineWidth', 1.2, 'DisplayName', 'Planner grid limit');
    end

    ylabel('Teljesítmény [kW]');
    xlim([0 24]);
    legend('Location', 'northeastoutside');

    % =====================================================================
    % 2) Ár és töltési/kisütési ablakok
    % =====================================================================
    subplot(5,1,2); hold on; grid on;
    title([day_label, ': ár és töltési/kisütési ablakok']);

    buy_huf = plot_price.buy_huf(:);

    plot(time_hours, buy_huf, 'k', 'LineWidth', 1.5, 'DisplayName', 'Vételi ár');

    buy_idx = find(plot_plan.trade_buy_mask);
    buy_idx = buy_idx(buy_idx <= n);

    if ~isempty(buy_idx)
        plot(time_hours(buy_idx), buy_huf(buy_idx), 'g.', ...
            'MarkerSize', 15, 'DisplayName', 'Töltési ablak');
    end

    sell_idx = find(plot_plan.trade_sell_mask);
    sell_idx = sell_idx(sell_idx <= n);

    if ~isempty(sell_idx)
        plot(time_hours(sell_idx), buy_huf(sell_idx), 'r.', ...
            'MarkerSize', 15, 'DisplayName', 'Kisütési ablak');
    end

    ylabel('Ár [HUF/kWh]');
    xlim([0 24]);
    legend('Location', 'best');

    % =====================================================================
    % 3) Hálózati import vs. lekötött teljesítmény
    % =====================================================================
    subplot(5,1,3); hold on; grid on;
    title([day_label, ': hálózatból felvett teljesítmény és contract']);

    plot(time_hours, P_grid_import, 'k-', 'LineWidth', 1.5, ...
        'DisplayName', 'Grid import actual');

    if any(isfinite(P_grid_plan))
        plot(time_hours, P_grid_plan, 'b--', 'LineWidth', 1.2, ...
            'DisplayName', 'Grid import plan');
    end

    yline(plot_plan.P_contract, 'r--', 'LineWidth', 1.5, ...
        'DisplayName', 'Contract');

    if isfinite(P_grid_limit)
        yline(P_grid_limit, 'm--', 'LineWidth', 1.2, ...
            'DisplayName', 'Planner grid limit');
    end

    ylabel('Teljesítmény [kW]');
    xlim([0 24]);
    legend('Location', 'best');

    % =====================================================================
    % 4) SOC és BESS teljesítmény
    % =====================================================================
    subplot(5,1,4); yyaxis left; hold on; grid on;
    title([day_label, ': SOC és BESS teljesítmény']);

    E_net_kWh = plot_res.E_stored(:) - plot_res.E_discharged(:);
    SOC_approx = soc_start + cumsum(E_net_kWh) / pars.E_cap_nom;

    plot(time_hours, SOC_approx * 100, 'b', 'LineWidth', 2, 'DisplayName', 'SOC actual');

    if isfield(plot_plan, 'SoC_plan')
        soc_plan = local_get_plan_vector(plot_plan, 'SoC_plan', n, NaN);
        plot(time_hours, soc_plan * 100, 'r--', 'LineWidth', 1.5, ...
            'DisplayName', 'SOC plan');
    end

    ylabel('SOC [%]');
    ylim([0 100]);

    yyaxis right;
    bar(time_hours, P_bess_dc_plot, ...
        'FaceColor', [0.3010 0.7450 0.9330], ...
        'EdgeColor', 'none', 'BarWidth', 1, ...
        'DisplayName', 'BESS P actual');

    ylabel('BESS P [kW]');
    xlim([0 24]);
    legend('Location', 'best');

    % =====================================================================
    % 5) Planner terv és tényleges végrehajtás összehasonlítása
    % =====================================================================
    subplot(5,1,5); hold on; grid on;
    title([day_label, ': planner terv vs. tényleges végrehajtás']);

    plot(time_hours, P_grid_import, 'k-', 'LineWidth', 1.5, ...
        'DisplayName', 'Grid actual');

    if any(isfinite(P_grid_plan))
        plot(time_hours, P_grid_plan, 'b--', 'LineWidth', 1.5, ...
            'DisplayName', 'Grid plan');
    end

    plot(time_hours, P_bess_actual, 'Color', [0.3010 0.7450 0.9330], ...
        'LineWidth', 1.3, 'DisplayName', 'BESS actual (+dis / -ch)');

    plot(time_hours, P_bess_plan, 'r--', ...
        'LineWidth', 1.3, 'DisplayName', 'BESS plan (+dis / -ch)');

    yline(plot_plan.P_contract, 'r:', 'LineWidth', 1.3, ...
        'DisplayName', 'Contract');

    if isfinite(P_grid_limit)
        yline(P_grid_limit, 'm:', 'LineWidth', 1.3, ...
            'DisplayName', 'Planner grid limit');
    end

    ylabel('Teljesítmény [kW]');
    xlabel('Idő [óra]');
    xlim([0 24]);
    legend('Location', 'best');

    % =====================================================================
    % Konzolos gyors diagnosztika
    % =====================================================================
    if any(isfinite(P_grid_plan))
        grid_err = P_grid_import(:) - P_grid_plan(:);

        fprintf('\n--- FINAL DAY PLAN VS ACTUAL DEBUG ---\n');
        fprintf('Day label: %s\n', day_label);
        fprintf('Max grid actual:       %.2f kW\n', max(P_grid_import));
        fprintf('Max grid plan:         %.2f kW\n', max(P_grid_plan));
        fprintf('Max grid actual-plan:  %.2f kW\n', max(grid_err));
        fprintf('Mean grid actual-plan: %.2f kW\n', mean(grid_err, 'omitnan'));
        fprintf('Max BESS actual:       %.2f kW\n', max(P_bess_actual));
        fprintf('Min BESS actual:       %.2f kW\n', min(P_bess_actual));
        fprintf('Max BESS plan:         %.2f kW\n', max(P_bess_plan));
        fprintf('Min BESS plan:         %.2f kW\n', min(P_bess_plan));
        fprintf('-------------------------------------\n');
    end
end


function v = local_get_plan_vector(plan, fieldName, n, defaultValue)

    if isfield(plan, fieldName)
        v = plan.(fieldName)(:);
    else
        v = defaultValue * ones(n, 1);
        return;
    end

    if numel(v) < n
        v = [v; repmat(v(end), n - numel(v), 1)];
    elseif numel(v) > n
        v = v(1:n);
    end
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