function plot_hybrid_daily_energy_flow_diagnostics(full_result, pars, cfg)
% PLOT_HYBRID_DAILY_ENERGY_FLOW_DIAGNOSTICS
%
% Hybrid AC+DC BESS részletes napi diagnosztikai ábrák.
%
% Subplot struktúra:
%   1) Teljesítményáramlások
%   2) Ár és töltési/kisütési időszakok
%   3) Hálózati import és planner
%   4) DC BESS teljesítmény és SoC
%   5) AC BESS teljesítmény és SoC

    fprintf('\n--- HYBRID RÉSZLETES DIAGNOSZTIKAI NAPI ÁBRÁK ---\n');

    detail_days = struct([]);

    if isfield(full_result, 'overrun_detail_days') && ~isempty(full_result.overrun_detail_days)
        detail_days = [detail_days, full_result.overrun_detail_days]; %#ok<AGROW>
    end

    if isfield(full_result, 'detail_days') && ~isempty(full_result.detail_days)

        rep_days = full_result.detail_days;

        if ~isempty(detail_days)
            existing_abs_days = [detail_days.abs_day];
            rep_abs_days = [rep_days.abs_day];
            rep_days = rep_days(~ismember(rep_abs_days, existing_abs_days));
        end

        detail_days = [detail_days, rep_days]; %#ok<AGROW>
    end

    if isempty(detail_days)
        fprintf('Nincs eltárolt hybrid részletes nap.\n');
        return;
    end

    max_plots = 8;

    if isfield(full_result, 'detail_cfg') && ...
       isfield(full_result.detail_cfg, 'max_representative_plots')
        max_plots = full_result.detail_cfg.max_representative_plots;
    elseif isfield(cfg, 'diagnostics') && ...
           isfield(cfg.diagnostics, 'maxHybridDailyDiagnosticPlots')
        max_plots = cfg.diagnostics.maxHybridDailyDiagnosticPlots;
    end

    nPlot = min(max_plots, numel(detail_days));

    fprintf('Hybrid részletes napok plottolása: %d db\n', nPlot);

    for i = 1:nPlot

        day_detail = detail_days(i);

        if ~isfield(day_detail, 'final_day') || isempty(day_detail.final_day)
            continue;
        end

        fd = day_detail.final_day;

        if ~isfield(fd, 'plan') || isempty(fd.plan) || ...
           ~isfield(fd, 'res')  || isempty(fd.res)
            continue;
        end

        label = sprintf( ...
            'Hybrid részletes napi diagnosztika | day index = %d | abs day = %d', ...
            day_detail.day_index, ...
            day_detail.abs_day);

        local_plot_one_hybrid_day(fd, pars, label, day_detail);
    end
end


