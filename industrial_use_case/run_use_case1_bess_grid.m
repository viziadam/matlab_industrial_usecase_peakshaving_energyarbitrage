function use_case1 = run_use_case1_bess_grid()
% RUN_USE_CASE1_BESS_GRID
% 4 éves BESS-rács futtatás PV-hez viszonyított energiaméret alapján.
%
% Kimenet:
%   use_case1 struktúra
%   és ugyanennek mentése: use_case1.mat
%
% Megjegyzés:
%   - A BESS rács itt energiaméret-rács [kWh/kWp].
%   - A teljesítmény méretezése külön C-rate alapú.
%   - A degradációs költséget itt NEM a napi throughputból számoljuk,
%     hanem a végső SoH alapján évesített/periodizált formában mentjük.
%   - A havi peak-ek a jelenlegi 30 napos hónaplogikával számolódnak,
%     mert a contract és overrun logika is ezt használja.

    clc; close all;

    % ================================================================
    % 1) GLOBÁLIS CONFIG
    % ================================================================
    cfg = struct();

    cfg.case_name = 'use_case1';
    cfg.bess_ratio_vec = 0.2:0.2:5.0;   % [kWh/kWp]
    cfg.bess_c_rate_per_h = 0.5;        % P_bess_max = C-rate * E_bess_cap
    cfg.search_cfg.coarse_step_kW = 25;
    cfg.search_cfg.fine_step_kW = 10;
    cfg.search_cfg.validation_offsets_kW = [-20 -10 0 10 20];
    cfg.search_cfg.verbose = false;

    % Ha kell, itt tudsz később bounds-ot adni a contract keresőnek
    % search_optimal_contract_capacity belül most a saját logikáját használja.

    % BESS gazdasági paraméterek
    cfg.battery_replacement_cost_huf_per_kWh = 90000;  % példa
    cfg.cap_floor_frac = 0.80;

    % ================================================================
    % 2) ADATOK BETÖLTÉSE
    % ================================================================
    PV_A = build_pv_cache(11, [95, 275], [274, 274], 0.325);
    PV_B = build_pv_cache(11, [70, 250], [100.5, 100.5], 0.325);
    [Load, Price] = build_load_price_cache();

    nDaysAvailable = min([numel(PV_A), numel(PV_B), numel(Load), numel(Price)]) - 1;
    START_DAY = 1;
    FINAL_DAY = nDaysAvailable;
    nSimDays = FINAL_DAY - START_DAY + 1;

    % ================================================================
    % 3) PV REFERENCE POWER A MÉRETEZÉSHEZ
    % ================================================================
    pv_ref_kW = local_estimate_pv_reference_power_kW(PV_A, PV_B, START_DAY, FINAL_DAY);

    % ================================================================
    % 4) ALAP TARIFA
    % ================================================================
    tariff = create_hungarian_mv_tariff_structure();

    % ================================================================
    % 5) KÖZÖS CACHE A PV-ONLY / BESS FUTÁSOKHOZ
    % ================================================================
    inv_eta_ref = 0.97;
    day_cache = build_full_day_cache_4y(START_DAY, FINAL_DAY, PV_A, PV_B, Load, Price, inv_eta_ref);

    features = build_daily_features_4y(day_cache);

    rep_cfg_proxy.n_typical = 5;
    rep_cfg_proxy.n_extreme = 2;
    rep_set_proxy = local_select_representative_days_pattern_based(features, day_cache, rep_cfg_proxy);

    rep_cfg_valid.n_clusters = 5;
    rep_cfg_valid.n_validation_days_total = 20;
    rep_cfg_valid.n_extreme_force = 4;
    rep_set_valid = local_select_validation_days_pattern_based(features, day_cache, rep_cfg_valid);

    % ================================================================
    % 6) REFERENCIA ESETEK
    % ================================================================
    reference_no_pv_no_bess = evaluate_reference_no_pv_no_bess(day_cache, tariff);
    reference_pv_only       = evaluate_reference_pv_only(day_cache, tariff);

    % ================================================================
    % 7) USE CASE STRUKTÚRA ALAP
    % ================================================================
    use_case1 = struct();
    use_case1.meta = struct();
    use_case1.meta.created_at = datestr(now);
    use_case1.meta.n_days = nSimDays;
    use_case1.meta.pv_reference_kW = pv_ref_kW;
    use_case1.meta.notes = 'BESS grid sweep over full available 4-year-like horizon';

    use_case1.config = cfg;
    use_case1.reference_no_pv_no_bess = reference_no_pv_no_bess;
    use_case1.reference_pv_only = reference_pv_only;

    % ================================================================
    % 8) BESS RÁCS FUTTATÁS
    % ================================================================
    nCases = numel(cfg.bess_ratio_vec);
    cases = struct([]);

    for i = 1:nCases
        t_case = tic;

        ratio_kWh_per_kWp = cfg.bess_ratio_vec(i);

        E_bess_cap = ratio_kWh_per_kWp * pv_ref_kW;      % [kWh]
        P_bess_max = cfg.bess_c_rate_per_h * E_bess_cap; % [kW]

        pars = base_battery_pars_nonideal_(E_bess_cap, P_bess_max);
        pars.P_inv_limit_ac = 550;
        pars.degradation_cost_per_kWh = 5.0;

        pars.battery_replacement_cost_huf_per_kWh = cfg.battery_replacement_cost_huf_per_kWh;
        pars.cap_floor_frac = cfg.cap_floor_frac;

        search_result = search_optimal_contract_capacity( ...
            day_cache, rep_set_proxy, rep_set_valid, pars, tariff, cfg.search_cfg);

        best_contract = search_result.best_contract_kW;

        full_result = run_full_horizon_for_fixed_contract_usecase( ...
            day_cache, pars, tariff, best_contract, false);

        metrics = local_build_use_case_metrics( ...
            full_result, day_cache, pars, tariff, ...
            reference_no_pv_no_bess, reference_pv_only);

        case_i = struct();
        case_i.index = i;
        case_i.bess_ratio_kWh_per_kWp = ratio_kWh_per_kWp;
        case_i.E_bess_cap_kWh = E_bess_cap;
        case_i.P_bess_max_kW = P_bess_max;
        case_i.best_contract_kW = best_contract;
        case_i.search_result = search_result;
        case_i.full_result = full_result;
        case_i.metrics = metrics;
        case_i.runtime_total_s = toc(t_case);

        fprintf('\n=== BESS ESET %d / %d ===\n', i, nCases);
        fprintf('BESS fajlagos meret a PV-hez viszonyitva: %.2f kWh/kWp\n', ratio_kWh_per_kWp);
        fprintf('BESS energiameret: %.2f kWh\n', E_bess_cap);
        fprintf('BESS teljesitmenymeret: %.2f kW\n', P_bess_max);
        fprintf('Optimalis teljesitmenykorlat (contract): %.2f kW\n', best_contract);
        fprintf('Teljes futasi ido erre a BESS meretre: %.2f s\n', case_i.runtime_total_s);

        if isempty(cases)
            cases = repmat(case_i, 1, nCases);
        end
            cases(i) = case_i;
        end

        use_case1.cases = cases;

        % ================================================================
        % 9) MENTÉS
        % ================================================================
        save('use_case1.mat', 'use_case1');
    end


