function result = run_no_bess_contract_optimization_main()
% RUN_NO_BESS_CONTRACT_OPTIMIZATION_MAIN
% Egyetlen main + alatta segédfüggvények.
%
% Cél:
%   BESS nélküli referencia esetben meghatározni az optimális lekötött
%   teljesítményt éves és 4 éves globális költségszempontból.
%
% Feltételezés:
%   - a build_pv_cache és build_load_price_cache elérhető
%   - a PV és load napi bontásban érkezik
%   - a hálózati import BESS nélkül:
%         P_grid = max(P_load - P_pv_ac, 0)
%
% Kimenet:
%   result struktúra, benne:
%       .opt_contract_kW_per_year
%       .global_opt_contract_kW
%       .global_total_cost_curve
%       .yearly_peak_kW
%       .contract_candidates_kW
%
% Megjegyzés:
%   Ez a függvény NEM futtat MILP-et. Ez kizárólag a BESS nélküli
%   referencia contracted power optimum becslésére szolgál.

    clc;
    close all;

    fprintf('=== BESS NELKULI OPTIMALIS LEKOTOTT TELJESITMENY KERESES ===\n');

    % ---------------------------------------------------------------------
    % 1) ADATOK BETOLTESE
    % ---------------------------------------------------------------------
    fprintf('Adatok betoltese a cache-bol...\n');

    PV_A = build_pv_cache(11, [95, 275], [274, 274], 0.325);
    PV_B = build_pv_cache(11, [70, 250], [100.5, 100.5], 0.325);
    [Load, ~] = build_load_price_cache();

    % ---------------------------------------------------------------------
    % 2) ALAP PARAMETEREK
    % ---------------------------------------------------------------------
    pars = local_base_pars_for_no_bess_reference();
    tariff = local_create_hungarian_mv_tariff_structure();

    % Evek kezelese
    DAYS_PER_YEAR = 365;
    requested_years = 4;

    nAvailableDays = min([numel(PV_A), numel(PV_B), numel(Load)]);
    nFullYears = floor(nAvailableDays / DAYS_PER_YEAR);

    if nFullYears < 1
        error('Nincs eleg adat legalabb 1 teljes evhez.');
    end

    NY = min(requested_years, nFullYears);

    fprintf('Elérhető napok száma: %d\n', nAvailableDays);
    fprintf('Felhasznált teljes évek száma: %d\n', NY);

    % ---------------------------------------------------------------------
    % 3) BESS NELKULI HALOZATI IMPORT ELOALLITASA EVENKENT
    % ---------------------------------------------------------------------
    P_grid_years = cell(1, NY);
    yearly_peak_kW = zeros(1, NY);
    yearly_energy_MWh = zeros(1, NY);

    for iy = 1:NY
        d0 = (iy-1) * DAYS_PER_YEAR + 1;
        d1 = iy * DAYS_PER_YEAR;

        P_grid_vec = [];

        for d = d0:d1
            dt_h = PV_A(d).dt_h;

            P_pv_dc = (PV_A(d).Ppv + PV_B(d).Ppv) / 1000; % [kW]
            P_load  = Load(d).P_load_kW;                  % [kW]

            P_pv_ac = P_pv_dc * pars.inv_eta;
            P_grid_day = max(P_load - P_pv_ac, 0);

            P_grid_vec = [P_grid_vec, P_grid_day]; %#ok<AGROW>
        end

        P_grid_years{iy} = P_grid_vec(:);
        yearly_peak_kW(iy) = max(P_grid_vec);
        yearly_energy_MWh(iy) = sum(P_grid_vec) * dt_h / 1000;
    end

    % ---------------------------------------------------------------------
    % 4) CONTRACT JELÖLTEK AUTOMATIKUS KEPZESE
    % ---------------------------------------------------------------------
    max_peak_all = max(yearly_peak_kW);
    contract_candidates_kW = local_make_contract_candidates(yearly_peak_kW, max_peak_all);

    fprintf('Contract jeloltek tartomanya: %.1f ... %.1f kW (%d db)\n', ...
        contract_candidates_kW(1), contract_candidates_kW(end), numel(contract_candidates_kW));

    % ---------------------------------------------------------------------
    % 5) OPTIMUMKERESÉS
    % ---------------------------------------------------------------------
    result = local_find_optimal_contracted_power_no_bess( ...
        P_grid_years, tariff, contract_candidates_kW);

    result.yearly_peak_kW = yearly_peak_kW;
    result.yearly_energy_MWh = yearly_energy_MWh;
    result.contract_candidates_kW = contract_candidates_kW;

    % ---------------------------------------------------------------------
    % 6) KIIRAS
    % ---------------------------------------------------------------------
    fprintf('\n=== EVES OPTIMUMOK ===\n');
    for iy = 1:NY
        fprintf('Ev %d:\n', iy);
        fprintf('  eves peak:                %.2f kW\n', result.yearly_peak_kW(iy));
        fprintf('  optimalis contract:       %.2f kW\n', result.opt_contract_kW_per_year(iy));
        fprintf('  minimalis eves koltseg:   %.2f HUF\n', result.yearly_total_cost(iy));
    end

    fprintf('\n=== GLOBALIS 4 EVES OPTIMUM ===\n');
    fprintf('Globalis optimalis contract: %.2f kW\n', result.global_opt_contract_kW);
    fprintf('Globalis 4 eves koltseg:     %.2f HUF\n', result.global_opt_total_cost);

    % ---------------------------------------------------------------------
    % 7) PLOTOK
    % ---------------------------------------------------------------------
    local_plot_contract_results(result);

    fprintf('\n=== KESZ ===\n');
