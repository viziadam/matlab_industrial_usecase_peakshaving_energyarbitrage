function figs = plot_hybrid_daily_energy_flow_diagnostics(full_result, pars, cfg)
% PLOT_HYBRID_DAILY_ENERGY_FLOW_DIAGNOSTICS
% Extra diagnostic figures for hybrid AC+DC BESS daily details.
%
% The existing dispatch diagnostic plots remain unchanged. This helper adds
% hybrid-only plots that show separate DC-BESS and AC-BESS actual flows,
% plan flows, charge/discharge powers and SoC trajectories.

    figs = gobjects(0);

    if nargin < 3
        cfg = struct();
    end

    detailDays = local_get_hybrid_detail_days(full_result, cfg);

    if isempty(detailDays)
        return;
    end

    for k = 1:numel(detailDays)

        if ~isfield(detailDays(k), 'final_day') || isempty(detailDays(k).final_day)
            continue;
        end

        dayFigs = local_plot_one_day(detailDays(k).final_day, pars, detailDays(k));

        for j = 1:numel(dayFigs)
            if isgraphics(dayFigs(j), 'figure')
                figs(end + 1) = dayFigs(j); %#ok<AGROW>
            end
        end
    end
end


function fig = local_plot_one_day(day, pars, meta)
% LOCAL_PLOT_ONE_DAY
% Hybrid AC/DC napi reszletes diagnosztikai abra.
%
% Az abra szerkezete szandekosan hasonlo a regi egy-BESS-es napi
% diagnosztikai abrahoz:
%   1) Teljesitmenyaramlasok
%   2) Ar es toltes/kisutesi idoszakok
%   3) Halozati import es planner
%   4) DC/AC BESS teljesitmeny es SoC
%   5) Planner felbontott energiaaramai DC/AC bontasban

    fig = [];

    if ~isfield(day, 'plan') || ~isfield(day, 'res') || ...
       ~isfield(day, 'load') || ~isfield(day, 'pv') || ...
       ~isfield(day, 'price')
        return;
    end

    plan = day.plan;
    res = day.res;

    load = day.load(:);
    pvdc = day.pv(:);
    price = day.price;

    n = numel(load);
    dt_h = 24 / n;
    t = (0:n-1).' * dt_h;

    dayIndex = local_meta(meta, 'day_index', NaN);
    absDay = local_meta(meta, 'abs_day', NaN);

    % =====================================================================
    % Actual power values
    % =====================================================================
    PgridImport = local_power(res, 'P_grid_import_kW', 'E_grid_import', n, dt_h, 0);
    PgridExport = local_power(res, 'P_grid_export_kW', 'E_grid_export', n, dt_h, 0);

    if isfield(res, 'P_grid_net_kW')
        PgridNet = local_fit(res.P_grid_net_kW(:), n, 'P_grid_net_kW');
    else
        PgridNet = PgridImport - PgridExport;
    end

    PpvAvailable = local_get_pv_available_ac_hybrid(res, pvdc, pars, n);

    PpvToLoad = local_power_or_plan(res, plan, ...
        'P_pv_to_load_direct_kW', 'P_pvload_plan', n, 0);

    PgridToLoad = local_power_or_plan(res, plan, ...
        'P_grid_to_load_kW', 'P_gload_plan', n, 0);

    PdcActual = local_power(res, 'P_bess_dc_actual_kW', '', n, dt_h, 0);
    PacActual = local_power(res, 'P_bess_ac_actual_kW', '', n, dt_h, 0);

    PdcChargeActual = max(-PdcActual, 0);
    PdcDischargeActual = max(PdcActual, 0);

    PacChargeActual = max(-PacActual, 0);
    PacDischargeActual = max(PacActual, 0);

    PbessActualTotal = PdcActual + PacActual;
    PchargeActualTotal = PdcChargeActual + PacChargeActual;
    PdischargeActualTotal = PdcDischargeActual + PacDischargeActual;

    PdcToLoadActual = local_power(res, 'P_bess_dc_to_load_kW', '', n, dt_h, 0);
    PacToLoadActual = local_power(res, 'P_bess_ac_to_load_kW', '', n, dt_h, 0);

    PgridToDcActual = local_power(res, 'P_grid_to_bess_dc_kW', '', n, dt_h, 0);
    PgridToAcActual = local_power(res, 'P_grid_to_bess_ac_kW', '', n, dt_h, 0);

    PpvToDcActual = local_power(res, 'P_pv_to_bess_dc_kW', '', n, dt_h, 0);
    PpvToAcActual = local_power(res, 'P_pv_to_bess_ac_kW', '', n, dt_h, 0);

    PcurtActual = local_power(res, 'P_curtailment_kW', 'E_curtailment', n, dt_h, 0);

    SocDcActual = local_power(res, 'SoC_dc', '', n, dt_h, NaN);
    SocAcActual = local_power(res, 'SoC_ac', '', n, dt_h, NaN);

    if isfield(res, 'SoC')
        SocTotalActual = local_fit(res.SoC(:), n, 'SoC');
    else
        SocTotalActual = NaN(n, 1);
    end

    % =====================================================================
    % Plan values
    % =====================================================================
    PgridPlan = local_plan(plan, 'P_grid_plan', n, NaN);

    PdcChargePlan = local_plan(plan, 'P_ch_dc_plan', n, 0);
    PdcDischargePlan = local_plan(plan, 'P_dis_dc_plan', n, 0);
    PacChargePlan = local_plan(plan, 'P_ch_ac_plan', n, 0);
    PacDischargePlan = local_plan(plan, 'P_dis_ac_plan', n, 0);

    PdcPlan = PdcDischargePlan - PdcChargePlan;
    PacPlan = PacDischargePlan - PacChargePlan;
    PbessPlanTotal = PdcPlan + PacPlan;

    SocDcPlan = local_plan(plan, 'SoC_dc_plan', n, NaN);
    SocAcPlan = local_plan(plan, 'SoC_ac_plan', n, NaN);
    SocPlanTotal = local_plan(plan, 'SoC_plan', n, NaN);

    PgloadPlan = local_plan(plan, 'P_gload_plan', n, NaN);
    PpvloadPlan = local_plan(plan, 'P_pvload_plan', n, NaN);

    PgridToDcPlan = local_plan(plan, 'P_gbatt_dc_plan', n, 0);
    PgridToAcPlan = local_plan(plan, 'P_gbatt_ac_plan', n, 0);

    PpvToDcPlan = local_plan(plan, 'P_pvbatt_dc_plan', n, 0);
    PpvToAcPlan = local_plan(plan, 'P_pvbatt_ac_plan', n, 0);

    PdcToLoadPlan = local_plan(plan, 'P_bload_dc_plan', n, 0);
    PacToLoadPlan = local_plan(plan, 'P_bload_ac_plan', n, 0);

    PspillPlan = local_plan(plan, 'P_spill_plan', n, NaN);

    if all(isnan(PspillPlan))
        PspillPlan = local_plan(plan, 'P_curt_plan', n, NaN);
    end

    PoverPlan = local_plan(plan, 'P_over_plan', n, NaN);

    Pcontract = local_scalar_plan(plan, 'P_contract', NaN);
    PgridLimit = local_scalar_plan(plan, 'P_grid_limit', NaN);

    if ~isfinite(PgridLimit)
        if isfield(plan, 'P_contract_safety_factor') && isfield(plan, 'P_contract')
            PgridLimit = plan.P_contract_safety_factor * plan.P_contract;
        end
    end

    buy = local_fit(price.buy_huf(:), n, 'buy_huf');

    % =====================================================================
    % Plot cleanup
    % =====================================================================
    plotTol = 1e-8;

    PpvToLoad(abs(PpvToLoad) < plotTol) = 0;
    PgridToLoad(abs(PgridToLoad) < plotTol) = 0;
    PdcToLoadActual(abs(PdcToLoadActual) < plotTol) = 0;
    PacToLoadActual(abs(PacToLoadActual) < plotTol) = 0;
    PgridToDcActual(abs(PgridToDcActual) < plotTol) = 0;
    PgridToAcActual(abs(PgridToAcActual) < plotTol) = 0;
    PpvToDcActual(abs(PpvToDcActual) < plotTol) = 0;
    PpvToAcActual(abs(PpvToAcActual) < plotTol) = 0;
    PchargeActualTotal(abs(PchargeActualTotal) < plotTol) = 0;
    PcurtActual(abs(PcurtActual) < plotTol) = 0;

    % =====================================================================
    % Figure
    % =====================================================================
    fig = figure('Name', 'Hybrid reszletes napi diagnosztika', ...
        'Position', [80, 40, 1500, 1250]);

    % =====================================================================
    % 1) Teljesitmenyaramlasok
    % =====================================================================
    subplot(5,1,1); hold on; grid on;
    title(sprintf('Teljesitmenyaramlasok | hybrid | day index = %d | abs day = %d', ...
        dayIndex, absDay));

    areaData = [ ...
        max(PpvToLoad, 0), ...
        max(PdcToLoadActual, 0), ...
        max(PacToLoadActual, 0), ...
        max(PgridToLoad, 0), ...
        max(PpvToDcActual + PpvToAcActual, 0)];

    h = area(t, areaData);

    h(1).FaceColor = [0.4660 0.6740 0.1880];
    h(1).DisplayName = 'PV -> fogyasztas';

    h(2).FaceColor = [0.0000 0.4470 0.7410];
    h(2).DisplayName = 'DC BESS -> fogyasztas';

    h(3).FaceColor = [0.4940 0.1840 0.5560];
    h(3).DisplayName = 'AC BESS -> fogyasztas';

    h(4).FaceColor = [0.6350 0.0780 0.1840];
    h(4).DisplayName = 'Halozat -> fogyasztas';

    h(5).FaceColor = [0.3010 0.7450 0.9330];
    h(5).DisplayName = 'PV tobblet -> BESS';

    plot(t, PchargeActualTotal, ...
        'Color', [0.9290 0.6940 0.1250], ...
        'LineWidth', 2.0, ...
        'DisplayName', 'BESS toltes osszesen');

    plot(t, load, 'k-', ...
        'LineWidth', 1.3, ...
        'DisplayName', 'Osszes fogyasztas');

    plot(t, PpvAvailable, ...
        'Color', [0.2 0.5 0.2], ...
        'LineStyle', ':', ...
        'LineWidth', 1.1, ...
        'DisplayName', 'PV elerheto AC oldalon');

    if isfinite(Pcontract)
        yline(Pcontract, 'r--', ...
            'LineWidth', 1.3, ...
            'DisplayName', 'Lekotott teljesitmeny');
    end

    if isfinite(PgridLimit)
        yline(PgridLimit, 'm--', ...
            'LineWidth', 1.2, ...
            'DisplayName', 'Planner hatar');
    end

    ylabel('Teljesitmeny [kW]');
    xlim([0 24]);
    legend('Location', 'northeastoutside');

    % =====================================================================
    % 2) Ar es toltes/kisutesi idoszakok
    % =====================================================================
    subplot(5,1,2); hold on; grid on;
    title('Ar es toltes/kisutesi idoszakok');

    plot(t, buy, 'k-', ...
        'LineWidth', 1.5, ...
        'DisplayName', 'Veteli ar');

    idxDcCh = find(PdcChargeActual > 1e-6);
    idxDcDis = find(PdcDischargeActual > 1e-6);
    idxAcCh = find(PacChargeActual > 1e-6);
    idxAcDis = find(PacDischargeActual > 1e-6);

    if ~isempty(idxDcCh)
        plot(t(idxDcCh), buy(idxDcCh), 'b.', ...
            'MarkerSize', 13, ...
            'DisplayName', 'DC toltes');
    end

    if ~isempty(idxDcDis)
        plot(t(idxDcDis), buy(idxDcDis), 'c.', ...
            'MarkerSize', 13, ...
            'DisplayName', 'DC kisutes');
    end

    if ~isempty(idxAcCh)
        plot(t(idxAcCh), buy(idxAcCh), 'r.', ...
            'MarkerSize', 13, ...
            'DisplayName', 'AC toltes');
    end

    if ~isempty(idxAcDis)
        plot(t(idxAcDis), buy(idxAcDis), 'm.', ...
            'MarkerSize', 13, ...
            'DisplayName', 'AC kisutes');
    end

    ylabel('Ar [HUF/kWh]');
    xlim([0 24]);
    legend('Location', 'best');

    % =====================================================================
    % 3) Halozati import es planner
    % =====================================================================
    subplot(5,1,3); hold on; grid on;
    title('Halozati import es planner');

    plot(t, PgridImport, 'k-', ...
        'LineWidth', 1.5, ...
        'DisplayName', 'Tenyleges halozati import');

    if any(isfinite(PgridPlan))
        plot(t, PgridPlan, 'b--', ...
            'LineWidth', 1.4, ...
            'DisplayName', 'Tervezett halozati import');
    end

    if any(isfinite(PgridNet))
        plot(t, PgridNet, 'c:', ...
            'LineWidth', 1.1, ...
            'DisplayName', 'Netto halozati teljesitmeny');
    end

    if isfinite(Pcontract)
        yline(Pcontract, 'r--', ...
            'LineWidth', 1.2, ...
            'DisplayName', 'Lekotott teljesitmeny');
    end

    if isfinite(PgridLimit)
        yline(PgridLimit, 'm--', ...
            'LineWidth', 1.2, ...
            'DisplayName', 'Planner hatar');
    end

    ylabel('Teljesitmeny [kW]');
    xlim([0 24]);
    legend('Location', 'best');

    % =====================================================================
    % 4) BESS teljesitmeny es toltottsegi allapot
    % =====================================================================
    subplot(5,1,4); hold on; grid on;
    title('DC/AC BESS teljesitmeny es toltottsegi allapot');

    yyaxis left;

    plot(t, PdcActual, 'b-', ...
        'LineWidth', 1.4, ...
        'DisplayName', 'DC BESS tenyleges');

    plot(t, PdcPlan, 'b--', ...
        'LineWidth', 1.2, ...
        'DisplayName', 'DC BESS tervezett');

    plot(t, PacActual, 'r-', ...
        'LineWidth', 1.4, ...
        'DisplayName', 'AC BESS tenyleges');

    plot(t, PacPlan, 'r--', ...
        'LineWidth', 1.2, ...
        'DisplayName', 'AC BESS tervezett');

    plot(t, PbessActualTotal, 'k-', ...
        'LineWidth', 1.1, ...
        'DisplayName', 'BESS osszesen tenyleges');

    plot(t, PbessPlanTotal, 'k--', ...
        'LineWidth', 1.1, ...
        'DisplayName', 'BESS osszesen tervezett');

    if any(isfinite(PcurtActual))
        plot(t, PcurtActual, 'm-', ...
            'LineWidth', 1.0, ...
            'DisplayName', 'Tenyleges vagas');
    end

    if any(isfinite(PspillPlan))
        plot(t, PspillPlan, 'm--', ...
            'LineWidth', 1.0, ...
            'DisplayName', 'Tervezett vagas');
    end

    yline(0, 'k:', 'LineWidth', 0.8);
    ylabel('Teljesitmeny [kW]');

    yyaxis right;

    if any(isfinite(SocDcActual))
        plot(t, SocDcActual * 100, ...
            'Color', [0.0000 0.4470 0.7410], ...
            'LineStyle', '-', ...
            'LineWidth', 1.4, ...
            'DisplayName', 'DC SOC tenyleges');
    end

    if any(isfinite(SocDcPlan))
        plot(t, SocDcPlan * 100, ...
            'Color', [0.0000 0.4470 0.7410], ...
            'LineStyle', '--', ...
            'LineWidth', 1.1, ...
            'DisplayName', 'DC SOC tervezett');
    end

    if any(isfinite(SocAcActual))
        plot(t, SocAcActual * 100, ...
            'Color', [0.8500 0.3250 0.0980], ...
            'LineStyle', '-', ...
            'LineWidth', 1.4, ...
            'DisplayName', 'AC SOC tenyleges');
    end

    if any(isfinite(SocAcPlan))
        plot(t, SocAcPlan * 100, ...
            'Color', [0.8500 0.3250 0.0980], ...
            'LineStyle', '--', ...
            'LineWidth', 1.1, ...
            'DisplayName', 'AC SOC tervezett');
    end

    if any(isfinite(SocTotalActual))
        plot(t, SocTotalActual * 100, ...
            'Color', [0.2 0.2 0.2], ...
            'LineStyle', ':', ...
            'LineWidth', 1.2, ...
            'DisplayName', 'Osszesitett SOC tenyleges');
    end

    if any(isfinite(SocPlanTotal))
        plot(t, SocPlanTotal * 100, ...
            'Color', [0.2 0.2 0.2], ...
            'LineStyle', '-.', ...
            'LineWidth', 1.1, ...
            'DisplayName', 'Osszesitett SOC tervezett');
    end

    ylabel('SOC [%]');
    ylim([0 100]);
    xlim([0 24]);
    legend('Location', 'northeastoutside');

    % =====================================================================
    % 5) Planner felbontott energiaaramai
    % =====================================================================
    subplot(5,1,5); hold on; grid on;
    title('Planner es tenyleges energiaaramok AC/DC BESS bontasban');

    if any(isfinite(PgloadPlan))
        plot(t, PgloadPlan, ...
            'Color', [0.0000 0.4470 0.7410], ...
            'LineStyle', '-', ...
            'LineWidth', 1.1, ...
            'DisplayName', 'Halozat -> fogyasztas plan');
    end

    if any(isfinite(PpvloadPlan))
        plot(t, PpvloadPlan, ...
            'Color', [0.4660 0.6740 0.1880], ...
            'LineStyle', '-', ...
            'LineWidth', 1.1, ...
            'DisplayName', 'PV -> fogyasztas plan');
    end

    plot(t, PgridToDcPlan, ...
        'Color', [0.0000 0.4470 0.7410], ...
        'LineStyle', '--', ...
        'LineWidth', 1.1, ...
        'DisplayName', 'Halozat -> DC BESS plan');

    plot(t, PgridToAcPlan, ...
        'Color', [0.8500 0.3250 0.0980], ...
        'LineStyle', '--', ...
        'LineWidth', 1.1, ...
        'DisplayName', 'Halozat -> AC BESS plan');

    plot(t, PpvToDcPlan, ...
        'Color', [0.0000 0.4470 0.7410], ...
        'LineStyle', ':', ...
        'LineWidth', 1.1, ...
        'DisplayName', 'PV -> DC BESS plan');

    plot(t, PpvToAcPlan, ...
        'Color', [0.8500 0.3250 0.0980], ...
        'LineStyle', ':', ...
        'LineWidth', 1.1, ...
        'DisplayName', 'PV -> AC BESS plan');

    plot(t, PdcToLoadPlan, ...
        'Color', [0.0000 0.4470 0.7410], ...
        'LineStyle', '-', ...
        'LineWidth', 1.3, ...
        'DisplayName', 'DC BESS -> fogyasztas plan');

    plot(t, PacToLoadPlan, ...
        'Color', [0.8500 0.3250 0.0980], ...
        'LineStyle', '-', ...
        'LineWidth', 1.3, ...
        'DisplayName', 'AC BESS -> fogyasztas plan');

    plot(t, PgridToDcActual, ...
        'Color', [0.0000 0.4470 0.7410], ...
        'LineStyle', '-.', ...
        'LineWidth', 0.9, ...
        'DisplayName', 'Halozat -> DC BESS tenyleges');

    plot(t, PgridToAcActual, ...
        'Color', [0.8500 0.3250 0.0980], ...
        'LineStyle', '-.', ...
        'LineWidth', 0.9, ...
        'DisplayName', 'Halozat -> AC BESS tenyleges');

    plot(t, PpvToDcActual, ...
        'Color', [0.0000 0.4470 0.7410], ...
        'LineStyle', ':', ...
        'LineWidth', 0.9, ...
        'DisplayName', 'PV -> DC BESS tenyleges');

    plot(t, PpvToAcActual, ...
        'Color', [0.8500 0.3250 0.0980], ...
        'LineStyle', ':', ...
        'LineWidth', 0.9, ...
        'DisplayName', 'PV -> AC BESS tenyleges');

    if any(isfinite(PoverPlan))
        plot(t, PoverPlan, 'k--', ...
            'LineWidth', 1.1, ...
            'DisplayName', 'Hatar feletti resz');
    end

    ylabel('Teljesitmeny [kW]');
    xlabel('Ido [h]');
    xlim([0 24]);
    legend('Location', 'northeastoutside');

    if isfield(pars, 'dc') && isfield(pars, 'ac')
        sgtitle(sprintf('Hybrid BESS napi diagnosztika | DC %.0f kWh / %.0f kW, AC %.0f kWh / %.0f kW', ...
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

function detailDays = local_get_hybrid_detail_days(full_result, cfg)
% LOCAL_GET_HYBRID_DETAIL_DAYS
% Ugyanazt az elvet koveti, mint a sima diagnosztika:
%   - eloszor a tullepeses napok,
%   - utana a reprezentans detail_days,
%   - a reprezentans napok szama a meglevo detail_cfg/cfg beallitasbol jon.

    detailDays = struct('day_index', {}, 'abs_day', {}, 'type', {}, ...
        'overrun_margin_kW', {}, 'peak_kW', {}, 'final_day', {});

    maxRepPlots = local_get_max_representative_plots(full_result, cfg);

    if isfield(full_result, 'overrun_detail_days') && ~isempty(full_result.overrun_detail_days)
        detailDays = [detailDays, full_result.overrun_detail_days]; %#ok<AGROW>
    end

    if ~isfield(full_result, 'detail_days') || isempty(full_result.detail_days)
        return;
    end

    repDays = full_result.detail_days;

    if ~isempty(detailDays)
        overIdx = [detailDays.day_index];
        repIdx = [repDays.day_index];
        repDays = repDays(~ismember(repIdx, overIdx));
    end

    if isempty(repDays)
        return;
    end

    nRep = min(maxRepPlots, numel(repDays));
    detailDays = [detailDays, repDays(1:nRep)];
end


function maxRepPlots = local_get_max_representative_plots(full_result, cfg)

    maxRepPlots = 8;

    if isfield(full_result, 'detail_cfg') && ...
       isfield(full_result.detail_cfg, 'max_representative_plots')

        maxRepPlots = full_result.detail_cfg.max_representative_plots;
        return;
    end

    if isfield(cfg, 'diagnostics') && ...
       isfield(cfg.diagnostics, 'max_representative_plots')

        maxRepPlots = cfg.diagnostics.max_representative_plots;
        return;
    end

    if isfield(cfg, 'diagnostics') && ...
       isfield(cfg.diagnostics, 'maxRepresentativePlots')

        maxRepPlots = cfg.diagnostics.maxRepresentativePlots;
        return;
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
        error('Hybrid diagnostic vector length mismatch for %s. Expected %d, got %d.', ...
            name, n, numel(v));
    end
end


function value = local_meta(S, fieldName, defaultValue)

    if isstruct(S) && isfield(S, fieldName)
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end


function value = local_scalar_plan(plan, fieldName, defaultValue)

    if isfield(plan, fieldName)
        value = plan.(fieldName);
    else
        value = defaultValue;
    end

    if ~isscalar(value)
        value = value(1);
    end
end


function PpvAvailable = local_get_pv_available_ac_hybrid(res, pvdc, pars, n)

    if isfield(res, 'P_pv_ac_base_kW')
        PpvAvailable = res.P_pv_ac_base_kW(:);
    elseif isfield(res, 'P_pv_ac_kW') && ~isfield(res, 'P_inv_ac_kW')
        PpvAvailable = res.P_pv_ac_kW(:);
    elseif isfield(res, 'P_pv_ac_kW')
        PpvAvailable = res.P_pv_ac_kW(:);
    elseif isfield(pars, 'central_inv_eta_nom')
        PpvAvailable = pvdc(:) .* pars.central_inv_eta_nom;
    else
        PpvAvailable = pvdc(:);
    end

    PpvAvailable = local_fit(PpvAvailable, n, 'PpvAvailable');
end
