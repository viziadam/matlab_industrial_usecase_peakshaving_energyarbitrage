function summary = analyze_no_bess_cost_fixed_contract(contract_kW, start_day, final_day)

% ANALYZE_NO_BESS_COST_FIXED_CONTRACT
% No-BESS referencia költségelemzés fix lekötött teljesítmény mellett.
%
% Közvetlenül hívható függvény, belül felépíti a napi cache-t.
%
% Bemenet:
%   contract_kW - vizsgált lekötött teljesítmény [kW]
%   start_day   - kezdő nap index (opcionális)
%   final_day   - záró nap index (opcionális)
%
% Példa:
%   summary = analyze_no_bess_cost_fixed_contract(800);
%   summary = analyze_no_bess_cost_fixed_contract(800, 1, 365);
%
% Külső függőségek:
%   build_pv_cache
%   build_load_price_cache
%   create_hungarian_mv_tariff_structure

    if nargin < 1 || isempty(contract_kW)
        error('Adj meg egy contract teljesitmenyt kW-ban.');
    end

    fprintf('\n=====================================================\n');
    fprintf('NO-BESS KOLTSEGELEMZES FIX CONTRACT MELLETT\n');
    fprintf('Vizsgalt contract: %.2f kW\n', contract_kW);
    fprintf('=====================================================\n');

    % ---------------------------------------------------------------------
    % ADATBETOLTES
    % ---------------------------------------------------------------------
    fprintf('Adatok betoltese...\n');

    PV_A = build_pv_cache(11, [95, 275], [274, 274], 0.325);
    PV_B = build_pv_cache(11, [70, 250], [100.5, 100.5], 0.325);
    [Load, Price] = build_load_price_cache();
    tariff = create_hungarian_mv_tariff_structure();

    nDaysAvailable = min([numel(PV_A), numel(PV_B), numel(Load), numel(Price)]) - 1;

    if nargin < 2 || isempty(start_day)
        start_day = 1;
    end
    if nargin < 3 || isempty(final_day)
        final_day = nDaysAvailable;
    end

    start_day = max(1, start_day);
    final_day = min(nDaysAvailable, final_day);

    if final_day < start_day
        error('A final_day nem lehet kisebb, mint a start_day.');
    end

    fprintf('Vizsgalt idoszak: %d - %d nap\n', start_day, final_day);

    % ---------------------------------------------------------------------
    % TARIFA DEFAULTOK
    % ---------------------------------------------------------------------
    if ~isfield(tariff, 'distribution_energy_rate_huf_per_kWh')
        tariff.distribution_energy_rate_huf_per_kWh = 8.39;
    end
    if ~isfield(tariff, 'transmission_energy_rate_huf_per_kWh')
        tariff.transmission_energy_rate_huf_per_kWh = 3.39;
    end
    if ~isfield(tariff, 'annual_contracted_power_fee_huf_per_kW')
        tariff.annual_contracted_power_fee_huf_per_kW = 15924;
    end
    if ~isfield(tariff, 'annual_base_fee_huf')
        tariff.annual_base_fee_huf = 216504;
    end
    if ~isfield(tariff, 'days_in_year')
        tariff.days_in_year = 365;
    end
    if ~isfield(tariff, 'months_in_year')
        tariff.months_in_year = 12;
    end
    if ~isfield(tariff, 'penalty_rate_huf_per_kW_year')
        tariff.penalty_rate_huf_per_kW_year = 4.0 * tariff.annual_contracted_power_fee_huf_per_kW;
    end

    % ---------------------------------------------------------------------
    % NAPI CACHE FELÉPÍTÉSE BELSŐLEG
    % ---------------------------------------------------------------------
    fprintf('Napi cache epitese...\n');
    inv_eta_ref = 0.97;

    day_cache = local_build_day_cache_for_no_bess( ...
        start_day, final_day, PV_A, PV_B, Load, Price, inv_eta_ref);

    % ---------------------------------------------------------------------
    % ALAP ADATOK
    % ---------------------------------------------------------------------
    nDays = numel(day_cache);
    days_in_year = tariff.days_in_year;

    month_ids = zeros(1, nDays);
    daily_peak = zeros(1, nDays);
    daily_energy_cost = zeros(1, nDays);
    daily_grid_energy_kWh = zeros(1, nDays);
    daily_over_contract_kW = zeros(1, nDays);

    % ---------------------------------------------------------------------
    % NAPI SZINTU SZAMITAS
    % ---------------------------------------------------------------------
    for k = 1:nDays
        dc = day_cache(k);

        P_grid = dc.P_grid_no_bess_day(:);
        dt_h = dc.dt_h;

        buy_total = dc.Prices_today.buy_huf(:) + ...
                    tariff.distribution_energy_rate_huf_per_kWh + ...
                    tariff.transmission_energy_rate_huf_per_kWh;

        daily_peak(k) = max(P_grid);
        daily_grid_energy_kWh(k) = sum(P_grid) * dt_h;
        daily_energy_cost(k) = sum(P_grid(:) .* buy_total(:)) * dt_h;
        daily_over_contract_kW(k) = max(0, daily_peak(k) - contract_kW);

        month_ids(k) = floor((dc.abs_day - 1) / 30) + 1;
    end

    % ---------------------------------------------------------------------
    % HAVI SZINTU SZAMITAS
    % ---------------------------------------------------------------------
    unique_months = unique(month_ids);
    nMonths = numel(unique_months);

    monthly_peak = zeros(1, nMonths);
    monthly_overrun_kW = zeros(1, nMonths);
    monthly_energy_cost = zeros(1, nMonths);
    monthly_grid_energy_kWh = zeros(1, nMonths);
    monthly_overrun_cost = zeros(1, nMonths);

    monthly_overrun_cost_per_kW = tariff.penalty_rate_huf_per_kW_year / tariff.months_in_year;
    monthly_contracted_power_fee = (contract_kW * tariff.annual_contracted_power_fee_huf_per_kW) / tariff.months_in_year;

    for m = 1:nMonths
        idx = (month_ids == unique_months(m));

        monthly_peak(m) = max(daily_peak(idx));
        monthly_overrun_kW(m) = max(0, monthly_peak(m) - contract_kW);
        monthly_energy_cost(m) = sum(daily_energy_cost(idx));
        monthly_grid_energy_kWh(m) = sum(daily_grid_energy_kWh(idx));
        monthly_overrun_cost(m) = monthly_overrun_cost_per_kW * monthly_overrun_kW(m);
    end

    % ---------------------------------------------------------------------
    % OSSZESITES
    % ---------------------------------------------------------------------
    total_energy_cost = sum(daily_energy_cost);
    total_overrun_cost = sum(monthly_overrun_cost);
    total_contracted_power_fee = (nDays / days_in_year) * ...
        (contract_kW * tariff.annual_contracted_power_fee_huf_per_kW);

    total_cost_without_base_fee = total_energy_cost + total_overrun_cost + total_contracted_power_fee;

    % ---------------------------------------------------------------------
    % SUMMARY STRUCT
    % ---------------------------------------------------------------------
    summary = struct();
    summary.contract_kW = contract_kW;

    summary.daily_peak = daily_peak;
    summary.daily_energy_cost = daily_energy_cost;
    summary.daily_grid_energy_kWh = daily_grid_energy_kWh;
    summary.daily_over_contract_kW = daily_over_contract_kW;

    summary.month_ids = month_ids;
    summary.monthly_peak = monthly_peak;
    summary.monthly_overrun_kW = monthly_overrun_kW;
    summary.monthly_energy_cost = monthly_energy_cost;
    summary.monthly_grid_energy_kWh = monthly_grid_energy_kWh;
    summary.monthly_overrun_cost = monthly_overrun_cost;
    summary.monthly_contracted_power_fee = monthly_contracted_power_fee * ones(1, nMonths);

    summary.total_energy_cost = total_energy_cost;
    summary.total_overrun_cost = total_overrun_cost;
    summary.total_contracted_power_fee = total_contracted_power_fee;
    summary.total_cost_without_base_fee = total_cost_without_base_fee;

    summary.max_daily_peak = max(daily_peak);
    summary.mean_daily_peak = mean(daily_peak);
    summary.p95_daily_peak = prctile(daily_peak, 95);

    % ---------------------------------------------------------------------
    % LOG KIIRAS
    % ---------------------------------------------------------------------
    fprintf('\n---------------- OSSZEFOGLALO ----------------\n');
    fprintf('Vizsgalt napok szama:                  %d nap\n', nDays);
    fprintf('Vizsgalt honapok szama:                %d honap\n', nMonths);
    fprintf('Fix contract:                          %.2f kW\n', contract_kW);

    fprintf('\nNAPI PEAK STATISZTIKAK:\n');
    fprintf('Max napi peak:                         %.2f kW\n', summary.max_daily_peak);
    fprintf('Atlagos napi peak:                     %.2f kW\n', summary.mean_daily_peak);
    fprintf('95%% napi peak:                         %.2f kW\n', summary.p95_daily_peak);

    fprintf('\nKOLTSEGEK A TELJES VIZSGALT IDOSZAKRA:\n');
    fprintf('Energia koltseg:                       %.2f HUF\n', total_energy_cost);
    fprintf('Overrun koltseg:                       %.2f HUF\n', total_overrun_cost);
    fprintf('Lekotott teljesitmenydij:              %.2f HUF\n', total_contracted_power_fee);
    fprintf('Teljes koltseg (alapdij nelkul):       %.2f HUF\n', total_cost_without_base_fee);

    fprintf('\nHAVI LEKOTOTT TELJESITMENYDIJ:\n');
    fprintf('Havi lekotott teljesitmenydij:         %.2f HUF/ho\n', monthly_contracted_power_fee);

    fprintf('\n---------------- HAVI BONTAS ----------------\n');
    for m = 1:nMonths
        fprintf(['Honap %2d | peak = %8.2f kW | overrun = %8.2f kW | ' ...
                 'energia = %12.2f HUF | overrun dij = %10.2f HUF | ' ...
                 'lekotott telj. dij = %10.2f HUF\n'], ...
                 unique_months(m), ...
                 monthly_peak(m), ...
                 monthly_overrun_kW(m), ...
                 monthly_energy_cost(m), ...
                 monthly_overrun_cost(m), ...
                 monthly_contracted_power_fee);
    end

    % ---------------------------------------------------------------------
    % ABRAK
    % ---------------------------------------------------------------------
    figure('Name', sprintf('No-BESS elemzes - %.0f kW contract', contract_kW), ...
           'Position', [120, 120, 1250, 850]);

    subplot(3,1,1); hold on; grid on;
    plot(1:nDays, daily_peak, 'b-', 'LineWidth', 1.2, 'DisplayName', 'Napi peak');
    yline(contract_kW, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Contract');
    ylabel('Peak [kW]');
    title(sprintf('Napi no-BESS peak-ek (contract = %.0f kW)', contract_kW));
    legend('Location', 'best');

    subplot(3,1,2); hold on; grid on;
    bar(unique_months, monthly_peak, 'FaceColor', [0.2 0.6 0.8], 'DisplayName', 'Havi peak');
    yline(contract_kW, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Contract');
    ylabel('Peak [kW]');
    title('Havi maximumok');
    legend('Location', 'best');

    subplot(3,1,3); hold on; grid on;
    plot(unique_months, monthly_energy_cost, 'k-o', 'LineWidth', 1.5, 'DisplayName', 'Energia koltseg');
    plot(unique_months, monthly_overrun_cost, 'r-s', 'LineWidth', 1.5, 'DisplayName', 'Overrun koltseg');
    plot(unique_months, monthly_contracted_power_fee * ones(size(unique_months)), 'b--', ...
        'LineWidth', 1.5, 'DisplayName', 'Havi lekotott teljesitmenydij');
    ylabel('Koltseg [HUF]');
    xlabel('Honap index');
    title('Havi koltsegbontas');
    legend('Location', 'best');
end


function day_cache = local_build_day_cache_for_no_bess(start_day, final_day, PV_A, PV_B, Load, Price, inv_eta_ref)

    nSimDays = final_day - start_day + 1;
    day_cache = repmat(struct(), 1, nSimDays);

    for d = start_day:final_day
        ii = d - start_day + 1;

        dt_h = PV_A(d).dt_h;

        P_pv_dc_actual = (PV_A(d).Ppv + PV_B(d).Ppv) / 1000;
        P_load_actual  = Load(d).P_load_kW;
        Prices_today   = Price(d);

        P_grid_no_bess_day = max(P_load_actual - P_pv_dc_actual * inv_eta_ref, 0);

        day_cache(ii).abs_day = d;
        day_cache(ii).dt_h = dt_h;
        day_cache(ii).P_pv_dc_actual = P_pv_dc_actual;
        day_cache(ii).P_load_actual  = P_load_actual;
        day_cache(ii).Prices_today   = Prices_today;
        day_cache(ii).P_grid_no_bess_day = P_grid_no_bess_day;
        day_cache(ii).no_bess_peak = max(P_grid_no_bess_day);
    end
end