% =========================================================================
% EGYSZERŰSÍTETT, CSENDES TELJES FUTTATÁS FIX CONTRACTTAL
% =========================================================================
function result = run_full_horizon_for_fixed_contract_usecase(day_cache, pars_in, tariff_in, contract_kW, store_detail)

    if nargin < 5
        store_detail = false;
    end

    pars = pars_in;
    tariff = tariff_in;

    nDays = numel(day_cache);

    init_params = struct( ...
        'target_energy_kWh', pars.E_cap_nom, ...
        'max_power_W', pars.P_rated * 1000, ...
        'initial_soc', 0.5);

    [pack_info, state_bess] = bess_pack_model(0, 'init', init_params, 1/12, []);
    pars.E_cap_nom = pack_info.E_installed_kWh;

    monthly_overrun_cost_per_kW = tariff.penalty_rate_huf_per_kW_year / 12;

    current_month_id = [];
    current_month_peak = 0;

    daily_peak_no_bess    = zeros(1, nDays);
    daily_peak_with_bess  = zeros(1, nDays);
    daily_energy_cost     = zeros(1, nDays);
    daily_deg_cost        = zeros(1, nDays);   % itt még throughput-alapú placeholder maradhat
    daily_overrun_cost    = zeros(1, nDays);
    daily_total_cost      = zeros(1, nDays);
    daily_bess_throughput = zeros(1, nDays);
    daily_planned_peak    = zeros(1, nDays);
    daily_ref_contract    = contract_kW * ones(1, nDays);

    daily_grid_import_kWh = zeros(1, nDays);
    daily_grid_export_kWh = zeros(1, nDays);
    daily_pv_dc_kWh       = zeros(1, nDays);
    daily_pv_clip_kWh     = zeros(1, nDays);
    daily_selfcons_ratio  = zeros(1, nDays);
    daily_soh_end         = zeros(1, nDays);
    monthly_peak_series   = zeros(1, nDays); % hónapon belüli futó max diagnosztikára

    plot_plan = [];
    plot_res = [];
    plot_load = [];
    plot_pv = [];
    plot_price = [];
    soc_start_of_final_day = NaN;

    for kk = 1:nDays
        dc = day_cache(kk);

        month_id = local_get_month_id_from_abs_day_4y(dc.abs_day);
        if isempty(current_month_id) || month_id ~= current_month_id
            current_month_id = month_id;
            current_month_peak = 0;
        end

        if kk == nDays
            soc_start_of_final_day = state_bess.cell_state.SOC;
        end

        contract_state = struct();
        contract_state.P_contract_kW = contract_kW;
        contract_state.P_month_max_so_far_kW = current_month_peak;
        contract_state.current_day_of_month = mod(dc.abs_day - 1, 30) + 1;

        % FONTOS:
        % itt nincs hard cap teszt!
        pars.SoC_initial = state_bess.cell_state.SOC;

        plan_full = ems_day_ahead_planner_milp_contract( ...
            dc.P_load_48h, dc.P_pv_48h, dc.Prices_48h, ...
            pars, tariff, dc.dt_h, contract_state);

        nDay = length(dc.P_load_actual);

        plan_today = plan_full;
        plan_today.trade_buy_mask  = plan_full.trade_buy_mask(1:nDay);
        plan_today.trade_sell_mask = plan_full.trade_sell_mask(1:nDay);
        plan_today.P_ch_plan       = plan_full.P_ch_plan(1:nDay);
        plan_today.P_dis_plan      = plan_full.P_dis_plan(1:nDay);
        plan_today.P_grid_plan     = plan_full.P_grid_plan(1:nDay);
        plan_today.P_curt_plan     = plan_full.P_curt_plan(1:nDay);
        plan_today.SoC_plan        = plan_full.SoC_plan(1:nDay);

        P_bess_dc_req_kW = ems_realtime_decision_dc( ...
            dc.P_pv_dc_actual, dc.P_load_actual, plan_today, pars);

        [dayRes, state_bess] = topology_dc_coupled( ...
            P_bess_dc_req_kW, dc.P_pv_dc_actual, dc.P_load_actual, ...
            dc.Prices_today, pars, state_bess, dc.dt_h);

        actual_grid = (dayRes.E_grid_import(:)) / dc.dt_h;
        actual_peak = max(actual_grid);

        prev_overrun = max(0, current_month_peak - contract_kW);
        current_month_peak = max(current_month_peak, actual_peak);
        new_overrun = max(0, current_month_peak - contract_kW);
        overrun_increment_cost_actual = monthly_overrun_cost_per_kW * (new_overrun - prev_overrun);

        buy_today = dc.Prices_today.buy_huf(:);
        buy_total = buy_today + tariff.distribution_energy_rate_huf_per_kWh + ...
                               tariff.transmission_energy_rate_huf_per_kWh;

        energy_cost_actual = sum(buy_total(:) .* actual_grid(:)) * dc.dt_h;

        % Itt csak placeholder napi degradációs költség marad, mert a végső
        % degradációs gazdasági értéket a SoH-ból fogjuk számolni.
        deg_cost_actual = 0;

        pv_dc_day_kWh = sum(dayRes.E_pv_dc);
        grid_import_day_kWh = sum(dayRes.E_grid_import);
        grid_export_day_kWh = sum(dayRes.E_grid_export);
        pv_clip_day_kWh = sum(dayRes.E_clip_inv);

        pv_selfcons_ratio = local_compute_pv_self_consumption_ratio( ...
            pv_dc_day_kWh, grid_export_day_kWh, pv_clip_day_kWh);

        daily_peak_no_bess(kk)    = dc.no_bess_peak;
        daily_peak_with_bess(kk)  = actual_peak;
        daily_energy_cost(kk)     = energy_cost_actual;
        daily_deg_cost(kk)        = deg_cost_actual;
        daily_overrun_cost(kk)    = overrun_increment_cost_actual;
        daily_total_cost(kk)      = energy_cost_actual + deg_cost_actual + overrun_increment_cost_actual;
        daily_bess_throughput(kk) = sum(dayRes.E_stored + dayRes.E_discharged);
        daily_planned_peak(kk)    = plan_today.P_month_peak_candidate;

        daily_grid_import_kWh(kk) = grid_import_day_kWh;
        daily_grid_export_kWh(kk) = grid_export_day_kWh;
        daily_pv_dc_kWh(kk)       = pv_dc_day_kWh;
        daily_pv_clip_kWh(kk)     = pv_clip_day_kWh;
        daily_selfcons_ratio(kk)  = pv_selfcons_ratio;
        daily_soh_end(kk)         = dayRes.SOH_end;
        monthly_peak_series(kk)   = current_month_peak;

        if store_detail && kk == nDays
            plot_plan = plan_today;
            plot_res = dayRes;
            plot_load = dc.P_load_actual;
            plot_pv = dc.P_pv_dc_actual;
            plot_price = dc.Prices_today;
        end
    end

    contract_cost_period = (nDays / tariff.days_in_year) * ...
        (tariff.annual_contracted_power_fee_huf_per_kW * contract_kW + tariff.annual_base_fee_huf);

    result = struct();
    result.contract_kW = contract_kW;

    result.energy_cost_period_huf = sum(daily_energy_cost);
    result.degradation_cost_period_huf = 0; % később SoH-ból képezzük
    result.overrun_cost_period_huf = sum(daily_overrun_cost);
    result.contract_cost_period_huf = contract_cost_period;
    result.total_cost_period_huf = result.energy_cost_period_huf + ...
                                   result.degradation_cost_period_huf + ...
                                   result.overrun_cost_period_huf + ...
                                   result.contract_cost_period_huf;

    result.daily_peak_no_bess = daily_peak_no_bess;
    result.daily_peak_with_bess = daily_peak_with_bess;
    result.daily_energy_cost = daily_energy_cost;
    result.daily_deg_cost = daily_deg_cost;
    result.daily_overrun_cost = daily_overrun_cost;
    result.daily_total_cost = daily_total_cost;
    result.daily_bess_throughput = daily_bess_throughput;
    result.daily_planned_peak = daily_planned_peak;
    result.daily_ref_contract = daily_ref_contract;
    result.days_axis = [day_cache.abs_day];

    result.daily_grid_import_kWh = daily_grid_import_kWh;
    result.daily_grid_export_kWh = daily_grid_export_kWh;
    result.daily_pv_dc_kWh       = daily_pv_dc_kWh;
    result.daily_pv_clip_kWh     = daily_pv_clip_kWh;
    result.daily_selfcons_ratio  = daily_selfcons_ratio;
    result.daily_soh_end         = daily_soh_end;
    result.monthly_peak_series   = monthly_peak_series;

    result.final_day = struct();
    result.final_day.plan = plot_plan;
    result.final_day.res = plot_res;
    result.final_day.load = plot_load;
    result.final_day.pv = plot_pv;
    result.final_day.price = plot_price;
    result.final_day.soc_start = soc_start_of_final_day;