end

% =========================================================================
% SEGEDFUGGVENYEK
% =========================================================================

function pars = local_base_pars_for_no_bess_reference()
    pars = struct();
    pars.inv_eta = 0.97;
end

function tariff = local_create_hungarian_mv_tariff_structure()
% KÖF / MV referencia tarifa a korábban megbeszélt osztály szerint.

    tariff = struct();

    tariff.class_name = 'Kozepfeszultsegu csatlakozas';

    % Hivatalos KÖF energiadíj elemek [HUF/kWh]
    tariff.distribution_energy_rate_huf_per_kWh = 8.39;
    tariff.transmission_energy_rate_huf_per_kWh = 3.39;

    % Hivatalos éves díjak
    tariff.annual_contracted_power_fee_huf_per_kW = 15924;
    tariff.annual_base_fee_huf = 216504;

    % Szimulációs overrun proxy
    tariff.penalty_rate_huf_per_kW_year = 2.5 * tariff.annual_contracted_power_fee_huf_per_kW;

    % Ratchet opcionális
    tariff.ratchet_factor = 0.0;
end

function contract_candidates_kW = local_make_contract_candidates(yearly_peak_kW, max_peak_all)
% Automatikus contract jelöltek generálása.
%
% Logika:
% - alsó tartomány: kb. a peak 50%-a
% - felső tartomány: kb. a peak 110%-a
% - lépésköz: 25 kW

    cmin = floor(0.50 * min(yearly_peak_kW) / 25) * 25;
    cmax = ceil(1.10 * max_peak_all / 25) * 25;

    cmin = max(cmin, 25);
    cmax = max(cmax, cmin + 25);

    contract_candidates_kW = cmin:25:cmax;
end

function result = local_find_optimal_contracted_power_no_bess(P_grid_years, tariff, contract_candidates_kW)
% Meghatározza az optimális contracted power-t BESS nélküli referencia
% esetre éves és globális többéves nézetben.

    NY = numel(P_grid_years);
    nC = numel(contract_candidates_kW);

    annual_contract_rate = tariff.annual_contracted_power_fee_huf_per_kW;
    annual_base_fee      = tariff.annual_base_fee_huf;
    annual_penalty_rate  = tariff.penalty_rate_huf_per_kW_year;
    ratchet_factor       = tariff.ratchet_factor;

    total_cost_matrix    = zeros(NY, nC);
    contract_cost_matrix = zeros(NY, nC);
    overrun_cost_matrix  = zeros(NY, nC);
    peak_over_matrix     = zeros(NY, nC);
    yearly_peak_kW       = zeros(1, NY);

    yearly_best_contract = zeros(1, NY);
    yearly_best_cost     = zeros(1, NY);

    % -------------------------
    % ÉVENKÉNTI OPTIMUM
    % -------------------------
    P_12month_max_prev = 0;

    for iy = 1:NY
        P_grid = P_grid_years{iy}(:);
        peak_y = max(P_grid);
        yearly_peak_kW(iy) = peak_y;

        for ic = 1:nC
            P_contract = contract_candidates_kW(ic);

            P_limit_ref = max(P_contract, ratchet_factor * P_12month_max_prev);
            P_over = max(0, peak_y - P_limit_ref);

            C_contract = annual_contract_rate * P_contract + annual_base_fee;
            C_overrun  = annual_penalty_rate * P_over;
            C_total    = C_contract + C_overrun;

            contract_cost_matrix(iy, ic) = C_contract;
            overrun_cost_matrix(iy, ic)  = C_overrun;
            peak_over_matrix(iy, ic)     = P_over;
            total_cost_matrix(iy, ic)    = C_total;
        end

        [yearly_best_cost(iy), idx_best] = min(total_cost_matrix(iy, :));
        yearly_best_contract(iy) = contract_candidates_kW(idx_best);

        P_12month_max_prev = max(P_12month_max_prev, peak_y);
    end

    % -------------------------
    % EGYETLEN GLOBALIS 4 EVES OPTIMUM
    % -------------------------
    global_total_cost = zeros(1, nC);

    for ic = 1:nC
        P_contract = contract_candidates_kW(ic);

        P_12month_max_prev = 0;
        cost_sum = 0;

        for iy = 1:NY
            P_grid = P_grid_years{iy}(:);
            peak_y = max(P_grid);

            P_limit_ref = max(P_contract, ratchet_factor * P_12month_max_prev);
            P_over = max(0, peak_y - P_limit_ref);

            C_contract = annual_contract_rate * P_contract + annual_base_fee;
            C_overrun  = annual_penalty_rate * P_over;

            cost_sum = cost_sum + C_contract + C_overrun;

            P_12month_max_prev = max(P_12month_max_prev, peak_y);
        end

        global_total_cost(ic) = cost_sum;
    end

    [global_best_cost, idx_global] = min(global_total_cost);
    global_best_contract = contract_candidates_kW(idx_global);

    result = struct();
    result.opt_contract_kW_per_year = yearly_best_contract;
    result.yearly_total_cost         = yearly_best_cost;
    result.yearly_peak_kW            = yearly_peak_kW;

    result.cost_table = struct();
    result.cost_table.contract_candidates_kW = contract_candidates_kW(:);
    result.cost_table.total_cost_matrix      = total_cost_matrix;
    result.cost_table.contract_cost_matrix   = contract_cost_matrix;
    result.cost_table.overrun_cost_matrix    = overrun_cost_matrix;
    result.cost_table.peak_over_matrix       = peak_over_matrix;

    result.global_opt_contract_kW   = global_best_contract;
    result.global_opt_total_cost    = global_best_cost;
    result.global_total_cost_curve  = global_total_cost;