function local_plot_one_hybrid_day(fd, pars, day_label, day_detail)

    plan = fd.plan;
    res = fd.res;

    load = fd.load(:);
    pvdc = fd.pv(:);
    price = fd.price;

    n = numel(load);
    dt_h = 24 / n;
    t = (0:n-1).' * dt_h;

    % =====================================================================
    % Actual topology values
    % =====================================================================

    PgridImport = local_get_power(res, 'P_grid_import_kW', 'E_grid_import', n, dt_h, 0);
    PgridExport = local_get_power(res, 'P_grid_export_kW', 'E_grid_export', n, dt_h, 0);

    if isfield(res, 'P_grid_net_kW')
        PgridNet = local_vec(res.P_grid_net_kW, n);
    else
        PgridNet = PgridImport - PgridExport;
    end

    PpvToLoad = local_get_power(res, 'P_pv_to_load_direct_kW', '', n, dt_h, 0);
    PgridToLoad = local_get_power(res, 'P_grid_to_load_kW', '', n, dt_h, 0);

    PdcBessToLoad = local_get_power(res, 'P_bess_dc_to_load_kW', '', n, dt_h, 0);
    PacBessToLoad = local_get_power(res, 'P_bess_ac_to_load_kW', '', n, dt_h, 0);

    PpvToBessDc = local_get_power(res, 'P_pv_to_bess_dc_kW', '', n, dt_h, 0);
    PpvToBessAc = local_get_power(res, 'P_pv_to_bess_ac_kW', '', n, dt_h, 0);

    PgridToBessDc = local_get_power(res, 'P_grid_to_bess_dc_kW', '', n, dt_h, 0);
    PgridToBessAc = local_get_power(res, 'P_grid_to_bess_ac_kW', '', n, dt_h, 0);

    PdcActual = local_get_power(res, 'P_bess_dc_actual_kW', '', n, dt_h, 0);
    PacActual = local_get_power(res, 'P_bess_ac_actual_kW', '', n, dt_h, 0);

    PdcChargeActual = max(-PdcActual, 0);
    PdcDisActual = max(PdcActual, 0);

    PacChargeActual = max(-PacActual, 0);
    PacDisActual = max(PacActual, 0);

    PdcAcTotalActual = PdcActual + PacActual;

    if isfield(res, 'SoC_dc')
        SocDcActual = local_vec(res.SoC_dc, n);
    else
        SocDcActual = NaN(n, 1);
    end

    if isfield(res, 'SoC_ac')
        SocAcActual = local_vec(res.SoC_ac, n);
    else
        SocAcActual = NaN(n, 1);
    end

    % =====================================================================
    % Planner values
    % =====================================================================

    PgridPlan = local_plan_vec(plan, 'P_grid_plan', n, NaN);

    PdcChPlan = local_plan_vec(plan, 'P_ch_dc_plan', n, 0);
    PdcDisPlan = local_plan_vec(plan, 'P_dis_dc_plan', n, 0);
    PdcPlan = PdcDisPlan - PdcChPlan;

    PacChPlan = local_plan_vec(plan, 'P_ch_ac_plan', n, 0);
    PacDisPlan = local_plan_vec(plan, 'P_dis_ac_plan', n, 0);
    PacPlan = PacDisPlan - PacChPlan;

    SocDcPlan = local_plan_vec(plan, 'SoC_dc_plan', n, NaN);
    SocAcPlan = local_plan_vec(plan, 'SoC_ac_plan', n, NaN);

    PoverPlan = local_plan_vec(plan, 'P_over_plan', n, NaN);

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
    % Plot preparation
    % =====================================================================

    plotTol = 1e-8;

    PpvToLoad(PpvToLoad < plotTol) = 0;
    PgridToLoad(PgridToLoad < plotTol) = 0;
    PdcBessToLoad(PdcBessToLoad < plotTol) = 0;
    PacBessToLoad(PacBessToLoad < plotTol) = 0;
    PpvToBessDc(PpvToBessDc < plotTol) = 0;
    PpvToBessAc(PpvToBessAc < plotTol) = 0;
    PgridToBessDc(PgridToBessDc < plotTol) = 0;
    PgridToBessAc(PgridToBessAc < plotTol) = 0;

    PdcChargeActual(PdcChargeActual < plotTol) = 0;
    PacChargeActual(PacChargeActual < plotTol) = 0;
    PdcDisActual(PdcDisActual < plotTol) = 0;
    PacDisActual(PacDisActual < plotTol) = 0;

    PdcChargeTotal = PpvToBessDc + PgridToBessDc;
    PacChargeTotal = PpvToBessAc + PgridToBessAc;

    % =====================================================================
    % Figure
    % =====================================================================

    figure('Name', 'Hybrid részletes napi diagnosztika', ...
        'Position', [40, 30, 1700, 1250]);

    sgtitle(day_label);

    % =====================================================================
    % 1) Teljesítményáramlások
    % =====================================================================

    subplot(5,1,1); hold on; grid on;
    title('Teljesítményáramlások');

    h = area(t, [ ...
        PpvToLoad(:), ...
        PdcBessToLoad(:), ...
        PacBessToLoad(:), ...
        PgridToLoad(:), ...
        PpvToBessDc(:), ...
        PpvToBessAc(:)]);

    h(1).FaceColor = [0.4660 0.6740 0.1880];
    h(1).DisplayName = 'PV -> fogyasztás';

    h(2).FaceColor = [0.0000 0.4470 0.7410];
    h(2).DisplayName = 'DC BESS -> fogyasztás';

    h(3).FaceColor = [0.4940 0.1840 0.5560];
    h(3).DisplayName = 'AC BESS -> fogyasztás';

    h(4).FaceColor = [0.6350 0.0780 0.1840];
    h(4).DisplayName = 'Hálózat -> fogyasztás';

    h(5).FaceColor = [0.3010 0.7450 0.9330];
    h(5).DisplayName = 'PV -> DC BESS';

    h(6).FaceColor = [0.9290 0.6940 0.1250];
    h(6).DisplayName = 'PV -> AC BESS';

    plot(t, PdcChargeTotal, ...
        'Color', [0.0000 0.4470 0.7410], ...
        'LineWidth', 2.0, ...
        'DisplayName', 'DC BESS töltés');

    plot(t, PacChargeTotal, ...
        'Color', [0.8500 0.3250 0.0980], ...
        'LineWidth', 2.0, ...
        'LineStyle', '--', ...
        'DisplayName', 'AC BESS töltés');

    plot(t, load, 'k-', ...
        'LineWidth', 1.3, ...
        'DisplayName', 'Összes fogyasztás');

    if isfinite(Pcontract)
        yline(Pcontract, 'r--', ...
            'LineWidth', 1.2, ...
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

    % =====================================================================
    % 2) Ár és töltési/kisütési időszakok
    % =====================================================================

    subplot(5,1,2); hold on; grid on;
    title('Ár és töltési/kisütési időszakok');

    plot(t, buy, 'k-', ...
        'LineWidth', 1.5, ...
        'DisplayName', 'Vételi ár');

    idxDcCh = find(PdcChargeActual > 1e-6);
    idxDcDis = find(PdcDisActual > 1e-6);
    idxAcCh = find(PacChargeActual > 1e-6);
    idxAcDis = find(PacDisActual > 1e-6);

    if ~isempty(idxDcCh)
        plot(t(idxDcCh), buy(idxDcCh), 'b.', ...
            'MarkerSize', 12, ...
            'DisplayName', 'DC töltés');
    end

    if ~isempty(idxDcDis)
        plot(t(idxDcDis), buy(idxDcDis), 'c.', ...
            'MarkerSize', 12, ...
            'DisplayName', 'DC kisütés');
    end

    if ~isempty(idxAcCh)
        plot(t(idxAcCh), buy(idxAcCh), 'r.', ...
            'MarkerSize', 12, ...
            'DisplayName', 'AC töltés');
    end

    if ~isempty(idxAcDis)
        plot(t(idxAcDis), buy(idxAcDis), 'm.', ...
            'MarkerSize', 12, ...
            'DisplayName', 'AC kisütés');
    end

    ylabel('Ár [HUF/kWh]');
    xlim([0 24]);
    legend('Location', 'best');

    % =====================================================================
    % 3) Hálózati import és planner
    % =====================================================================

    subplot(5,1,3); hold on; grid on;
    title('Hálózati import és planner');

    plot(t, PgridImport, 'k-', ...
        'LineWidth', 1.5, ...
        'DisplayName', 'Tényleges hálózati import');

    if any(isfinite(PgridPlan))
        plot(t, PgridPlan, 'b--', ...
            'LineWidth', 1.4, ...
            'DisplayName', 'Tervezett hálózati import');
    end

    if any(isfinite(PgridNet))
        plot(t, PgridNet, 'c:', ...
            'LineWidth', 1.1, ...
            'DisplayName', 'Nettó hálózati teljesítmény');
    end

    if isfinite(Pcontract)
        yline(Pcontract, 'r--', ...
            'LineWidth', 1.2, ...
            'DisplayName', 'Lekötött teljesítmény');
    end

    if isfinite(PgridLimit)
        yline(PgridLimit, 'm--', ...
            'LineWidth', 1.2, ...
            'DisplayName', 'Planner határ');
    end

    ylabel('Teljesítmény [kW]');
    xlim([0 24]);
    legend('Location', 'best');

    % =====================================================================
    % 4) DC BESS teljesítmény és SoC
    % =====================================================================

    subplot(5,1,4); hold on; grid on;
    title('DC BESS teljesítmény és töltöttségi állapot');

    yyaxis left;

    plot(t, PdcActual, 'b-', ...
        'LineWidth', 1.5, ...
        'DisplayName', 'DC BESS tényleges');

    plot(t, PdcPlan, 'b--', ...
        'LineWidth', 1.3, ...
        'DisplayName', 'DC BESS tervezett');

    yline(0, 'k:', ...
        'LineWidth', 1.0, ...
        'DisplayName', '0 kW');

    ylabel('Teljesítmény [kW]');

    yyaxis right;

    if any(isfinite(SocDcActual))
        plot(t, SocDcActual * 100, 'k-', ...
            'LineWidth', 1.4, ...
            'DisplayName', 'DC SoC tényleges');
    end

    if any(isfinite(SocDcPlan))
        plot(t, SocDcPlan * 100, 'k--', ...
            'LineWidth', 1.2, ...
            'DisplayName', 'DC SoC tervezett');
    end

    ylabel('SoC [%]');
    ylim([0 100]);
    xlim([0 24]);
    legend('Location', 'northeastoutside');

    % =====================================================================
    % 5) AC BESS teljesítmény és SoC
    % =====================================================================

    subplot(5,1,5); hold on; grid on;
    title('AC BESS teljesítmény és töltöttségi állapot');

    yyaxis left;

    plot(t, PacActual, 'r-', ...
        'LineWidth', 1.5, ...
        'DisplayName', 'AC BESS tényleges');

    plot(t, PacPlan, 'r--', ...
        'LineWidth', 1.3, ...
        'DisplayName', 'AC BESS tervezett');

    yline(0, 'k:', ...
        'LineWidth', 1.0, ...
        'DisplayName', '0 kW');

    ylabel('Teljesítmény [kW]');

    yyaxis right;

    if any(isfinite(SocAcActual))
        plot(t, SocAcActual * 100, 'k-', ...
            'LineWidth', 1.4, ...
            'DisplayName', 'AC SoC tényleges');
    end

    if any(isfinite(SocAcPlan))
        plot(t, SocAcPlan * 100, 'k--', ...
            'LineWidth', 1.2, ...
            'DisplayName', 'AC SoC tervezett');
    end

    ylabel('SoC [%]');
    ylim([0 100]);
    xlim([0 24]);
    xlabel('Idő [h]');
    legend('Location', 'northeastoutside');
end

function v = local_get_power(res, powerField, energyField, n, dt_h, defaultValue)

    if ~isempty(powerField) && isfield(res, powerField)
        v = res.(powerField)(:);

    elseif ~isempty(energyField) && isfield(res, energyField)
        v = res.(energyField)(:) ./ max(dt_h, eps);

    else
        v = defaultValue * ones(n, 1);
    end

    v = local_vec(v, n);
end


function v = local_vec(v, n)

    v = v(:);

    if numel(v) ~= n
        error('Hybrid diagnostic vector length mismatch. Expected %d, got %d.', ...
            n, numel(v));
    end
end


function v = local_plan_vec(plan, fieldName, n, defaultValue)

    if isfield(plan, fieldName)
        v = plan.(fieldName)(:);
    else
        v = defaultValue * ones(n, 1);
    end

    v = local_vec(v, n);
end