end


% =========================================================================
% REFERENCIA: NO PV / NO BESS
% =========================================================================
function ref = evaluate_reference_no_pv_no_bess(day_cache, tariff)

    nDays = numel(day_cache);

    daily_grid_import_kWh = zeros(1, nDays);
    daily_energy_cost     = zeros(1, nDays);
    daily_peak            = zeros(1, nDays);

    for k = 1:nDays
        dc = day_cache(k);
        P_grid = dc.P_load_actual(:);
        E_grid = sum(P_grid) * dc.dt_h;

        buy_total = dc.Prices_today.buy_huf(:) + ...
            tariff.distribution_energy_rate_huf_per_kWh + ...
            tariff.transmission_energy_rate_huf_per_kWh;

        daily_grid_import_kWh(k) = E_grid;
        daily_energy_cost(k)     = sum(P_grid(:) .* buy_total(:)) * dc.dt_h;
        daily_peak(k)            = max(P_grid);
    end

    contract_eval = local_optimize_contract_for_exogenous_daily_peaks(daily_peak, tariff);

    ref = struct();
    ref.case_name = 'reference_no_pv_no_bess';
    ref.daily_grid_import_kWh = daily_grid_import_kWh;
    ref.daily_peak = daily_peak;
    ref.daily_energy_cost = daily_energy_cost;

    ref.best_contract_kW = contract_eval.best_contract_kW;
    ref.contract_cost_period_huf = contract_eval.contract_cost_period_huf;
    ref.overrun_cost_period_huf  = contract_eval.overrun_cost_period_huf;
    ref.energy_cost_period_huf   = sum(daily_energy_cost);
    ref.total_cost_period_huf    = ref.energy_cost_period_huf + ...
                                   ref.contract_cost_period_huf + ...
                                   ref.overrun_cost_period_huf;

    ref.monthly_peaks_kW = contract_eval.monthly_peaks_kW;
