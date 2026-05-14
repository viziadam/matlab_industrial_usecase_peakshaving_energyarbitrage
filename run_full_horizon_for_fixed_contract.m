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

    if ~isfield(cfg.dispatch, 'P_grid_hard_cap_kW')
        error('Hiányzó cfg mező: cfg.dispatch.P_grid_hard_cap_kW');
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
    pars.P_grid_hard_cap_kW = cfg.dispatch.P_grid_hard_cap_kW;

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
        contract_state.P_grid_hard_cap_kW = pars.P_grid_hard_cap_kW;

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
                if kk == nDays
                    final_day_detail = day_detail.final_day;
                end
            case "ac"

                error(['AC-csatolt ipari dispatch még nincs implementálva. ', ...
                       'Később itt kell közvetlenül meghívni az AC MILP planner és AC topology függvényeket.']);
                if kk == nDays
                    final_day_detail = day_detail.final_day;
                end
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

    result.daily_peak_with_bess = daily_peak_with_bess;
    result.daily_peak_no_bess = daily_peak_no_bess;
    result.daily_planned_peak = daily_planned_peak;
    result.daily_overrun_cost = daily_overrun_cost;

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