end

function local_plot_contract_results(result)
% Ábrák az éves és globális optimumról.

    contract_candidates = result.contract_candidates_kW;
    yearly_peak_kW      = result.yearly_peak_kW;
    yearly_opt_contract = result.opt_contract_kW_per_year;
    yearly_total_cost   = result.yearly_total_cost;
    global_curve        = result.global_total_cost_curve;
    global_opt_contract = result.global_opt_contract_kW;

    NY = numel(yearly_peak_kW);

    figure('Name', 'BESS nélküli optimális lekötött teljesítmény', ...
           'Position', [100, 100, 1300, 850]);

    % ---------------------------------------------------------------------
    % 1) Éves peak vs éves optimális contract
    % ---------------------------------------------------------------------
    subplot(2,2,1); hold on; grid on;
    x = 1:NY;
    bar(x - 0.15, yearly_peak_kW, 0.30, 'FaceColor', [0.80 0.20 0.20], ...
        'DisplayName', 'Éves peak');
    bar(x + 0.15, yearly_opt_contract, 0.30, 'FaceColor', [0.20 0.50 0.85], ...
        'DisplayName', 'Optimális contract');

    xlabel('Év');
    ylabel('Teljesítmény [kW]');
    title('Éves peak és optimális lekötött teljesítmény');
    legend('Location', 'best');

    % ---------------------------------------------------------------------
    % 2) Éves minimális költség
    % ---------------------------------------------------------------------
    subplot(2,2,2); hold on; grid on;
    bar(1:NY, yearly_total_cost, 'FaceColor', [0.25 0.70 0.40]);
    xlabel('Év');
    ylabel('Költség [HUF/év]');
    title('Éves minimális contract+overrun költség');

    % ---------------------------------------------------------------------
    % 3) Globális költséggörbe
    % ---------------------------------------------------------------------
    subplot(2,2,3); hold on; grid on;
    plot(contract_candidates, global_curve, 'k-', 'LineWidth', 2, ...
        'DisplayName', '4 éves teljes költség');
    xline(global_opt_contract, 'r--', 'LineWidth', 2, ...
        'DisplayName', sprintf('Global optimum = %.0f kW', global_opt_contract));

    xlabel('Lekötött teljesítmény [kW]');
    ylabel('4 éves költség [HUF]');
    title('Globális 4 éves költséggörbe');
    legend('Location', 'best');

    % ---------------------------------------------------------------------
    % 4) Évenkénti költséggörbék
    % ---------------------------------------------------------------------
    subplot(2,2,4); hold on; grid on;
    cmap = lines(NY);

    for iy = 1:NY
        plot(contract_candidates, result.cost_table.total_cost_matrix(iy,:), ...
            'LineWidth', 1.8, 'Color', cmap(iy,:), ...
            'DisplayName', sprintf('Év %d', iy));
    end

    xlabel('Lekötött teljesítmény [kW]');
    ylabel('Éves költség [HUF]');
    title('Évenkénti költséggörbék');
    legend('Location', 'best');
end