end


% =========================================================================
% REFERENCIA: PV-ONLY (BESS NÉLKÜL)
% =========================================================================
function ref = evaluate_reference_pv_only(day_cache, tariff)

    nDays = numel(day_cache);

    daily_grid_import_kWh = zeros(1, nDays);
    daily_grid_export_kWh = zeros(1, nDays);
    daily_energy_cost     = zeros(1, nDays);
    daily_peak            = zeros(1, nDays);
    daily_pv_dc_kWh       = zeros(1, nDays);
    daily_pv_clip_kWh     = zeros(1, nDays);
    daily_selfcons_ratio  = zeros(1, nDays);

    for k = 1:nDays
        dc = day_cache(k);

        P_grid = dc.P_grid_no_bess_day(:);
        E_grid = sum(P_grid) * dc.dt_h;

        buy_total = dc.Prices_today.buy_huf(:) + ...
            tariff.distribution_energy_rate_huf_per_kWh + ...
            tariff.transmission_energy_rate_huf_per_kWh;

        daily_grid_import_kWh(k) = E_grid;
        daily_energy_cost(k)     = sum(P_grid(:) .* buy_total(:)) * dc.dt_h;
        daily_peak(k)            = max(P_grid);

        pv_dc_day_kWh = sum(dc.P_pv_dc_actual(:)) * dc.dt_h;
        pv_clip_day_kWh = sum(max(dc.P_pv_dc_actual(:) * 0.97 - 550, 0)) * dc.dt_h;

        daily_pv_dc_kWh(k) = pv_dc_day_kWh;
        daily_pv_clip_kWh(k) = pv_clip_day_kWh;
        daily_grid_export_kWh(k) = 0; % egyszerűsített PV-only benchmark
        daily_selfcons_ratio(k) = local_compute_pv_self_consumption_ratio( ...
            pv_dc_day_kWh, 0, pv_clip_day_kWh);
    end

    contract_eval = local_optimize_contract_for_exogenous_daily_peaks(daily_peak, tariff);

    ref = struct();
    ref.case_name = 'reference_pv_only';
    ref.daily_grid_import_kWh = daily_grid_import_kWh;
    ref.daily_grid_export_kWh = daily_grid_export_kWh;
    ref.daily_peak = daily_peak;
    ref.daily_energy_cost = daily_energy_cost;
    ref.daily_pv_dc_kWh = daily_pv_dc_kWh;
    ref.daily_pv_clip_kWh = daily_pv_clip_kWh;
    ref.daily_selfcons_ratio = daily_selfcons_ratio;

    ref.best_contract_kW = contract_eval.best_contract_kW;
    ref.contract_cost_period_huf = contract_eval.contract_cost_period_huf;
    ref.overrun_cost_period_huf  = contract_eval.overrun_cost_period_huf;
    ref.energy_cost_period_huf   = sum(daily_energy_cost);
    ref.total_cost_period_huf    = ref.energy_cost_period_huf + ...
                                   ref.contract_cost_period_huf + ...
                                   ref.overrun_cost_period_huf;

    ref.monthly_peaks_kW = contract_eval.monthly_peaks_kW;
end


