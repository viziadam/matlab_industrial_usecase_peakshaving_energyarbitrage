function figs = plot_hybrid_daily_energy_flow_diagnostics(full_result, pars)
% PLOT_HYBRID_DAILY_ENERGY_FLOW_DIAGNOSTICS
% Extra diagnostic figures for hybrid AC+DC BESS daily details.
%
% The existing dispatch diagnostic plots remain unchanged. This helper adds
% hybrid-only plots that show separate DC-BESS and AC-BESS actual flows,
% plan flows, charge/discharge powers and SoC trajectories.

    figs = gobjects(0);

    if ~isfield(full_result, 'detail_days') || isempty(full_result.detail_days)
        return;
    end

    detailDays = full_result.detail_days;

    for k = 1:numel(detailDays)
        if ~isfield(detailDays(k), 'final_day') || isempty(detailDays(k).final_day)
            continue;
        end

        fig = local_plot_one_day(detailDays(k).final_day, pars, detailDays(k));

        if ~isempty(fig) && isgraphics(fig, 'figure')
            figs(end + 1) = fig; %#ok<AGROW>
        end
    end
end


function fig = local_plot_one_day(day, pars, meta)

    fig = [];

    if ~isfield(day, 'plan') || ~isfield(day, 'res') || ...
       ~isfield(day, 'load') || ~isfield(day, 'pv')
        return;
    end

    plan = day.plan;
    res = day.res;
    load = day.load(:);
    pvdc = day.pv(:);
    n = numel(load);
    dt_h = 24 / n;
    t = (0:n-1).' * dt_h;

    Pgrid = local_power(res, 'P_grid_import_kW', 'E_grid_import', n, dt_h, 0);
    PpvLoad = local_power_or_plan(res, plan, 'P_pv_to_load_direct_kW', 'P_pvload_plan', n, 0);
    PgridLoad = local_power_or_plan(res, plan, 'P_grid_to_load_kW', 'P_gload_plan', n, 0);

    PdcActual = local_power(res, 'P_bess_dc_actual_kW', '', n, dt_h, 0);
    PacActual = local_power(res, 'P_bess_ac_actual_kW', '', n, dt_h, 0);

    PdcCh = max(-PdcActual, 0);
    PdcDis = max(PdcActual, 0);
    PacCh = max(-PacActual, 0);
    PacDis = max(PacActual, 0);

    PdcChPlan = local_plan(plan, 'P_ch_dc_plan', n, 0);
    PdcDisPlan = local_plan(plan, 'P_dis_dc_plan', n, 0);
    PacChPlan = local_plan(plan, 'P_ch_ac_plan', n, 0);
    PacDisPlan = local_plan(plan, 'P_dis_ac_plan', n, 0);

    PgBdc = local_plan(plan, 'P_gbatt_dc_plan', n, 0);
    PgBac = local_plan(plan, 'P_gbatt_ac_plan', n, 0);
    PpvBdc = local_plan(plan, 'P_pvbatt_dc_plan', n, 0);
    PpvBac = local_plan(plan, 'P_pvbatt_ac_plan', n, 0);
    PbDcL = local_plan(plan, 'P_bload_dc_plan', n, 0);
    PbAcL = local_plan(plan, 'P_bload_ac_plan', n, 0);

    PgridBdcActual = local_power(res, 'P_grid_to_bess_dc_kW', '', n, dt_h, 0);
    PgridBacActual = local_power(res, 'P_grid_to_bess_ac_kW', '', n, dt_h, 0);
    PpvBdcActual = local_power(res, 'P_pv_to_bess_dc_kW', '', n, dt_h, 0);
    PpvBacActual = local_power(res, 'P_pv_to_bess_ac_kW', '', n, dt_h, 0);
    PbDcLoadActual = local_power(res, 'P_bess_dc_to_load_kW', '', n, dt_h, 0);
    PbAcLoadActual = local_power(res, 'P_bess_ac_to_load_kW', '', n, dt_h, 0);

    SocDc = local_power(res, 'SoC_dc', '', n, dt_h, NaN);
    SocAc = local_power(res, 'SoC_ac', '', n, dt_h, NaN);
    SocDcPlan = local_plan(plan, 'SoC_dc_plan', n, NaN);
    SocAcPlan = local_plan(plan, 'SoC_ac_plan', n, NaN);

    titleText = sprintf('Hybrid AC/DC napi diagnosztika | day index = %d | abs day = %d', ...
        local_meta(meta, 'day_index', NaN), local_meta(meta, 'abs_day', NaN));

    fig = figure('Name', 'Hybrid AC DC napi diagnosztika', 'Position', [70, 40, 1450, 1250]);

    subplot(5,1,1); hold on; grid on;
    title(titleText);
    area(t, [max(PpvLoad,0), max(PbDcLoadActual,0), max(PbAcLoadActual,0), max(PgridLoad,0)]);
    plot(t, load, 'k-', 'LineWidth', 1.3, 'DisplayName', 'Load');
    plot(t, Pgrid, 'r--', 'LineWidth', 1.1, 'DisplayName', 'Grid import');
    ylabel('kW');
    legend({'PV -> load','DC BESS -> load','AC BESS -> load','Grid -> load','Load','Grid import'}, 'Location', 'northeastoutside');
    xlim([0 24]);

    subplot(5,1,2); hold on; grid on;
    title('Actual BESS teljesitmenyek');
    plot(t, PdcActual, 'b-', 'LineWidth', 1.3, 'DisplayName', 'DC BESS actual (+dis, -ch)');
    plot(t, PacActual, 'r-', 'LineWidth', 1.3, 'DisplayName', 'AC BESS actual (+dis, -ch)');
    plot(t, PdcDis, 'b--', 'LineWidth', 1.0, 'DisplayName', 'DC discharge');
    plot(t, PdcCh, 'b:', 'LineWidth', 1.0, 'DisplayName', 'DC charge');
    plot(t, PacDis, 'r--', 'LineWidth', 1.0, 'DisplayName', 'AC discharge');
    plot(t, PacCh, 'r:', 'LineWidth', 1.0, 'DisplayName', 'AC charge');
    ylabel('kW');
    legend('Location', 'northeastoutside');
    xlim([0 24]);

    subplot(5,1,3); hold on; grid on;
    title('Plan BESS teljesitmenyek');
    plot(t, PdcDisPlan - PdcChPlan, 'b-', 'LineWidth', 1.3, 'DisplayName', 'DC BESS plan (+dis, -ch)');
    plot(t, PacDisPlan - PacChPlan, 'r-', 'LineWidth', 1.3, 'DisplayName', 'AC BESS plan (+dis, -ch)');
    plot(t, PdcChPlan, 'b:', 'LineWidth', 1.0, 'DisplayName', 'DC charge plan');
    plot(t, PdcDisPlan, 'b--', 'LineWidth', 1.0, 'DisplayName', 'DC discharge plan');
    plot(t, PacChPlan, 'r:', 'LineWidth', 1.0, 'DisplayName', 'AC charge plan');
    plot(t, PacDisPlan, 'r--', 'LineWidth', 1.0, 'DisplayName', 'AC discharge plan');
    ylabel('kW');
    legend('Location', 'northeastoutside');
    xlim([0 24]);

    subplot(5,1,4); hold on; grid on;
    title('Plan energiaaramok AC/DC bontasban');
    plot(t, PgBdc, 'b-', 'LineWidth', 1.1, 'DisplayName', 'Grid -> DC BESS plan');
    plot(t, PgBac, 'r-', 'LineWidth', 1.1, 'DisplayName', 'Grid -> AC BESS plan');
    plot(t, PpvBdc, 'b--', 'LineWidth', 1.1, 'DisplayName', 'PV -> DC BESS plan');
    plot(t, PpvBac, 'r--', 'LineWidth', 1.1, 'DisplayName', 'PV -> AC BESS plan');
    plot(t, PbDcL, 'b:', 'LineWidth', 1.1, 'DisplayName', 'DC BESS -> load plan');
    plot(t, PbAcL, 'r:', 'LineWidth', 1.1, 'DisplayName', 'AC BESS -> load plan');
    ylabel('kW');
    legend('Location', 'northeastoutside');
    xlim([0 24]);

    subplot(5,1,5); hold on; grid on;
    title('Actual energiaaramok es SoC');
    yyaxis left;
    plot(t, PgridBdcActual, 'b-', 'LineWidth', 1.0, 'DisplayName', 'Grid -> DC BESS actual');
    plot(t, PgridBacActual, 'r-', 'LineWidth', 1.0, 'DisplayName', 'Grid -> AC BESS actual');
    plot(t, PpvBdcActual, 'b--', 'LineWidth', 1.0, 'DisplayName', 'PV -> DC BESS actual');
    plot(t, PpvBacActual, 'r--', 'LineWidth', 1.0, 'DisplayName', 'PV -> AC BESS actual');
    ylabel('kW');
    yyaxis right;
    plot(t, 100 * SocDc, 'c-', 'LineWidth', 1.3, 'DisplayName', 'DC SoC actual');
    plot(t, 100 * SocAc, 'm-', 'LineWidth', 1.3, 'DisplayName', 'AC SoC actual');
    plot(t, 100 * SocDcPlan, 'c--', 'LineWidth', 1.0, 'DisplayName', 'DC SoC plan');
    plot(t, 100 * SocAcPlan, 'm--', 'LineWidth', 1.0, 'DisplayName', 'AC SoC plan');
    ylabel('SoC [%]');
    ylim([0 100]);
    xlabel('Ido [h]');
    legend('Location', 'northeastoutside');
    xlim([0 24]);

    if isfield(pars, 'dc') && isfield(pars, 'ac')
        sgtitle(sprintf('Hybrid BESS: DC %.0f kWh / %.0f kW, AC %.0f kWh / %.0f kW', ...
            pars.dc.E_cap_nom, pars.dc.P_rated, pars.ac.E_cap_nom, pars.ac.P_rated));
    end
end


function v = local_plan(plan, fieldName, n, defaultValue)
    if isfield(plan, fieldName)
        v = plan.(fieldName)(:);
    else
        v = defaultValue * ones(n, 1);
    end
    v = local_fit(v, n, fieldName);
end

function v = local_power(res, powerField, energyField, n, dt_h, defaultValue)
    if ~isempty(powerField) && isfield(res, powerField)
        v = res.(powerField)(:);
    elseif ~isempty(energyField) && isfield(res, energyField)
        v = res.(energyField)(:) ./ max(dt_h, eps);
    else
        v = defaultValue * ones(n, 1);
    end
    v = local_fit(v, n, powerField);
end

function v = local_power_or_plan(res, plan, powerField, planField, n, defaultValue)
    if isfield(res, powerField)
        v = res.(powerField)(:);
    elseif isfield(plan, planField)
        v = plan.(planField)(:);
    else
        v = defaultValue * ones(n, 1);
    end
    v = local_fit(v, n, powerField);
end

function v = local_fit(v, n, name)
    v = v(:);
    if numel(v) ~= n
        error('Hybrid diagnostic vector length mismatch for %s. Expected %d, got %d.', name, n, numel(v));
    end
end

function value = local_meta(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName)
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end
