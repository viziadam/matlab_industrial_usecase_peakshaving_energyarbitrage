function local_plot_embedded_dispatch_diagnostics(cfg, candidateIndex, design, simSummary, detail)
% LOCAL_PLOT_EMBEDDED_DISPATCH_DIAGNOSTICS
%
% Dispatch diagnosztikai abrakat keszit a mar lefutott candidate eredmenyekbol.
% A reszletes napi abra DC es AC csatolasra, valamint peak_only,
% energy_only es combined mukodesi modra is ugyanazt az egyseges logikat
% hasznalja.

    if ~isfield(simSummary, 'full_result')
        error('simSummary.full_result hianyzik a dispatch diagnosztikai plotokhoz.');
    end

    if ~isfield(simSummary, 'search_result')
        error('simSummary.search_result hianyzik a dispatch diagnosztikai plotokhoz.');
    end

    if ~isfield(simSummary, 'bestContract_kW')
        error('simSummary.bestContract_kW hianyzik a dispatch diagnosztikai plotokhoz.');
    end

    if ~isfield(simSummary, 'pars')
        error('simSummary.pars hianyzik a dispatch diagnosztikai plotokhoz.');
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

    if local_has_contract_search_history(simSummary.search_result)
        plot_contract_search_summary_4y(simSummary.search_result);
    else
        if isfield(simSummary.search_result, 'mode')
            fprintf('Contract search summary plot skipped. Mode: %s\n', string(simSummary.search_result.mode));
        else
            fprintf('Contract search summary plot skipped.\n');
        end
    end

    plot_full_horizon_summary_4y(full_result, simSummary.bestContract_kW);
    plot_final_day_detail_4y(full_result, simSummary.pars);
    plot_selected_day_details_4y(full_result, simSummary.pars);

    if isfield(cfg.diagnostics, 'makePlannerExecutionDebugPlot') && ...
       cfg.diagnostics.makePlannerExecutionDebugPlot

        if isfield(full_result, 'planner_debug') && ~isempty(full_result.planner_debug)
            plot_planner_execution_debug(full_result);
        end
    end

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
    proxy_costs = [hist.total_cost_huf];

    [proxy_contracts, idx] = sort(proxy_contracts);
    proxy_costs = proxy_costs(idx);

    validation_results = search_result.validation_results;
    val_contracts = [validation_results.contract_kW];
    val_total = [validation_results.total_cost_period_huf];
    val_energy = [validation_results.energy_cost_period_huf];
    val_over = [validation_results.overrun_cost_period_huf];
    val_contract = [validation_results.contract_cost_period_huf];

    [val_contracts, idxv] = sort(val_contracts);
    val_total = val_total(idxv);
    val_energy = val_energy(idxv);
    val_over = val_over(idxv);
    val_contract = val_contract(idxv);

    figure('Name', '4 éves contract keresés összesítő', 'Position', [80, 80, 1350, 900]);

    subplot(2,2,1); hold on; grid on;
    plot(proxy_contracts, proxy_costs, 'k--o', 'LineWidth', 1.2, 'DisplayName', 'Proxy költség');
    plot(val_contracts, val_total, 'b-o', 'LineWidth', 1.8, 'DisplayName', 'Validált költség');
    xline(search_result.best_contract_kW, 'r--', 'LineWidth', 1.4, ...
        'DisplayName', sprintf('Optimum = %.0f kW', search_result.best_contract_kW));
    xlabel('Lekötött teljesítmény [kW]');
    ylabel('Költség [HUF]');
    title('Contract keresés');
    legend('Location', 'best');

    subplot(2,2,2); hold on; grid on;
    plot(val_contracts, val_energy, 'k-', 'LineWidth', 1.3, 'DisplayName', 'Energia');
    plot(val_contracts, val_contract, 'm-', 'LineWidth', 1.3, 'DisplayName', 'Lekötés');
    plot(val_contracts, val_over, 'r-', 'LineWidth', 1.3, 'DisplayName', 'Túllépés');
    xlabel('Lekötött teljesítmény [kW]');
    ylabel('Költség [HUF]');
    title('Költségkomponensek');
    legend('Location', 'best');

    subplot(2,2,3); hold on; grid on;
    max_peak = arrayfun(@(s) max(s.daily_peak_with_bess), validation_results);
    max_peak = max_peak(idxv);
    plot(val_contracts, max_peak, 'b-o', 'LineWidth', 1.4, 'DisplayName', 'Max. napi peak');
    xline(search_result.best_contract_kW, 'r--', 'LineWidth', 1.4, 'DisplayName', 'Optimum');
    xlabel('Lekötött teljesítmény [kW]');
    ylabel('Peak [kW]');
    title('Peak statisztika');
    legend('Location', 'best');

    subplot(2,2,4); hold on; grid on;
    if isfield(validation_results, 'runtime_s')
        val_runtime = [validation_results.runtime_s];
        val_runtime = val_runtime(idxv);
        bar(val_contracts, val_runtime);
    end
    xlabel('Lekötött teljesítmény [kW]');
    ylabel('Futásidő [s]');
    title('Validációs futásidők');