% =========================================================================
% USE CASE METRIKÁK
% =========================================================================
function metrics = local_build_use_case_metrics(full_result, day_cache, pars, tariff, ref0, refPV)

    nDays = numel(day_cache);
    years = local_assign_year_index_from_days(nDays);

    % --- nyers éves összegek ---
    annual_grid_import_kWh = local_group_sum_by_year(full_result.daily_grid_import_kWh, years);
    annual_grid_export_kWh = local_group_sum_by_year(full_result.daily_grid_export_kWh, years);
    annual_pv_dc_kWh       = local_group_sum_by_year(full_result.daily_pv_dc_kWh, years);
    annual_pv_clip_kWh     = local_group_sum_by_year(full_result.daily_pv_clip_kWh, years);
    annual_bess_throughput = local_group_sum_by_year(full_result.daily_bess_throughput, years);
    annual_energy_cost     = local_group_sum_by_year(full_result.daily_energy_cost, years);
    annual_overrun_cost    = local_group_sum_by_year(full_result.daily_overrun_cost, years);

    % fix contract költség éves bontás
    annual_contract_cost = local_annualize_fixed_contract_cost( ...
        full_result.contract_kW, tariff, max(years));

    annual_max_grid_kW = local_group_max_by_year(full_result.daily_peak_with_bess, years);
    annual_soh_end     = local_group_last_by_year(full_result.daily_soh_end, years);

    % havi csúcsteljesítmények teljes időszakra
    monthly_peaks_kW = local_compute_monthly_peaks(full_result.daily_peak_with_bess);

    % PV önfogyasztási arány éves
    annual_selfcons_ratio_pct = 100 * local_safe_divide( ...
        annual_pv_dc_kWh - annual_grid_export_kWh - annual_pv_clip_kWh, ...
        annual_pv_dc_kWh);

    % ciklusok / EFC
    annual_efc = local_safe_divide(annual_bess_throughput, 2 * pars.E_cap_nom);
    annual_cycles = annual_efc; % itt ekvivalens teljes ciklusszámot használunk

    % degradációs költség SoH-ból
    annual_degradation_cost = local_compute_annual_degradation_cost_from_soh( ...
        annual_soh_end, pars);

    % teljes éves költség
    annual_total_cost = annual_energy_cost + annual_contract_cost + annual_overrun_cost + annual_degradation_cost;

    % referencia megtakarítások
    ref0_annual_total  = local_build_reference_annual_total(ref0, years);
    refpv_annual_total = local_build_reference_annual_total(refPV, years);

    annual_saving_vs_reference = ref0_annual_total - annual_total_cost;
    annual_saving_vs_pv_only   = refpv_annual_total - annual_total_cost;

    annual_specific_saving_ft_per_kWhBESS = local_safe_divide(annual_saving_vs_pv_only, pars.E_cap_nom);
    annual_specific_saving_ft_per_kWp     = local_safe_divide(annual_saving_vs_pv_only, max(annual_pv_dc_kWh, 1e-9) * 0 + 1); %#ok<NASGU>

    % nettó hozzáadott érték
    % = PV+BESS költségcsökkenés - degradációs költség - többletveszteségek gazd. hatása
    %
    % Többletveszteség gazdasági hatás proxy:
    % BESS throughput * átlagár * veszteségi büntetés helyett egyszerűen
    % nem számoljuk külön részletesen, hanem elmentjük 0-ként és a raw adatokból
    % később pontosítható.
    annual_extra_loss_impact_huf = zeros(size(annual_total_cost));

    annual_net_added_value = annual_saving_vs_pv_only - annual_degradation_cost - annual_extra_loss_impact_huf;

    metrics = struct();

    metrics.annual_grid_import_kWh = annual_grid_import_kWh;
    metrics.annual_grid_export_kWh = annual_grid_export_kWh;
    metrics.annual_max_grid_kW = annual_max_grid_kW;
    metrics.monthly_peaks_kW = monthly_peaks_kW;

    metrics.annual_pv_self_consumption_ratio_pct = annual_selfcons_ratio_pct;
    metrics.annual_pv_clipped_kWh = annual_pv_clip_kWh;

    metrics.annual_bess_energy_throughput_kWh = annual_bess_throughput;
    metrics.annual_cycles = annual_cycles;
    metrics.annual_efc = annual_efc;

    metrics.year_end_soh_pct = 100 * annual_soh_end;

    metrics.annual_energy_cost_huf = annual_energy_cost;
    metrics.annual_contract_cost_huf = annual_contract_cost;
    metrics.annual_overrun_penalty_huf = annual_overrun_cost;
    metrics.annual_degradation_cost_huf = annual_degradation_cost;
    metrics.annual_total_cost_huf = annual_total_cost;

    metrics.annual_saving_vs_reference_huf = annual_saving_vs_reference;
    metrics.annual_saving_vs_pv_only_huf = annual_saving_vs_pv_only;
    metrics.annual_specific_saving_ft_per_kWhBESS = annual_specific_saving_ft_per_kWhBESS;
    metrics.annual_net_added_value_huf = annual_net_added_value;

    % raw mentések későbbi ábrázoláshoz
    metrics.raw.daily_grid_import_kWh = full_result.daily_grid_import_kWh;
    metrics.raw.daily_grid_export_kWh = full_result.daily_grid_export_kWh;
    metrics.raw.daily_pv_dc_kWh       = full_result.daily_pv_dc_kWh;
    metrics.raw.daily_pv_clip_kWh     = full_result.daily_pv_clip_kWh;
    metrics.raw.daily_bess_throughput = full_result.daily_bess_throughput;
    metrics.raw.daily_peak_with_bess  = full_result.daily_peak_with_bess;
    metrics.raw.daily_soh_end         = full_result.daily_soh_end;
