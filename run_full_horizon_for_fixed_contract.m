function [running, result, detail] = run_full_horizon_for_fixed_contract( ...
    day_cache, pars_in, tariff_in, contract_kW, running, cfg, store_detail, detail_cfg)
% RUN_FULL_HORIZON_FOR_FIXED_CONTRACT
%
% Teljes időhorizont futtatása adott contract értékkel.
%
% Fontos:
%   - A DC/AC topológia kapcsoló itt van: cfg.system.bessCoupling
%   - A napi dispatch logika NINCS külön fájlba kiszervezve.
%   - A metrikák továbbra is dayVectors -> update_metrics útvonalon mennek.
%   - Nincs fallback. Hiányzó kötelező mező esetén hiba.

    if nargin < 7
        error('Hiányzó bemenet: store_detail.');
    end

    if nargin < 8
        error('Hiányzó bemenet: detail_cfg.');
    end

    requiredCfgFields = {'system', 'dispatch', 'output'};
    for i = 1:numel(requiredCfgFields)
        if ~isfield(cfg, requiredCfgFields{i})
            error('Hiányzó cfg mező: cfg.%s', requiredCfgFields{i});
        end
    end

    if ~isfield(cfg.system, 'bessCoupling')
        error('Hiányzó cfg mező: cfg.system.bessCoupling');
    end

    if ~isfield(cfg.dispatch, 'P_contract_safety_factor')
        error('Hiányzó cfg mező: cfg.dispatch.P_contract_safety_factor');
    end

    if ~isfield(detail_cfg, 'day_indices')
        error('Hiányzó detail_cfg mező: detail_cfg.day_indices');
    end

    if ~isfield(detail_cfg, 'max_overrun_days')
        error('Hiányzó detail_cfg mező: detail_cfg.max_overrun_days');
    end

    if ~isfield(detail_cfg, 'overrun_tolerance_kW')
        error('Hiányzó detail_cfg mező: detail_cfg.overrun_tolerance_kW');
    end

    pars = pars_in;
    tariff = tariff_in;

    nDays = numel(day_cache);

    if nDays < 1
        error('A day_cache üres.');
    end

    requiredTariffFields = { ...
        'penalty_rate_huf_per_kW_year', ...
        'distribution_energy_rate_huf_per_kWh', ...
        'transmission_energy_rate_huf_per_kWh', ...
        'annual_contracted_power_fee_huf_per_kW', ...
        'annual_base_fee_huf', ...
        'days_in_year'};

    for i = 1:numel(requiredTariffFields)
        if ~isfield(tariff, requiredTariffFields{i})
            error('Hiányzó tariff mező: tariff.%s', requiredTariffFields{i});
        end
    end

    requiredParsFields = { ...
        'E_cap_nom', ...
        'P_rated', ...
        'degradation_cost_per_kWh', ...
        'P_inv_limit_ac'};

    for i = 1:numel(requiredParsFields)
        if ~isfield(pars, requiredParsFields{i})
            error('Hiányzó pars mező: pars.%s', requiredParsFields{i});
        end
    end

    % =====================================================================
    % 1) BESS inicializálás
    % =====================================================================
    init_params = struct( ...
        'target_energy_kWh', pars.E_cap_nom, ...
        'max_power_W', pars.P_rated * 1000, ...
        'initial_soc', 0.5);

    [pack_info, state_bess] = bess_pack_model( ...
        0, ...
        'init', ...
        init_params, ...
        day_cache(1).dt_h, ...
        []);

    if ~isfield(pack_info, 'E_installed_kWh')
        error('A bess_pack_model init kimenete nem tartalmazza: pack_info.E_installed_kWh');
    end

    if ~isfield(state_bess, 'cell_state') || ...
       ~isfield(state_bess.cell_state, 'SOC')
        error('A BESS kezdeti state nem tartalmazza: state_bess.cell_state.SOC');
    end

    pars.E_cap_nom = pack_info.E_installed_kWh;
    pars.P_contract_safety_factor = cfg.dispatch.P_contract_safety_factor;

    % =====================================================================
    % 2) Havi contract állapot
    % =====================================================================
    monthly_overrun_cost_per_kW = tariff.penalty_rate_huf_per_kW_year / 12;

    current_month_id = [];
    current_month_peak = 0;

    % =====================================================================
    % 3) Diagnosztikai tárolók
    % =====================================================================
    detail_days = struct( ...
        'day_index', {}, ...
        'abs_day', {}, ...
        'type', {}, ...
        'overrun_margin_kW', {}, ...
        'peak_kW', {}, ...
        'final_day', {});

    overrun_detail_days = detail_days;

    detail_day_indices = unique(detail_cfg.day_indices(:).');
    detail_day_indices = detail_day_indices( ...
        detail_day_indices >= 1 & detail_day_indices <= nDays);

    % =====================================================================
    % 4) Összefoglaló tömbök
    % =====================================================================
    daily_peak_with_bess = zeros(1, nDays);
    daily_peak_no_bess = zeros(1, nDays);
    daily_planned_peak = NaN(1, nDays);
    daily_overrun_cost = zeros(1, nDays);

    % Diagnosztikai napi költség- és energia tömbök
    daily_contract_cost = zeros(1, nDays);
    daily_energy_cost = zeros(1, nDays);
    daily_deg_cost = zeros(1, nDays);
    daily_total_cost = zeros(1, nDays);
    daily_bess_throughput = zeros(1, nDays);
    daily_ref_contract = contract_kW * ones(1, nDays);

    % =====================================================================
    % 5) Topológia kapcsoló
    % =====================================================================
    coupling = lower(string(cfg.system.bessCoupling));

    if ~(coupling == "dc" || coupling == "ac")
        error('Érvénytelen cfg.system.bessCoupling: %s. Engedélyezett: "dc" vagy "ac".', coupling);
    end

    % =====================================================================
    % 6) Teljes horizon ciklus
    % =====================================================================
    final_day_detail = [];

    planner_debug = struct( ...
    'day_index', {}, ...
    'abs_day', {}, ...
    'contract_kW', {}, ...
    'P_month_max_so_far_kW', {}, ...
    'current_day_of_month', {}, ...
    'P_grid_hard_cap_kW', {}, ...
    'SoC_initial', {}, ...
    'E_cap_nom', {}, ...
    'P_rated', {}, ...
    'P_inv_limit_ac', {}, ...
    'dt_h', {}, ...
    'max_load_48h', {}, ...
    'max_pv_48h', {}, ...
    'mean_price_48h', {}, ...
    'exitflag', {}, ...
    'objective_value', {}, ...
    'max_P_ch_plan', {}, ...
    'max_P_dis_plan', {}, ...
    'max_P_grid_plan', {}, ...
    'soc_plan_start', {}, ...
    'soc_plan_end', {}, ...
    'max_P_bess_req', {}, ...
    'max_P_grid_actual', {}, ...
    'bess_stored_kWh', {}, ...
    'bess_discharged_kWh', {});

    for kk = 1:nDays

        dc = day_cache(kk);

        requiredDayCacheFields = { ...
            'abs_day', ...
            'dt_h', ...
            'P_pv_dc_actual', ...
            'P_load_actual', ...
            'Prices_today', ...
            'P_load_48h', ...
            'P_pv_48h', ...
            'Prices_48h', ...
            'P_grid_no_bess_day', ...
            'no_bess_peak'};

        for f = 1:numel(requiredDayCacheFields)
            if ~isfield(dc, requiredDayCacheFields{f})
                error('Hiányzó day_cache(%d) mező: %s', kk, requiredDayCacheFields{f});
            end
        end

        if ~isfield(dc.Prices_today, 'buy_huf')
            error('Hiányzó mező: day_cache(%d).Prices_today.buy_huf', kk);
        end

        if ~isfield(dc.Prices_48h, 'buy_huf')
            error('Hiányzó mező: day_cache(%d).Prices_48h.buy_huf', kk);
        end

        month_id = local_get_month_id_from_abs_day_4y(dc.abs_day);

        if isempty(current_month_id) || month_id ~= current_month_id
            current_month_id = month_id;
            current_month_peak = 0;
        end

        soc_start_of_day = state_bess.cell_state.SOC;

        % -----------------------------------------------------------------
        % Contract state
        % -----------------------------------------------------------------
        contract_state = struct();

        contract_state.P_contract_kW = contract_kW;
        contract_state.P_month_max_so_far_kW = current_month_peak;
        contract_state.current_day_of_month = mod(dc.abs_day - 1, 30) + 1;

        if ~isfield(pars, 'P_contract_safety_factor')
            error('Hiányzó pars.P_contract_safety_factor a full horizon futásban.');
        end

        % Full horizon alatt a már kiválasztott optimális contract a referencia.
        contract_state.P_grid_hard_cap_kW = contract_kW;
        contract_state.P_contract_safety_factor = pars.P_contract_safety_factor;

        pars.SoC_initial = state_bess.cell_state.SOC;

        % -----------------------------------------------------------------
        % Napi dispatch közvetlenül itt, coupling szerint
        % -----------------------------------------------------------------
        switch coupling

            case "dc"

                plan_full = ems_day_ahead_planner_milp_contract( ...
                    dc.P_load_48h, ...
                    dc.P_pv_48h, ...
                    dc.Prices_48h, ...
                    pars, ...
                    tariff, ...
                    dc.dt_h, ...
                    contract_state, ...
                    15);
                % -----------------------------------------------------------------
                % Eredeti planner-kompatibilis solver/fallback ellenőrzés
                % -----------------------------------------------------------------
                % Az eredeti ems_day_ahead_planner_milp_contract nem ad vissza
                % is_feasible / used_fallback mezőket.
                % Helyette az exitflag és objective_value alapján ellenőrizzük,
                % hogy valódi MILP-megoldás született-e.

                

                nDay = length(dc.P_load_actual);

                requiredPlanFields = { ...
                    'trade_buy_mask', ...
                    'trade_sell_mask', ...
                    'P_ch_plan', ...
                    'P_dis_plan', ...
                    'P_grid_plan', ...
                    'P_curt_plan', ...
                    'SoC_plan', ...
                    'P_month_peak_candidate'};

                for pf = 1:numel(requiredPlanFields)
                    if ~isfield(plan_full, requiredPlanFields{pf})
                        error('Hiányzó plan_full mező: %s', requiredPlanFields{pf});
                    end
                end

                plan_today = plan_full;

                plan_today.trade_buy_mask = plan_full.trade_buy_mask(1:nDay);
                plan_today.trade_sell_mask = plan_full.trade_sell_mask(1:nDay);
                plan_today.P_ch_plan = plan_full.P_ch_plan(1:nDay);
                plan_today.P_dis_plan = plan_full.P_dis_plan(1:nDay);
                plan_today.P_grid_plan = plan_full.P_grid_plan(1:nDay);
                plan_today.P_curt_plan = plan_full.P_curt_plan(1:nDay);
                plan_today.SoC_plan = plan_full.SoC_plan(1:nDay);

                P_bess_dc_req_kW = ems_realtime_decision_dc( ...
                    dc.P_pv_dc_actual, ...
                    dc.P_load_actual, ...
                    plan_today, ...
                    pars);

                [dayRes, state_bess] = topology_dc_coupled( ...
                    P_bess_dc_req_kW, ...
                    dc.P_pv_dc_actual, ...
                    dc.P_load_actual, ...
                    dc.Prices_today, ...
                    pars, ...
                    state_bess, ...
                    dc.dt_h);
                dbg = struct();

                dbg.day_index = kk;
                dbg.abs_day = dc.abs_day;

                dbg.contract_kW = contract_kW;
                dbg.P_month_max_so_far_kW = contract_state.P_month_max_so_far_kW;
                dbg.current_day_of_month = contract_state.current_day_of_month;

                if isfield(contract_state, 'P_grid_hard_cap_kW')
                    dbg.P_grid_hard_cap_kW = contract_state.P_grid_hard_cap_kW;
                else
                    dbg.P_grid_hard_cap_kW = NaN;
                end

                dbg.SoC_initial = pars.SoC_initial;
                dbg.E_cap_nom = pars.E_cap_nom;
                dbg.P_rated = pars.P_rated;
                dbg.P_inv_limit_ac = pars.P_inv_limit_ac;
                dbg.dt_h = dc.dt_h;

                dbg.max_load_48h = max(dc.P_load_48h(:));
                dbg.max_pv_48h = max(dc.P_pv_48h(:));
                dbg.mean_price_48h = mean(dc.Prices_48h.buy_huf(:));

                if isfield(plan_full, 'exitflag')
                    dbg.exitflag = plan_full.exitflag;
                else
                    dbg.exitflag = NaN;
                end

                if isfield(plan_full, 'objective_value')
                    dbg.objective_value = plan_full.objective_value;
                else
                    dbg.objective_value = NaN;
                end

                dbg.max_P_ch_plan = max(abs(plan_today.P_ch_plan(:)));
                dbg.max_P_dis_plan = max(abs(plan_today.P_dis_plan(:)));
                dbg.max_P_grid_plan = max(plan_today.P_grid_plan(:));

                if ~isempty(plan_today.SoC_plan)
                    dbg.soc_plan_start = plan_today.SoC_plan(1);
                    dbg.soc_plan_end = plan_today.SoC_plan(end);
                else
                    dbg.soc_plan_start = NaN;
                    dbg.soc_plan_end = NaN;
                end

                dbg.max_P_bess_req = max(abs(P_bess_dc_req_kW(:)));
                dbg.max_P_grid_actual = max(dayRes.E_grid_import(:) / dc.dt_h);

                dbg.bess_stored_kWh = sum(dayRes.E_stored(:));
                dbg.bess_discharged_kWh = sum(dayRes.E_discharged(:));

                planner_debug(end+1) = dbg; %#ok<AGROW>

                if kk <= 10 || dbg.max_P_dis_plan > 1e-6 || dbg.max_P_ch_plan > 1e-6
                    fprintf(['DBG day=%d abs=%d | contract=%.1f | Pgridcap=%.1f | SoC0=%.3f | ', ...
                        'exit=%g | obj=%.3e | maxCh=%.2f | maxDis=%.2f | ', ...
                        'maxReq=%.2f | maxGridPlan=%.2f | maxGridAct=%.2f | Est=%.2f | Edis=%.2f\n'], ...
                    dbg.day_index, ...
                    dbg.abs_day, ...
                    dbg.contract_kW, ...
                    dbg.P_grid_hard_cap_kW, ...
                    dbg.SoC_initial, ...
                    dbg.exitflag, ...
                    dbg.objective_value, ...
                    dbg.max_P_ch_plan, ...
                    dbg.max_P_dis_plan, ...
                    dbg.max_P_bess_req, ...
                    dbg.max_P_grid_plan, ...
                    dbg.max_P_grid_actual, ...
                    dbg.bess_stored_kWh, ...
                    dbg.bess_discharged_kWh);
                end
                
            case "ac"

                error(['AC-csatolt ipari dispatch még nincs implementálva. ', ...
                       'Később itt kell közvetlenül meghívni az AC MILP planner és AC topology függvényeket.']);
                
        end

        % -----------------------------------------------------------------
        % Kötelező dayRes mezők ellenőrzése
        % -----------------------------------------------------------------
        requiredDayResFields = { ...
            'E_grid_import', ...
            'E_stored', ...
            'E_discharged', ...
            'P_curtailment_kW', ...
            'SoC'};

        for rf = 1:numel(requiredDayResFields)
            if ~isfield(dayRes, requiredDayResFields{rf})
                error(['A topology eredmény nem tartalmazza a szükséges mezőt: dayRes.%s\n', ...
                       'Ne adjunk fallback értéket. Javítsd a topology függvényt vagy a dayVectors metrikalistát.'], ...
                       requiredDayResFields{rf});
            end
        end

        if ~isfield(state_bess, 'cell_state') || ...
           ~isfield(state_bess.cell_state, 'SOC')
            error('A topology utáni state_bess nem tartalmazza: state_bess.cell_state.SOC');
        end

        % -----------------------------------------------------------------
        % Tényleges grid peak és havi overrun
        % -----------------------------------------------------------------
        P_grid_import_kW = dayRes.E_grid_import(:) / dc.dt_h;
        actual_peak = max(P_grid_import_kW);

        prev_overrun = max(0, current_month_peak - contract_kW);

        current_month_peak = max(current_month_peak, actual_peak);

        new_overrun = max(0, current_month_peak - contract_kW);

        overrun_increment_cost_actual = ...
            monthly_overrun_cost_per_kW * (new_overrun - prev_overrun);

        % -----------------------------------------------------------------
        % Költségvektorok
        % -----------------------------------------------------------------
        buy_today = dc.Prices_today.buy_huf(:);

        if numel(buy_today) ~= numel(P_grid_import_kW)
            error('A buy_today és P_grid_import_kW hossza eltér a(z) %d. napon.', kk);
        end

        buy_total = buy_today + ...
            tariff.distribution_energy_rate_huf_per_kWh + ...
            tariff.transmission_energy_rate_huf_per_kWh;

        C_energy_step_HUF = buy_total(:) .* P_grid_import_kW(:) * dc.dt_h;

        C_energy_no_bess_step_HUF = ...
            buy_total(:) .* dc.P_grid_no_bess_day(:) * dc.dt_h;

        C_degradation_step_HUF = pars.degradation_cost_per_kWh * ...
            (dayRes.E_stored(:) + dayRes.E_discharged(:));

        C_overrun_step_HUF = zeros(numel(P_grid_import_kW), 1);
        C_overrun_step_HUF(1) = overrun_increment_cost_actual;

        contract_cost_daily_HUF = ...
            (tariff.annual_contracted_power_fee_huf_per_kW * contract_kW + ...
             tariff.annual_base_fee_huf) / tariff.days_in_year;

        C_contract_step_HUF = zeros(numel(P_grid_import_kW), 1);
        C_contract_step_HUF(1) = contract_cost_daily_HUF;

        C_objective_step_HUF = ...
            C_energy_step_HUF + ...
            C_degradation_step_HUF + ...
            C_overrun_step_HUF + ...
            C_contract_step_HUF;

        % -----------------------------------------------------------------
        % dayVectors -> cfg.output alapú metrikák
        % -----------------------------------------------------------------
        dayVectors = industrial_dayvectors_from_dispatch_result( ...
            dc, ...
            dayRes, ...
            plan_today, ...
            C_energy_step_HUF, ...
            C_energy_no_bess_step_HUF, ...
            C_degradation_step_HUF, ...
            C_overrun_step_HUF, ...
            C_contract_step_HUF, ...
            C_objective_step_HUF);

        running = update_metrics( ...
            running, ...
            dayVectors, ...
            dc.dt_h, ...
            cfg);

        % -----------------------------------------------------------------
        % Napi összefoglaló tömbök
        % -----------------------------------------------------------------
        daily_peak_with_bess(kk) = actual_peak;
        daily_peak_no_bess(kk) = dc.no_bess_peak;
        daily_planned_peak(kk) = plan_today.P_month_peak_candidate;
        daily_overrun_cost(kk) = overrun_increment_cost_actual;

        daily_energy_cost(kk) = sum(C_energy_step_HUF(:));
        daily_deg_cost(kk) = sum(C_degradation_step_HUF(:));
        daily_contract_cost(kk) = sum(C_contract_step_HUF(:));

        % Itt a napi total tartalmazza a napi contract költséget is,
        % mert a jelenlegi objectiveCost_HUF is így épül fel.
        daily_total_cost(kk) = ...
            sum(C_energy_step_HUF(:)) + ...
            sum(C_degradation_step_HUF(:)) + ...
            sum(C_overrun_step_HUF(:)) + ...
            sum(C_contract_step_HUF(:));

        daily_bess_throughput(kk) = ...
            sum(dayRes.E_stored(:) + dayRes.E_discharged(:));

        % -----------------------------------------------------------------
        % Diagnosztika
        % -----------------------------------------------------------------
        if store_detail

            overrun_margin_kW = actual_peak - contract_kW;
            is_requested_detail_day = ismember(kk, detail_day_indices);
            is_overrun_day = overrun_margin_kW > detail_cfg.overrun_tolerance_kW;

            if is_requested_detail_day || is_overrun_day || kk == nDays

                day_detail = struct();

                day_detail.day_index = kk;
                day_detail.abs_day = dc.abs_day;
                day_detail.overrun_margin_kW = overrun_margin_kW;
                day_detail.peak_kW = actual_peak;

                day_detail.final_day = struct();
                day_detail.final_day.plan = plan_today;
                day_detail.final_day.res = dayRes;
                day_detail.final_day.load = dc.P_load_actual;
                day_detail.final_day.pv = dc.P_pv_dc_actual;
                day_detail.final_day.price = dc.Prices_today;
                day_detail.final_day.soc_start = soc_start_of_day;
                day_detail.final_day.dayVectors = dayVectors;

                if kk == nDays
                    final_day_detail = day_detail.final_day;
                end

                if is_requested_detail_day
                    day_detail.type = 'representative';
                    detail_days(end+1) = day_detail; %#ok<AGROW>
                end

                if is_overrun_day
                    day_detail.type = 'overrun';
                    overrun_detail_days(end+1) = day_detail; %#ok<AGROW>

                    [~, ord_over] = sort( ...
                        [overrun_detail_days.overrun_margin_kW], ...
                        'descend');

                    overrun_detail_days = overrun_detail_days(ord_over);

                    if numel(overrun_detail_days) > detail_cfg.max_overrun_days
                        overrun_detail_days = ...
                            overrun_detail_days(1:detail_cfg.max_overrun_days);
                    end
                end
            end
        end
    end

    % =====================================================================
    % 7) Final SoC / SoH
    % =====================================================================
    finalSoC = state_bess.cell_state.SOC;

    if ~isfield(state_bess.cell_state, 'Deg') || ...
       ~isfield(state_bess.cell_state.Deg, 'SOH')
        error('A végső BESS state nem tartalmazza: state_bess.cell_state.Deg.SOH');
    end

    finalSoH = state_bess.cell_state.Deg.SOH;

    % =====================================================================
    % 8) Result struktúra
    % =====================================================================
    result = struct();

    result.contract_kW = contract_kW;

    result.days_axis = [day_cache.abs_day];

    result.planner_debug = planner_debug;

    result.daily_peak_with_bess = daily_peak_with_bess;
    result.daily_peak_no_bess = daily_peak_no_bess;
    result.daily_planned_peak = daily_planned_peak;
    result.daily_overrun_cost = daily_overrun_cost;

    result.daily_energy_cost = daily_energy_cost;
    result.daily_deg_cost = daily_deg_cost;
    result.daily_total_cost = daily_total_cost;
    result.daily_bess_throughput = daily_bess_throughput;
    result.daily_ref_contract = daily_ref_contract;

    result.daily_contract_cost = daily_contract_cost;

    result.finalSoC = finalSoC;
    result.finalSoH = finalSoH;

    result.total_cost_period_huf = running.scalar.objectiveCost_HUF;
    result.energy_cost_period_huf = running.scalar.energyCost_HUF;
    result.degradation_cost_period_huf = running.scalar.degradationCost_HUF;
    result.overrun_cost_period_huf = running.scalar.overrunCost_HUF;
    result.contract_cost_period_huf = running.scalar.contractCost_HUF;

    result.final_day = final_day_detail;

    result.detail_days = detail_days;
    result.overrun_detail_days = overrun_detail_days;
    result.detail_cfg = detail_cfg;

    % =====================================================================
    % 9) Detail
    % =====================================================================
    detail = struct();

    detail.detail_days = detail_days;
    detail.overrun_detail_days = overrun_detail_days;
    detail.detail_cfg = detail_cfg;
end

% =========================================================================
% 30 NAPOS HÓNAPINDEX A JELENLEGI SZIMULÁCIÓS KERETHEZ
% =========================================================================
function month_id = local_get_month_id_from_abs_day_4y(abs_day)
    month_id = floor((abs_day - 1) / 30) + 1;
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