end


function plot_full_horizon_summary_4y(full_result, best_contract)

    days_axis = full_result.days_axis(:).';

    daily_peak_no_bess = full_result.daily_peak_no_bess(:).';
    daily_peak_with_bess = full_result.daily_peak_with_bess(:).';
    daily_energy_cost = full_result.daily_energy_cost(:).';
    daily_deg_cost = full_result.daily_deg_cost(:).';
    daily_overrun_cost = full_result.daily_overrun_cost(:).';
    daily_total_cost = full_result.daily_total_cost(:).';
    daily_bess_throughput = full_result.daily_bess_throughput(:).';
    daily_planned_peak = full_result.daily_planned_peak(:).';
    daily_ref_contract = full_result.daily_ref_contract(:).';

    figure('Name', 'Teljes 4 éves futás összesítő', 'Position', [120, 80, 1400, 980]);

    subplot(4,1,1); hold on; grid on;
    plot(days_axis, daily_peak_no_bess, 'k-', 'LineWidth', 1.0, 'DisplayName', 'Peak BESS nélkül');
    plot(days_axis, daily_peak_with_bess, 'b-', 'LineWidth', 1.2, 'DisplayName', 'Peak BESS-sel');
    plot(days_axis, daily_planned_peak, 'm-', 'LineWidth', 1.0, 'DisplayName', 'MILP peak jelölt');
    yline(best_contract, 'r--', 'LineWidth', 1.4, 'DisplayName', sprintf('Contract = %.0f kW', best_contract));
    ylabel('Peak [kW]');
    title('Napi peak-ek a teljes időszakon');
    legend('Location', 'best');

    subplot(4,1,2); hold on; grid on;
    plot(days_axis, daily_energy_cost, 'k-', 'LineWidth', 1.0, 'DisplayName', 'Energia');
    plot(days_axis, daily_deg_cost, 'b-', 'LineWidth', 1.0, 'DisplayName', 'Degradáció');
    plot(days_axis, daily_overrun_cost, 'r-', 'LineWidth', 1.0, 'DisplayName', 'Túllépés');
    plot(days_axis, daily_total_cost, 'm-', 'LineWidth', 1.4, 'DisplayName', 'Összes napi költség');
    ylabel('Költség [HUF]');
    title('Napi költségek');
    legend('Location', 'best');

    subplot(4,1,3); hold on; grid on;
    bar(days_axis, daily_bess_throughput, 'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'none');
    ylabel('kWh/nap');
    title('Napi BESS throughput');

    subplot(4,1,4); hold on; grid on;
    plot(days_axis, daily_planned_peak, 'm-', 'LineWidth', 1.2, 'DisplayName', 'MILP peak jelölt');
    plot(days_axis, daily_ref_contract, 'r--', 'LineWidth', 1.2, 'DisplayName', 'Contract');
    plot(days_axis, daily_peak_with_bess, 'b:', 'LineWidth', 1.2, 'DisplayName', 'Tényleges peak');
    ylabel('Teljesítmény [kW]');
    xlabel('Nap index');
    title('Peak és contract viszony');
    legend('Location', 'best');
end


function plot_final_day_detail_4y(full_result, pars, day_label)
% PLOT_FINAL_DAY_DETAIL_4Y
%
% Reszletes napi diagnosztikai abra.
% Az elso subplot az actual teljesitmenyaramlasi kepet mutatja.
% DC topologiaban a P_inv_ac_kW/P_pv_ac_kW a kozos inverter kimenete lehet,
% ezert a PV reszhez elsodlegesen a BESS nelkuli PV AC alapjelet hasznaljuk.

    if nargin < 3 || isempty(day_label)
        day_label = 'Részletes napi diagnosztika';
    end

    if ~isfield(full_result, 'final_day') || isempty(full_result.final_day)
        return;
    end

    if ~isfield(full_result.final_day, 'plan') || isempty(full_result.final_day.plan)
        return;
    end

    plan = full_result.final_day.plan;
    res = full_result.final_day.res;
    load = full_result.final_day.load(:);
    pvdc = full_result.final_day.pv(:);
    price = full_result.final_day.price;
    soc0 = full_result.final_day.soc_start;

    n = numel(load);
    dt_h = 24 / n;
    t = (0:n-1).' * dt_h;

    PgridImport = local_get_power(res, 'P_grid_import_kW', 'E_grid_import', n, dt_h, 0);
    PgridExport = local_get_power(res, 'P_grid_export_kW', 'E_grid_export', n, dt_h, 0);

    if isfield(res, 'P_grid_net_kW')
        PgridNet = local_vec(res.P_grid_net_kW, n);
    else
        PgridNet = PgridImport - PgridExport;
    end

    if isfield(res, 'P_bess_actual_kW')
        PbessActual = local_vec(res.P_bess_actual_kW, n);
    elseif isfield(res, 'P_bess_ac_actual_kW')
        PbessActual = local_vec(res.P_bess_ac_actual_kW, n);
    elseif isfield(res, 'P_bess_dc_actual_kW')
        PbessActual = local_vec(res.P_bess_dc_actual_kW, n);
    elseif isfield(res, 'E_bess_ac')
        PbessActual = local_vec(res.E_bess_ac, n) / dt_h;
    elseif isfield(res, 'E_bess_dc')
        PbessActual = local_vec(res.E_bess_dc, n) / dt_h;
    else
        PbessActual = local_vec(res.E_discharged, n) / dt_h - ...
                      local_vec(res.E_stored, n) / dt_h;
    end

    PpvAvailable = local_get_pv_available_ac(res, pvdc, pars, n);
    PspillActual = local_get_power(res, 'P_spill_kW', 'E_curtailment', n, dt_h, 0);

    if all(PspillActual == 0) && isfield(res, 'P_curtailment_kW')
        PspillActual = local_vec(res.P_curtailment_kW, n);
    end

    if isfield(res, 'SoC')
        SocActual = local_vec(res.SoC, n);
    else
        E_net = local_vec(res.E_stored, n) - local_vec(res.E_discharged, n);
        SocActual = soc0 + cumsum(E_net) / pars.E_cap_nom;
    end

    PchActual = max(-PbessActual, 0);
    PdisActual = max(PbessActual, 0);

    PgridPlan = local_plan_vec(plan, 'P_grid_plan', n, NaN);
    PchPlan = local_plan_vec(plan, 'P_ch_plan', n, 0);
    PdisPlan = local_plan_vec(plan, 'P_dis_plan', n, 0);
    PbessPlan = PdisPlan - PchPlan;
    SocPlan = local_plan_vec(plan, 'SoC_plan', n, NaN);

    PspillPlan = local_plan_vec(plan, 'P_spill_plan', n, NaN);

    if all(isnan(PspillPlan))
        PspillPlan = local_plan_vec(plan, 'P_curt_plan', n, NaN);
    end

    PoverPlan = local_plan_vec(plan, 'P_over_plan', n, NaN);

    PgloadPlan = local_plan_vec(plan, 'P_gload_plan', n, NaN);
    PgbattPlan = local_plan_vec(plan, 'P_gbatt_plan', n, NaN);
    PpvloadPlan = local_plan_vec(plan, 'P_pvload_plan', n, NaN);
    PpvbattPlan = local_plan_vec(plan, 'P_pvbatt_plan', n, NaN);
    PbloadPlan = local_plan_vec(plan, 'P_bload_plan', n, NaN);

    if isfield(plan, 'P_grid_limit')
        PgridLimit = plan.P_grid_limit;
    elseif isfield(plan, 'P_contract_safety_factor') && isfield(plan, 'P_contract')
        PgridLimit = plan.P_contract_safety_factor * plan.P_contract;
    else
        PgridLimit = NaN;
    end

    if isfield(plan, 'P_contract')
        Pcontract = plan.P_contract;
    else
        Pcontract = NaN;
    end

    buy = local_vec(price.buy_huf(:), n);

    % =====================================================================
    % Elso subplot: actual energiaaramlasok vizualis felbontasa
    % =====================================================================
    PloadPlot = max(load(:), 0);
    PpvAvailable = max(PpvAvailable(:), 0);
    PgridImport = max(PgridImport(:), 0);
    PdisPlot = max(PdisActual(:), 0);
    PchPlot = max(PchActual(:), 0);

    % A BESS kisutest elobb terhelest fedezo komponenskent abrazoljuk.
    % Igy DC csatolasnal a kozos inverter AC kimenete nem rejti el a BESS
    % kisutest PV -> fogyasztas komponenskent.
    PbessToLoad = min(PdisPlot, PloadPlot);

    remainingLoad = max(PloadPlot - PbessToLoad, 0);
    PpvToLoad = min(PpvAvailable, remainingLoad);

    remainingLoad = max(remainingLoad - PpvToLoad, 0);
    PgridToLoad = min(PgridImport, remainingLoad);

    remainingLoad = max(remainingLoad - PgridToLoad, 0);
    PgridToLoad = PgridToLoad + remainingLoad;

    % PV tobblet csak akkor jelenik meg a fogyasztas folott, ha a PV termeles
    % nagyobb, mint a fogyasztas, es kozben tenyleges BESS toltes tortenik.
    PpvSurplusToBess = min(max(PpvAvailable - PloadPlot, 0), PchPlot);

    plotTol = 1e-8;
    PpvToLoad(PpvToLoad < plotTol) = 0;
    PbessToLoad(PbessToLoad < plotTol) = 0;
    PgridToLoad(PgridToLoad < plotTol) = 0;
    PpvSurplusToBess(PpvSurplusToBess < plotTol) = 0;
    PchPlot(PchPlot < plotTol) = 0;

    figure('Name', 'Részletes napi diagnosztika', ...
        'Position', [80, 40, 1400, 1250]);

    subplot(5,1,1); hold on; grid on;
    title('Teljesítményáramlások');

    h = area(t, [PpvToLoad, PbessToLoad, PgridToLoad, PpvSurplusToBess]);

    h(1).FaceColor = [0.4660 0.6740 0.1880];
    h(1).DisplayName = 'PV -> fogyasztás';

    h(2).FaceColor = [0.0000 0.4470 0.7410];
    h(2).DisplayName = 'BESS -> fogyasztás';

    h(3).FaceColor = [0.6350 0.0780 0.1840];
    h(3).DisplayName = 'Hálózat -> fogyasztás';

    h(4).FaceColor = [0.3010 0.7450 0.9330];
    h(4).DisplayName = 'PV többlet -> BESS';

    plot(t, PchPlot, ...
        'Color', [0.9290 0.6940 0.1250], ...
        'LineWidth', 2, ...
        'DisplayName', 'BESS töltés');

    plot(t, PloadPlot, 'k-', ...
        'LineWidth', 1.3, ...
        'DisplayName', 'Összes fogyasztás');

    if isfinite(Pcontract)
        yline(Pcontract, 'r--', ...
            'LineWidth', 1.3, ...
            'DisplayName', 'Lekötött teljesítmény');
    end

    if isfinite(PgridLimit)
        yline(PgridLimit, 'm--', ...
            'LineWidth', 1.2, ...
            'DisplayName', 'Planner határ');
    end

    ylabel('Teljesítmény [kW]');
    xlim([0 24]);
    legend('Location', 'northeastoutside');

    subplot(5,1,2); hold on; grid on;
    title('Ár és töltési/kisütési időszakok');

    plot(t, buy, 'k-', 'LineWidth', 1.5, 'DisplayName', 'Vételi ár');

    idxCh = find(PchActual > 1e-6);
    idxDis = find(PdisActual > 1e-6);

    if ~isempty(idxCh)
        plot(t(idxCh), buy(idxCh), 'g.', 'MarkerSize', 14, 'DisplayName', 'Töltés');
    end

    if ~isempty(idxDis)
        plot(t(idxDis), buy(idxDis), 'r.', 'MarkerSize', 14, 'DisplayName', 'Kisütés');
    end

    ylabel('Ár [HUF/kWh]');
    xlim([0 24]);
    legend('Location', 'best');

    subplot(5,1,3); hold on; grid on;
    title('Hálózati import és planner');

    plot(t, PgridImport, 'k-', 'LineWidth', 1.5, 'DisplayName', 'Tényleges hálózati import');

    if any(isfinite(PgridPlan))
        plot(t, PgridPlan, 'b--', 'LineWidth', 1.4, 'DisplayName', 'Tervezett hálózati import');
    end

    if any(isfinite(PgridNet))
        plot(t, PgridNet, 'c:', 'LineWidth', 1.1, 'DisplayName', 'Nettó hálózati teljesítmény');
    end

    if isfinite(Pcontract)
        yline(Pcontract, 'r--', 'LineWidth', 1.2, 'DisplayName', 'Lekötött teljesítmény');
    end

    if isfinite(PgridLimit)
        yline(PgridLimit, 'm--', 'LineWidth', 1.2, 'DisplayName', 'Planner határ');
    end

    ylabel('Teljesítmény [kW]');
    xlim([0 24]);
    legend('Location', 'best');

    subplot(5,1,4); hold on; grid on;
    title('BESS teljesítmény és töltöttségi állapot');

    yyaxis left;

    plot(t, PbessActual, 'k-', 'LineWidth', 1.4, 'DisplayName', 'Tényleges BESS teljesítmény');
    plot(t, PbessPlan, 'r--', 'LineWidth', 1.2, 'DisplayName', 'Tervezett BESS teljesítmény');
    plot(t, PspillActual, 'm-', 'LineWidth', 1.1, 'DisplayName', 'Tényleges vágás');

    if any(isfinite(PspillPlan))
        plot(t, PspillPlan, 'm--', 'LineWidth', 1.1, 'DisplayName', 'Tervezett vágás');
    end

    ylabel('Teljesítmény [kW]');

    yyaxis right;

    plot(t, SocActual * 100, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Tényleges SOC');

    if any(isfinite(SocPlan))
        plot(t, SocPlan * 100, 'c--', 'LineWidth', 1.2, 'DisplayName', 'Tervezett SOC');
    end

    ylabel('SOC [%]');
    ylim([0 100]);
    xlim([0 24]);
    legend('Location', 'northeastoutside');

    subplot(5,1,5); hold on; grid on;
    title('Planner felbontott energiaáramai');

    if any(isfinite(PgloadPlan))
        plot(t, PgloadPlan, 'b-', 'LineWidth', 1.2, 'DisplayName', 'Hálózat -> fogyasztás');
    end

    if any(isfinite(PgbattPlan))
        plot(t, PgbattPlan, 'b--', 'LineWidth', 1.2, 'DisplayName', 'Hálózat -> BESS');
    end

    if any(isfinite(PpvloadPlan))
        plot(t, PpvloadPlan, 'g-', 'LineWidth', 1.2, 'DisplayName', 'PV -> fogyasztás');
    end

    if any(isfinite(PpvbattPlan))
        plot(t, PpvbattPlan, 'g--', 'LineWidth', 1.2, 'DisplayName', 'PV -> BESS');
    end

    if any(isfinite(PbloadPlan))
        plot(t, PbloadPlan, 'r-', 'LineWidth', 1.2, 'DisplayName', 'BESS -> fogyasztás');
    end

    if any(isfinite(PspillPlan))
        plot(t, PspillPlan, 'm-', 'LineWidth', 1.2, 'DisplayName', 'Vágás');
    end

    if any(isfinite(PoverPlan))
        plot(t, PoverPlan, 'k--', 'LineWidth', 1.2, 'DisplayName', 'Határ feletti rész');
    end

    ylabel('Teljesítmény [kW]');
    xlabel('Idő [h]');
    xlim([0 24]);
    legend('Location', 'northeastoutside');
end


function plot_selected_day_details_4y(full_result, pars)

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
        return;
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


function P = local_get_power(res, pField, eField, n, dt_h, defaultValue)

    if isfield(res, pField)
        P = local_vec(res.(pField), n);
    elseif isfield(res, eField)
        P = local_vec(res.(eField), n) ./ dt_h;
    else
        P = defaultValue * ones(n, 1);
    end
end


function PpvAvailable = local_get_pv_available_ac(res, pvdc, pars, n)
% LOCAL_GET_PV_AVAILABLE_AC
%
% AC csatolasnal a res.P_pv_ac_kW altalaban tiszta PV AC teljesitmeny.
% DC csatolasnal viszont a res.P_pv_ac_kW/P_inv_ac_kW sokszor a kozos
% inverter kimenete, amely BESS kisutest is tartalmazhat. Emiatt DC esetben
% a P_pv_ac_base_kW vagy a pvdc*inv_eta alapjan szamolt PV-only AC jel a
% helyes vizualis PV komponens.

    if isfield(res, 'P_pv_ac_base_kW')
        PpvAvailable = local_vec(res.P_pv_ac_base_kW, n);
    elseif isfield(res, 'P_pv_available_ac_kW')
        PpvAvailable = local_vec(res.P_pv_available_ac_kW, n);
    elseif isfield(res, 'P_pv_ac_kW') && ~isfield(res, 'P_inv_ac_kW')
        PpvAvailable = local_vec(res.P_pv_ac_kW, n);
    else
        PpvAvailable = min(pvdc(:) .* pars.inv_eta, pars.P_inv_limit_ac);
        PpvAvailable = local_vec(PpvAvailable, n);
    end
end


function v = local_plan_vec(plan, fieldName, n, defaultValue)

    if isfield(plan, fieldName)
        v = plan.(fieldName)(:);
    else
        v = defaultValue * ones(n, 1);
        return;
    end

    v = local_vec(v, n);
end


function v = local_vec(x, n)

    v = x(:);

    if isempty(v)
        v = zeros(n, 1);
        return;
    end

    if numel(v) < n
        v = [v; repmat(v(end), n - numel(v), 1)];
    elseif numel(v) > n
        v = v(1:n);
    end
end


function tf = local_has_contract_search_history(search_result)

    tf = ...
        isstruct(search_result) && ...
        isfield(search_result, 'proxy_history') && ...
        isstruct(search_result.proxy_history) && ...
        isfield(search_result.proxy_history, 'history') && ...
        ~isempty(search_result.proxy_history.history) && ...
        isfield(search_result, 'validation_results') && ...
        ~isempty(search_result.validation_results);
end