end


% =========================================================================
% EXOGÉN CONTRACT OPTIMUM REFERENCIAESETEKHEZ
% =========================================================================
function out = local_optimize_contract_for_exogenous_daily_peaks(daily_peak_kW, tariff)

    contract_vec = 100:10:2000;
    nC = numel(contract_vec);

    total_cost = zeros(1, nC);
    overrun_cost = zeros(1, nC);
    contract_cost = zeros(1, nC);

    monthly_peaks = local_compute_monthly_peaks(daily_peak_kW);

    for i = 1:nC
        c = contract_vec(i);

        overrun_monthly = max(monthly_peaks - c, 0);
        overrun_cost(i) = sum(overrun_monthly) * (tariff.penalty_rate_huf_per_kW_year / 12);
        contract_cost(i) = (numel(daily_peak_kW) / tariff.days_in_year) * ...
            (tariff.annual_contracted_power_fee_huf_per_kW * c + tariff.annual_base_fee_huf);

        total_cost(i) = overrun_cost(i) + contract_cost(i);
    end

    [~, idx] = min(total_cost);

    out = struct();
    out.best_contract_kW = contract_vec(idx);
    out.contract_cost_period_huf = contract_cost(idx);
    out.overrun_cost_period_huf  = overrun_cost(idx);
    out.monthly_peaks_kW = monthly_peaks;
end


% =========================================================================
% SEGÉDFÜGGVÉNYEK
% =========================================================================
function pv_ref_kW = local_estimate_pv_reference_power_kW(PV_A, PV_B, START_DAY, FINAL_DAY)
    pv_ref_kW = 0;
    for d = START_DAY:FINAL_DAY
        Ppv = (PV_A(d).Ppv + PV_B(d).Ppv) / 1000;
        pv_ref_kW = max(pv_ref_kW, max(Ppv));
    end
end

function ratio = local_compute_pv_self_consumption_ratio(pv_dc_kWh, grid_export_kWh, pv_clip_kWh)
    if pv_dc_kWh <= 1e-9
        ratio = 0;
        return;
    end
    ratio = max(0, min(1, (pv_dc_kWh - grid_export_kWh - pv_clip_kWh) / pv_dc_kWh));
end

function month_id = local_get_month_id_from_abs_day_4y(abs_day)
    month_id = floor((abs_day - 1) / 30) + 1;
end

function monthly_peaks = local_compute_monthly_peaks(daily_peak)
    nDays = numel(daily_peak);
    month_id = arrayfun(@local_get_month_id_from_abs_day_4y, 1:nDays);
    nMonths = max(month_id);
    monthly_peaks = zeros(1, nMonths);
    for m = 1:nMonths
        monthly_peaks(m) = max(daily_peak(month_id == m));
    end
end

function years = local_assign_year_index_from_days(nDays)
    years = ceil((1:nDays) / 365);
end

function y = local_group_sum_by_year(x, years)
    nY = max(years);
    y = zeros(1, nY);
    for yy = 1:nY
        y(yy) = sum(x(years == yy));
    end
end

function y = local_group_max_by_year(x, years)
    nY = max(years);
    y = zeros(1, nY);
    for yy = 1:nY
        y(yy) = max(x(years == yy));
    end
end

function y = local_group_last_by_year(x, years)
    nY = max(years);
    y = zeros(1, nY);
    for yy = 1:nY
        idx = find(years == yy, 1, 'last');
        y(yy) = x(idx);
    end
end

function y = local_safe_divide(a, b)
    y = zeros(size(a));
    idx = abs(b) > 1e-12;
    y(idx) = a(idx) ./ b(idx);
end

function annual_contract_cost = local_annualize_fixed_contract_cost(contract_kW, tariff, nYears)
    annual_contract_cost = zeros(1, nYears);
    yearly = tariff.annual_contracted_power_fee_huf_per_kW * contract_kW + tariff.annual_base_fee_huf;
    annual_contract_cost(:) = yearly;
end

function annual_deg_cost = local_compute_annual_degradation_cost_from_soh(annual_soh_end, pars)
    % Egyszerű éves degradációs költség a SoH esésből.
    %
    % Ha az adott év végén a SoH:
    %   [0.995, 0.989, 0.982, ...]
    % akkor az éves DeltaSOH a különbségekből számolódik.
    %
    % Költség = DeltaSOH / (1 - cap_floor) * battery_total_replacement_cost

    nY = numel(annual_soh_end);
    annual_deg_cost = zeros(1, nY);

    if ~isfield(pars, 'battery_replacement_cost_huf_per_kWh')
        return;
    end
    if ~isfield(pars, 'cap_floor_frac')
        pars.cap_floor_frac = 0.80;
    end

    battery_total_cost = pars.battery_replacement_cost_huf_per_kWh * pars.E_cap_nom;
    usable_soh_window = max(1 - pars.cap_floor_frac, 1e-12);

    soh_prev = 1.0;
    for y = 1:nY
        dsoh = max(0, soh_prev - annual_soh_end(y));
        annual_deg_cost(y) = (dsoh / usable_soh_window) * battery_total_cost;
        soh_prev = annual_soh_end(y);
    end
end

function annual_total = local_build_reference_annual_total(ref, years)
    annual_energy = local_group_sum_by_year(ref.daily_energy_cost, years);
    nY = max(years);

    % egyszerű éves bontás a teljes periodikus contract / overrun költségből
    annual_contract = zeros(1, nY);
    annual_overrun  = zeros(1, nY);

    total_days = numel(years);
    for y = 1:nY
        nDaysY = sum(years == y);
        annual_contract(y) = ref.contract_cost_period_huf * nDaysY / total_days;
        annual_overrun(y)  = ref.overrun_cost_period_huf  * nDaysY / total_days;
    end

    annual_total = annual_energy + annual_contract + annual_overrun;
end

function day_cache = build_full_day_cache_4y(START_DAY, FINAL_DAY, PV_A, PV_B, Load, Price, inv_eta)

    nSimDays = FINAL_DAY - START_DAY + 1;
    day_cache = repmat(struct(), 1, nSimDays);

    for d = START_DAY:FINAL_DAY
        ii = d - START_DAY + 1;

        dt_h = PV_A(d).dt_h;

        P_pv_dc_actual = (PV_A(d).Ppv + PV_B(d).Ppv) / 1000;
        P_load_actual  = Load(d).P_load_kW;
        Prices_today   = Price(d);

        P_load_f_today = Load(d).P_load_kW;
        P_pv_f_today   = (PV_A(d).Ppv + PV_B(d).Ppv) / 1000;

        P_load_f_tomorrow = Load(d+1).P_load_kW;
        P_pv_f_tomorrow   = (PV_A(d+1).Ppv + PV_B(d+1).Ppv) / 1000;
        Prices_tomorrow   = Price(d+1);

        P_load_48h = [P_load_f_today, P_load_f_tomorrow];
        P_pv_48h   = [P_pv_f_today,   P_pv_f_tomorrow];

        Prices_48h = struct();
        Prices_48h.buy_huf = [Prices_today.buy_huf, Prices_tomorrow.buy_huf];

        P_grid_no_bess_day = max(P_load_actual - P_pv_dc_actual * inv_eta, 0);

        day_cache(ii).abs_day = d;
        day_cache(ii).dt_h = dt_h;

        day_cache(ii).P_pv_dc_actual = P_pv_dc_actual;
        day_cache(ii).P_load_actual  = P_load_actual;
        day_cache(ii).Prices_today   = Prices_today;

        day_cache(ii).P_load_48h = P_load_48h;
        day_cache(ii).P_pv_48h   = P_pv_48h;
        day_cache(ii).Prices_48h = Prices_48h;

        day_cache(ii).P_grid_no_bess_day = P_grid_no_bess_day;
        day_cache(ii).no_bess_peak = max(P_grid_no_bess_day);
    end
end

function features = build_daily_features_4y(day_cache)

    nDays = numel(day_cache);
    X = zeros(nDays, 10);

    for i = 1:nDays
        dc = day_cache(i);

        P_load = dc.P_load_actual(:);
        P_pv   = dc.P_pv_dc_actual(:) * 0.97;
        P_grid = dc.P_grid_no_bess_day(:);
        p_buy  = dc.Prices_today.buy_huf(:);

        N = numel(P_load);
        time_h = (0:N-1)' * dc.dt_h;

        evening_mask = time_h >= 16 & time_h < 22;
        morning_mask = time_h >= 6 & time_h < 10;

        load_energy = sum(P_load) * dc.dt_h;
        load_peak   = max(P_load);
        load_mean   = mean(P_load);

        pv_energy = sum(P_pv) * dc.dt_h;
        pv_peak   = max(P_pv);

        grid_energy = sum(P_grid) * dc.dt_h;
        grid_peak   = max(P_grid);
        evening_grid_peak = max(P_grid(evening_mask));
        morning_grid_peak = max(P_grid(morning_mask));

        price_mean = mean(p_buy);
        price_spread = max(p_buy) - min(p_buy);

        X(i,:) = [ ...
            load_energy, ...
            load_peak, ...
            load_mean, ...
            pv_energy, ...
            pv_peak, ...
            grid_energy, ...
            grid_peak, ...
            evening_grid_peak, ...
            price_mean, ...
            price_spread ];
    end

    features = struct();
    features.raw = X;
    features.z   = local_zscore(X);
end

function Z = local_zscore(X)
    mu = mean(X, 1);
    sig = std(X, 0, 1);
    sig(sig < 1e-12) = 1;
    Z = (X - mu) ./ sig;
end

function rep_set = local_select_representative_days_pattern_based(features, day_cache, cfg)

    X = features.z;

    n_typical = cfg.n_typical;
    n_extreme = cfg.n_extreme;

    [cluster_id, centers] = local_kmeans_basic(X, n_typical, 50);

    typical_day_indices = zeros(1, n_typical);
    cluster_weights = zeros(1, n_typical);

    for k = 1:n_typical
        idx_k = find(cluster_id == k);
        cluster_weights(k) = numel(idx_k);

        if isempty(idx_k)
            typical_day_indices(k) = 1;
            continue;
        end

        Xk = X(idx_k,:);
        ck = centers(k,:);
        d2 = sum((Xk - ck).^2, 2);
        [~, imin] = min(d2);
        typical_day_indices(k) = idx_k(imin);
    end

    no_bess_peak = arrayfun(@(d) d.no_bess_peak, day_cache);
    [~, idx_sorted_peak] = sort(no_bess_peak, 'descend');

    extreme_day_indices = [];
    for j = 1:numel(idx_sorted_peak)
        cand = idx_sorted_peak(j);
        if ~ismember(cand, typical_day_indices)
            extreme_day_indices(end+1) = cand; %#ok<AGROW>
        end
        if numel(extreme_day_indices) >= n_extreme
            break;
        end
    end

    all_day_indices = [typical_day_indices, extreme_day_indices];

    extreme_weight_each = max(1, round(0.5 * mean(cluster_weights)));

    weights = [cluster_weights, repmat(extreme_weight_each, 1, numel(extreme_day_indices))];
    weights = weights / sum(weights);

    rep_set = struct();
    rep_set.cluster_id = cluster_id;
    rep_set.centers = centers;
    rep_set.typical_day_indices = typical_day_indices;
    rep_set.extreme_day_indices = extreme_day_indices;
    rep_set.all_day_indices = all_day_indices;
    rep_set.weights = weights;
end

function [idx, centers] = local_kmeans_basic(X, K, maxIter)

    [N, D] = size(X);

    rng(42);
    perm = randperm(N, K);
    centers = X(perm, :);

    idx = ones(N,1);

    for it = 1:maxIter
        dist = zeros(N, K);
        for k = 1:K
            diff = X - centers(k,:);
            dist(:,k) = sum(diff.^2, 2);
        end
        [~, idx_new] = min(dist, [], 2);

        if all(idx_new == idx) && it > 1
            break;
        end
        idx = idx_new;

        new_centers = zeros(K, D);
        for k = 1:K
            members = X(idx == k, :);
            if isempty(members)
                new_centers(k,:) = X(randi(N), :);
            else
                new_centers(k,:) = mean(members, 1);
            end
        end

        if max(abs(new_centers(:) - centers(:))) < 1e-8
            centers = new_centers;
            break;
        end

        centers = new_centers;
    end
end

function rep_set = local_select_validation_days_pattern_based(features, day_cache, cfg)

    X = features.z;
    nDays = size(X,1);

    n_clusters = cfg.n_clusters;
    n_total = cfg.n_validation_days_total;
    n_extreme_force = cfg.n_extreme_force;

    [cluster_id, centers] = local_kmeans_basic(X, n_clusters, 50);

    cluster_sizes = zeros(1, n_clusters);
    for k = 1:n_clusters
        cluster_sizes(k) = sum(cluster_id == k);
    end
    cluster_frac = cluster_sizes / sum(cluster_sizes);

    raw_counts = cluster_frac * n_total;
    base_counts = floor(raw_counts);
    remainder = n_total - sum(base_counts);

    frac_part = raw_counts - base_counts;
    [~, idx_frac] = sort(frac_part, 'descend');

    cluster_sample_counts = base_counts;
    for j = 1:remainder
        cluster_sample_counts(idx_frac(j)) = cluster_sample_counts(idx_frac(j)) + 1;
    end

    for k = 1:n_clusters
        if cluster_sizes(k) > 0 && cluster_sample_counts(k) == 0
            cluster_sample_counts(k) = 1;
        end
    end

    while sum(cluster_sample_counts) > n_total
        eligible = find(cluster_sample_counts > 1);
        if isempty(eligible), break; end
        [~, imax] = max(cluster_sample_counts(eligible));
        cluster_sample_counts(eligible(imax)) = cluster_sample_counts(eligible(imax)) - 1;
    end

    no_bess_peak = arrayfun(@(d) d.no_bess_peak, day_cache);
    [~, idx_sorted_peak] = sort(no_bess_peak, 'descend');

    extreme_day_indices = unique(idx_sorted_peak(1:min(n_extreme_force, nDays)));

    validation_days = extreme_day_indices(:).';

    for k = 1:n_clusters
        idx_k = find(cluster_id == k);
        if isempty(idx_k)
            continue;
        end

        need_k = cluster_sample_counts(k);

        already_k = idx_k(ismember(idx_k, validation_days));
        n_already = numel(already_k);
        n_to_add = max(0, need_k - n_already);

        if n_to_add == 0
            continue;
        end

        Xk = X(idx_k,:);
        ck = centers(k,:);
        d2 = sum((Xk - ck).^2, 2);
        [~, order] = sort(d2, 'ascend');
        cand = idx_k(order);

        cand = cand(~ismember(cand, validation_days));
        cand = cand(1:min(n_to_add, numel(cand)));

        validation_days = [validation_days, cand(:).']; %#ok<AGROW>
    end

    if numel(validation_days) < n_total
        remaining = setdiff(1:nDays, validation_days, 'stable');
        n_missing = n_total - numel(validation_days);
        validation_days = [validation_days, remaining(1:min(n_missing, numel(remaining)))];
    end

    if numel(validation_days) > n_total
        [~, ord] = sort(no_bess_peak(validation_days), 'descend');
        validation_days = validation_days(ord);
        validation_days = validation_days(1:n_total);
    end

    validation_days = unique(validation_days, 'stable');

    if numel(validation_days) < n_total
        remaining = setdiff(1:nDays, validation_days, 'stable');
        n_missing = n_total - numel(validation_days);
        validation_days = [validation_days, remaining(1:min(n_missing, numel(remaining)))];
    end

    rep_set = struct();
    rep_set.cluster_id = cluster_id;
    rep_set.centers = centers;
    rep_set.cluster_sizes = cluster_sizes;
    rep_set.cluster_sample_counts = cluster_sample_counts;
    rep_set.extreme_day_indices = extreme_day_indices;
    rep_set.validation_day_indices = sort(validation_days(:).');
end