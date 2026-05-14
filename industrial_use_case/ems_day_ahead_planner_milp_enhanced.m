% function plan = ems_day_ahead_planner_milp_enhanced(P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, current_day_of_month, P_12month_max)
%     N = length(P_load_f);
% 
%     eta_in  = pars.inv_eta * pars.eta_c * pars.eta_cell;
%     eta_out = pars.eta_cell * pars.eta_d * pars.inv_eta;
%     cost_deg = pars.degradation_cost_per_kWh;
% 
%     days_in_month = tariff.days_in_billing_period;
%     D_remaining = days_in_month - current_day_of_month + 1;
% 
%     if strcmp(tariff.demand_charge_method, 'amortized')
%         C_peak_daily = tariff.demand_charge_rate / D_remaining;
%     else
%         C_peak_daily = tariff.demand_charge_rate / days_in_month;
%     end
% 
%     C_penalty_daily = (tariff.penalty_rate - tariff.demand_charge_rate) / D_remaining;
% 
%     nVars = 4*N + 2;
% 
%     f = zeros(nVars, 1);
%     buy_p = Prices.buy_huf(:);
%     sell_p = Prices.sell_huf(:);
% 
%     f(1:N) = (buy_p ./ eta_in) + cost_deg;
%     f(N+1:2*N) = -(sell_p .* eta_out) + cost_deg;
%     f(4*N+1) = C_peak_daily;
%     f(4*N+2) = C_penalty_daily;
% 
%     A = [];
%     b = [];
% 
%     A_grid = zeros(N, nVars);
%     b_grid = zeros(N, 1);
% 
%     for t = 1:N
%         P_pv_ac = min(P_pv_dc_f(t) * pars.inv_eta, pars.P_inv_limit_ac);
%         A_grid(t, t)     = 1;
%         A_grid(t, N+t)   = -1;
%         A_grid(t, 4*N+1) = -1;
%         b_grid(t)        = P_pv_ac - P_load_f(t);
%     end
% 
%     A = [A; A_grid];
%     b = [b; b_grid];
% 
%     A_bin = zeros(2*N, nVars);
%     b_bin = zeros(2*N, 1);
%     P_max = pars.P_inv_limit_ac;
% 
%     for t = 1:N
%         A_bin(t, t) = 1;
%         A_bin(t, 3*N+t) = -P_max;
%         b_bin(t) = 0;
% 
%         A_bin(N+t, N+t) = 1;
%         A_bin(N+t, 3*N+t) = P_max;
%         b_bin(N+t) = P_max;
%     end
% 
%     A = [A; A_bin];
%     b = [b; b_bin];
% 
%     P_ratchet = tariff.ratchet_factor * P_12month_max;
%     row_ratchet = zeros(1, nVars);
%     row_ratchet(4*N+1) = -1;
%     A = [A; row_ratchet];
%     b = [b; -P_ratchet];
% 
%     P_contract = tariff.contracted_capacity_kW;
% 
%     row_contract1 = zeros(1, nVars);
%     row_contract1(4*N+1) = 1;
%     row_contract1(4*N+2) = -1;
%     A = [A; row_contract1];
%     b = [b; P_contract];
% 
%     row_contract2 = zeros(1, nVars);
%     row_contract2(4*N+2) = -1;
%     A = [A; row_contract2];
%     b = [b; 0];
% 
%     Aeq = zeros(N, nVars);
%     beq = zeros(N, 1);
% 
%     if isfield(pars, 'SoC_initial')
%         SoC_start = pars.SoC_initial;
%     else
%         SoC_start = 0.5;
%     end
% 
%     for t = 1:N
%         Aeq(t, 2*N+t) = 1;
%         if t == 1
%             beq(t) = SoC_start;
%         else
%             Aeq(t, 2*N+t-1) = -1;
%             Aeq(t, t-1)     = -(eta_in * dt_h) / pars.E_cap_nom;
%             Aeq(t, N+t-1)   = (dt_h / eta_out) / pars.E_cap_nom;
%             beq(t) = 0;
%         end
%     end
% 
%     lb = zeros(nVars, 1);
%     ub = inf(nVars, 1);
%     lb(2*N+1:3*N) = pars.SoC_min;
%     ub(2*N+1:3*N) = pars.SoC_max;
%     ub(3*N+1:4*N) = 1;
%     lb(4*N+1) = P_ratchet;
%     lb(4*N+2) = 0;
% 
%     intcon = (3*N+1):(4*N);
%     options = optimoptions('intlinprog', ...
%         'Display', 'off', ...
%         'MaxTime', 30, ...
%         'RelativeGapTolerance', 0.01, ...
%         'IntegerPreprocess', 'advanced', ...
%         'RootLPAlgorithm', 'dual-simplex');
% 
%     [x, fval, exitflag] = intlinprog(f, intcon, A, b, Aeq, beq, lb, ub, options);
% 
%     if isempty(x) || exitflag <= 0
%         plan.P_limit = max(P_ratchet, max(P_load_f));
%         plan.P_over_contract = max(0, plan.P_limit - P_contract);
%         plan.trade_buy_mask = false(1, N);
%         plan.trade_sell_mask = false(1, N);
%         plan.P_ch_plan = zeros(N, 1);
%         plan.P_dis_plan = zeros(N, 1);
%         plan.SoC_plan = SoC_start * ones(N, 1);
%         plan.objective_value = inf;
%         plan.exitflag = exitflag;
%     else
%         plan.P_limit = x(4*N+1);
%         plan.P_over_contract = x(4*N+2);
%         plan.trade_buy_mask = x(1:N) > 0.1;
%         plan.trade_sell_mask = x(N+1:2*N) > 0.1;
%         plan.P_ch_plan = x(1:N);
%         plan.P_dis_plan = x(N+1:2*N);
%         plan.SoC_plan = x(2*N+1:3*N);
%         plan.objective_value = fval;
%         plan.exitflag = exitflag;
% 
%         plan.economics.energy_cost = sum((buy_p ./ eta_in) .* x(1:N));
%         plan.economics.energy_revenue = sum((sell_p .* eta_out) .* x(N+1:2*N));
%         plan.economics.degradation_cost = sum(cost_deg * (x(1:N) + x(N+1:2*N)));
%         plan.economics.demand_charge_daily = C_peak_daily * x(4*N+1);
%         plan.economics.penalty_charge_daily = C_penalty_daily * x(4*N+2);
%         plan.economics.net_cost = fval;
%         plan.economics.C_peak_daily = C_peak_daily;
%         plan.economics.C_penalty_daily = C_penalty_daily;
%         plan.economics.D_remaining = D_remaining;
%     end
% end


% function plan = ems_day_ahead_planner_milp_enhanced( ...
%     P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, current_day_of_month, P_12month_max)
% % IMPORT-ONLY, KÖF ipari logikára illesztett MILP tervező
% %
% % Döntési változók:
% %   P_grid(t)  - hálózati import [kW]
% %   P_ch(t)    - akku töltés AC oldali ekvivalens teljesítménye [kW]
% %   P_dis(t)   - akku kisütés AC oldali ekvivalens teljesítménye [kW]
% %   SoC(t)     - töltöttségi állapot [p.u.]
% %   u(t)       - bináris mód (1=töltés, 0=nem töltés / kisütés oldal)
% %   P_curt(t)  - eldobott PV AC teljesítmény [kW]
% %   P_peak     - napi/horizont peak import [kW]
% %   P_over     - contracted szint feletti rész [kW]
% 
%     %#ok<*INUSD>
% 
%     % ---------------------------------------------------------------------
%     % 0) Alapellenőrzések
%     % ---------------------------------------------------------------------
%     N = length(P_load_f);
% 
%     P_load_f  = P_load_f(:);
%     P_pv_dc_f = P_pv_dc_f(:);
%     buy_p_market = Prices.buy_huf(:);
% 
%     if length(P_pv_dc_f) ~= N
%         error('P_load_f és P_pv_dc_f hossza nem egyezik.');
%     end
%     if length(buy_p_market) ~= N
%         error('Prices.buy_huf hossza nem egyezik a horizonttal.');
%     end
% 
%     % ---------------------------------------------------------------------
%     % 1) Paraméterek
%     % ---------------------------------------------------------------------
%     eta_c_path = pars.inv_eta * pars.eta_c * pars.eta_cell;   % AC -> cell
%     eta_d_path = pars.eta_cell * pars.eta_d * pars.inv_eta;   % cell -> AC
%     cost_deg   = pars.degradation_cost_per_kWh;
% 
%     if isfield(pars, 'SoC_initial')
%         SoC_start = pars.SoC_initial;
%     else
%         SoC_start = 0.5;
%     end
% 
%     if isfield(pars, 'P_chg_max')
%         P_ch_max = pars.P_chg_max;
%     else
%         P_ch_max = pars.P_inv_limit_ac;
%     end
% 
%     if isfield(pars, 'P_dis_max')
%         P_dis_max = pars.P_dis_max;
%     else
%         P_dis_max = pars.P_inv_limit_ac;
%     end
% 
%     % ---------------------------------------------------------------------
%     % 2) Tarifa
%     % ---------------------------------------------------------------------
%     dist_energy_fee  = tariff.distribution_energy_rate_huf_per_kWh;
%     trans_energy_fee = tariff.transmission_energy_rate_huf_per_kWh;
%     buy_p_total = buy_p_market + dist_energy_fee + trans_energy_fee;
% 
%     P_contract = tariff.contracted_capacity_kW;
% 
%     if isfield(tariff, 'annual_contracted_power_fee_huf_per_kW')
%         annual_contract_rate = tariff.annual_contracted_power_fee_huf_per_kW;
%     else
%         annual_contract_rate = 0;
%     end
% 
%     if isfield(tariff, 'annual_base_fee_huf')
%         annual_base_fee = tariff.annual_base_fee_huf;
%     else
%         annual_base_fee = 0;
%     end
% 
%     if isfield(tariff, 'penalty_rate_huf_per_kW_year')
%         annual_penalty_rate = tariff.penalty_rate_huf_per_kW_year;
%     else
%         annual_penalty_rate = 2.0 * annual_contract_rate;
%     end
% 
%     if isfield(tariff, 'ratchet_factor')
%         P_ratchet = tariff.ratchet_factor * P_12month_max;
%     else
%         P_ratchet = 0;
%     end
% 
%     P_limit_ref = max(P_contract, P_ratchet);
% 
%     if isfield(tariff, 'days_in_year')
%         days_in_year = tariff.days_in_year;
%     else
%         days_in_year = 365;
%     end
% 
%     overrun_penalty_day = annual_penalty_rate / days_in_year;
% 
%     if isfield(tariff, 'peak_shadow_weight')
%         peak_shadow_weight = tariff.peak_shadow_weight;
%     else
%         peak_shadow_weight = 0;
%     end
%     peak_shadow_day = peak_shadow_weight * (annual_contract_rate / days_in_year);
% 
%     if isfield(tariff, 'curtailment_penalty_huf_per_kWh')
%         curtail_penalty = tariff.curtailment_penalty_huf_per_kWh;
%     else
%         curtail_penalty = 0;
%     end
% 
%     % ---------------------------------------------------------------------
%     % 3) PV AC oldal
%     % ---------------------------------------------------------------------
%     P_pv_ac = min(P_pv_dc_f * pars.inv_eta, pars.P_inv_limit_ac);
% 
%     % ---------------------------------------------------------------------
%     % 4) Indexek
%     % ---------------------------------------------------------------------
%     iGrid = 1:N;
%     iCh   = N+1:2*N;
%     iDis  = 2*N+1:3*N;
%     iSoc  = 3*N+1:4*N;
%     iMode = 4*N+1:5*N;
%     iCurt = 5*N+1:6*N;
%     iPeak = 6*N+1;
%     iOver = 6*N+2;
% 
%     nVars = 6*N + 2;
% 
%     % ---------------------------------------------------------------------
%     % 5) Célfüggvény
%     % ---------------------------------------------------------------------
%     f = zeros(nVars, 1);
%     f(iGrid) = buy_p_total * dt_h;
%     f(iCh)   = cost_deg * dt_h;
%     f(iDis)  = cost_deg * dt_h;
%     f(iCurt) = curtail_penalty * dt_h;
%     f(iPeak) = peak_shadow_day;
%     f(iOver) = overrun_penalty_day;
% 
%     % ---------------------------------------------------------------------
%     % 6) Egyenlőségi korlátok
%     % ---------------------------------------------------------------------
%     % Energiamérleg export nélkül:
%     % P_grid + P_dis - P_ch - P_curt = P_load - P_pv_ac
%     Aeq_energy = zeros(N, nVars);
%     beq_energy = P_load_f - P_pv_ac;
% 
%     for t = 1:N
%         Aeq_energy(t, iGrid(t)) =  1;
%         Aeq_energy(t, iDis(t))  =  1;
%         Aeq_energy(t, iCh(t))   = -1;
%         Aeq_energy(t, iCurt(t)) = -1;
%     end
% 
%     % SoC dinamika
%     Aeq_soc = zeros(N, nVars);
%     beq_soc = zeros(N, 1);
% 
%     Aeq_soc(1, iSoc(1)) = 1;
%     beq_soc(1) = SoC_start;
% 
%     alpha_ch = (eta_c_path * dt_h) / pars.E_cap_nom;
%     beta_dis = (dt_h / eta_d_path) / pars.E_cap_nom;
% 
%     for t = 2:N
%         Aeq_soc(t, iSoc(t))   =  1;
%         Aeq_soc(t, iSoc(t-1)) = -1;
%         Aeq_soc(t, iCh(t-1))  = -alpha_ch;
%         Aeq_soc(t, iDis(t-1)) =  beta_dis;
%     end
% 
%     Aeq = [Aeq_energy; Aeq_soc];
%     beq = [beq_energy; beq_soc];
% 
%     % ---------------------------------------------------------------------
%     % 7) Egyenlőtlenségi korlátok
%     % ---------------------------------------------------------------------
%     A = [];
%     b = [];
% 
%     % Töltés/kisütés logika
%     A_bin = zeros(2*N, nVars);
%     b_bin = zeros(2*N, 1);
% 
%     for t = 1:N
%         % P_ch <= P_ch_max * u
%         A_bin(t, iCh(t))   = 1;
%         A_bin(t, iMode(t)) = -P_ch_max;
%         b_bin(t) = 0;
% 
%         % P_dis <= P_dis_max * (1-u)
%         % P_dis + P_dis_max*u <= P_dis_max
%         A_bin(N+t, iDis(t))  = 1;
%         A_bin(N+t, iMode(t)) = P_dis_max;
%         b_bin(N+t) = P_dis_max;
%     end
% 
%     A = [A; A_bin];
%     b = [b; b_bin];
% 
%     % Curtailment <= PV AC
%     A_curt = zeros(N, nVars);
%     b_curt = zeros(N, 1);
%     for t = 1:N
%         A_curt(t, iCurt(t)) = 1;
%         b_curt(t) = P_pv_ac(t);
%     end
%     A = [A; A_curt];
%     b = [b; b_curt];
% 
%     % P_peak >= P_grid(t)
%     A_peak = zeros(N, nVars);
%     b_peak = zeros(N, 1);
%     for t = 1:N
%         A_peak(t, iGrid(t)) = 1;
%         A_peak(t, iPeak)    = -1;
%     end
%     A = [A; A_peak];
%     b = [b; b_peak];
% 
%     % P_over >= P_peak - P_limit_ref
%     % P_peak - P_over <= P_limit_ref
%     row_over = zeros(1, nVars);
%     row_over(iPeak) = 1;
%     row_over(iOver) = -1;
%     A = [A; row_over];
%     b = [b; P_limit_ref];
% 
%     % ---------------------------------------------------------------------
%     % 8) Alsó/felső korlátok
%     % ---------------------------------------------------------------------
%     lb = zeros(nVars, 1);
%     ub = inf(nVars, 1);
% 
%     lb(iSoc) = pars.SoC_min;
%     ub(iSoc) = pars.SoC_max;
% 
%     lb(iMode) = 0;
%     ub(iMode) = 1;
% 
%     % ---------------------------------------------------------------------
%     % 9) MILP
%     % ---------------------------------------------------------------------
%     intcon = iMode;
% 
%     options = optimoptions('intlinprog', ...
%         'Display', 'off', ...
%         'MaxTime', 30, ...
%         'RelativeGapTolerance', 0.01, ...
%         'IntegerPreprocess', 'advanced', ...
%         'RootLPAlgorithm', 'dual-simplex');
% 
%     [x, fval, exitflag] = intlinprog(f, intcon, A, b, Aeq, beq, lb, ub, options);
% 
%     % ---------------------------------------------------------------------
%     % 10) Kimenet
%     % ---------------------------------------------------------------------
%     plan = struct();
% 
%     if isempty(x) || exitflag <= 0
%         fallback_peak = max(max(P_load_f - P_pv_ac, 0), P_limit_ref);
% 
%         plan.P_limit = fallback_peak;
%         plan.P_limit_ref = P_limit_ref;
%         plan.P_over_contract = max(0, fallback_peak - P_limit_ref);
% 
%         plan.trade_buy_mask  = false(1, N);
%         plan.trade_sell_mask = false(1, N);
% 
%         plan.P_grid_plan = max(P_load_f - P_pv_ac, 0);
%         plan.P_ch_plan   = zeros(N, 1);
%         plan.P_dis_plan  = zeros(N, 1);
%         plan.P_curt_plan = max(P_pv_ac - P_load_f, 0);
%         plan.SoC_plan    = SoC_start * ones(N, 1);
% 
%         plan.objective_value = inf;
%         plan.exitflag = exitflag;
% 
%         plan.economics.energy_cost_market      = sum(buy_p_market .* plan.P_grid_plan) * dt_h;
%         plan.economics.energy_cost_network     = sum((dist_energy_fee + trans_energy_fee) .* plan.P_grid_plan) * dt_h;
%         plan.economics.energy_cost_total       = plan.economics.energy_cost_market + plan.economics.energy_cost_network;
%         plan.economics.degradation_cost        = 0;
%         plan.economics.overrun_cost_proxy      = overrun_penalty_day * plan.P_over_contract;
%         plan.economics.peak_shadow_cost        = peak_shadow_day * plan.P_limit;
%         plan.economics.net_cost_operational    = inf;
%         plan.economics.contract_charge_annual  = annual_contract_rate * P_contract;
%         plan.economics.base_fee_annual         = annual_base_fee;
%         plan.economics.P_contract              = P_contract;
%         plan.economics.P_limit_ref             = P_limit_ref;
%         plan.economics.annual_penalty_rate     = annual_penalty_rate;
%         plan.economics.buy_price_total_mean    = mean(buy_p_total);
%         return;
%     end
% 
%     P_grid = x(iGrid);
%     P_ch   = x(iCh);
%     P_dis  = x(iDis);
%     SoC    = x(iSoc);
%     P_curt = x(iCurt);
%     P_peak = x(iPeak);
%     P_over = x(iOver);
% 
%     plan.P_limit = P_peak;
%     plan.P_limit_ref = P_limit_ref;
%     plan.P_over_contract = P_over;
% 
%     % Kompatibilitás a meglévő teszthez:
%     % buy_mask = töltési ablak, sell_mask = kisütési ablak
%     plan.trade_buy_mask  = (P_ch  > 1e-3).';
%     plan.trade_sell_mask = (P_dis > 1e-3).';
% 
%     plan.P_grid_plan = P_grid;
%     plan.P_ch_plan   = P_ch;
%     plan.P_dis_plan  = P_dis;
%     plan.P_curt_plan = P_curt;
%     plan.SoC_plan    = SoC;
% 
%     plan.objective_value = fval;
%     plan.exitflag = exitflag;
% 
%     energy_cost_market  = sum(buy_p_market .* P_grid) * dt_h;
%     energy_cost_network = sum((dist_energy_fee + trans_energy_fee) .* P_grid) * dt_h;
%     degradation_cost    = sum(cost_deg .* (P_ch + P_dis)) * dt_h;
%     overrun_cost_proxy  = overrun_penalty_day * P_over;
%     peak_shadow_cost    = peak_shadow_day * P_peak;
%     curtailment_cost    = sum(curtail_penalty .* P_curt) * dt_h;
% 
%     plan.economics.energy_cost_market      = energy_cost_market;
%     plan.economics.energy_cost_network     = energy_cost_network;
%     plan.economics.energy_cost_total       = energy_cost_market + energy_cost_network;
%     plan.economics.degradation_cost        = degradation_cost;
%     plan.economics.overrun_cost_proxy      = overrun_cost_proxy;
%     plan.economics.peak_shadow_cost        = peak_shadow_cost;
%     plan.economics.curtailment_cost        = curtailment_cost;
%     plan.economics.net_cost_operational    = fval;
%     plan.economics.contract_charge_annual  = annual_contract_rate * P_contract;
%     plan.economics.base_fee_annual         = annual_base_fee;
%     plan.economics.P_contract              = P_contract;
%     plan.economics.P_limit_ref             = P_limit_ref;
%     plan.economics.annual_penalty_rate     = annual_penalty_rate;
%     plan.economics.buy_price_total_mean    = mean(buy_p_total);
% end

function plan = ems_day_ahead_planner_milp_enhanced( ...
    P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, current_day_of_month, P_12month_max)
% EMS_DAY_AHEAD_PLANNER_MILP_PEAK_ORIENTED
% Gyorsított, peak-oriented, rule-assisted rolling MILP planner.
%
% FONTOS:
% - Ugyanaz a függvénynév marad, ezért a hívó kódot nem kell módosítani.
% - A gyorsítás úgy történik, hogy a MILP aggregált időlépésen fut
%   (pl. 15 percen), majd a terv visszabontásra kerül az eredeti felbontásra.
%
% Belső logika:
% - ha van tariff.planner_dt_h mező, azt használja aggregált planner időlépésnek
% - ha nincs, akkor alapból 15 percet (0.25 h) használ
% - ha az aggregálás nem értelmes, visszaesik az eredeti felbontásra

    % --------------------------------------------------------------
    % 0) Gyorsított planner időlépés beállítása
    % --------------------------------------------------------------
    if isfield(tariff, 'planner_dt_h') && ~isempty(tariff.planner_dt_h)
        target_dt_h = tariff.planner_dt_h;
    else
        target_dt_h = 0.25; % default: 15 perc
    end

    agg_factor = round(target_dt_h / dt_h);

    if agg_factor <= 1
        plan = local_milp_peak_oriented_core( ...
            P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, ...
            current_day_of_month, P_12month_max);
        return;
    end

    N0 = numel(P_load_f);
    Nagg = floor(N0 / agg_factor);

    if Nagg < 2
        plan = local_milp_peak_oriented_core( ...
            P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, ...
            current_day_of_month, P_12month_max);
        return;
    end

    % --------------------------------------------------------------
    % 1) Bemenetek levágása osztható hosszra
    % --------------------------------------------------------------
    keep_len = Nagg * agg_factor;

    P_load_trim = P_load_f(1:keep_len);
    P_pv_trim   = P_pv_dc_f(1:keep_len);
    buy_trim    = Prices.buy_huf(1:keep_len);

    % --------------------------------------------------------------
    % 2) Aggregálás
    % --------------------------------------------------------------
    P_load_agg = local_aggregate_series_mean(P_load_trim, agg_factor);
    P_pv_agg   = local_aggregate_series_mean(P_pv_trim, agg_factor);
    buy_agg    = local_aggregate_series_mean(buy_trim, agg_factor);

    Prices_agg = struct();
    Prices_agg.buy_huf = buy_agg;

    % --------------------------------------------------------------
    % 3) MILP futtatása aggregált rácson
    % --------------------------------------------------------------
    plan_agg = local_milp_peak_oriented_core( ...
        P_load_agg, P_pv_agg, Prices_agg, pars, tariff, target_dt_h, ...
        current_day_of_month, P_12month_max);

    % --------------------------------------------------------------
    % 4) Visszabontás eredeti felbontásra
    % --------------------------------------------------------------
    plan = struct();
    plan.P_limit         = plan_agg.P_limit;
    plan.P_limit_ref     = plan_agg.P_limit_ref;
    plan.P_over_contract = plan_agg.P_over_contract;
    plan.objective_value = plan_agg.objective_value;
    plan.exitflag        = plan_agg.exitflag;
    plan.economics       = plan_agg.economics;

    plan.trade_buy_mask  = local_expand_series_repelem(plan_agg.trade_buy_mask(:),  agg_factor, keep_len);
    plan.trade_sell_mask = local_expand_series_repelem(plan_agg.trade_sell_mask(:), agg_factor, keep_len);

    plan.P_grid_plan = local_expand_series_repelem(plan_agg.P_grid_plan(:), agg_factor, keep_len);
    plan.P_ch_plan   = local_expand_series_repelem(plan_agg.P_ch_plan(:),   agg_factor, keep_len);
    plan.P_dis_plan  = local_expand_series_repelem(plan_agg.P_dis_plan(:),  agg_factor, keep_len);
    plan.P_curt_plan = local_expand_series_repelem(plan_agg.P_curt_plan(:), agg_factor, keep_len);
    plan.SoC_plan    = local_expand_series_repelem(plan_agg.SoC_plan(:),    agg_factor, keep_len);

    % Ha maradt levágott rész a végén, egészítsük ki
    if keep_len < N0
        rem_len = N0 - keep_len;

        plan.trade_buy_mask  = [plan.trade_buy_mask;  false(rem_len,1)];
        plan.trade_sell_mask = [plan.trade_sell_mask; false(rem_len,1)];

        plan.P_grid_plan = [plan.P_grid_plan; repmat(plan.P_grid_plan(end), rem_len, 1)];
        plan.P_ch_plan   = [plan.P_ch_plan;   zeros(rem_len,1)];
        plan.P_dis_plan  = [plan.P_dis_plan;  zeros(rem_len,1)];
        plan.P_curt_plan = [plan.P_curt_plan; zeros(rem_len,1)];
        plan.SoC_plan    = [plan.SoC_plan;    repmat(plan.SoC_plan(end), rem_len, 1)];
    end

    % Kompatibilitás a meglévő kóddal
    plan.trade_buy_mask  = plan.trade_buy_mask(:).';
    plan.trade_sell_mask = plan.trade_sell_mask(:).';
end

% =========================================================================
% BELSŐ CORE MILP - eredeti logika gyorsított wrapper mögött
% =========================================================================
function plan = local_milp_peak_oriented_core( ...
    P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, current_day_of_month, P_12month_max)

    N = length(P_load_f);

    P_load_f  = P_load_f(:);
    P_pv_dc_f = P_pv_dc_f(:);
    buy_p_market = Prices.buy_huf(:);

    eta_c_path = pars.inv_eta * pars.eta_c * pars.eta_cell;
    eta_d_path = pars.eta_cell * pars.eta_d * pars.inv_eta;
    cost_deg   = pars.degradation_cost_per_kWh;

    if isfield(pars, 'SoC_initial')
        SoC_start = pars.SoC_initial;
    else
        SoC_start = 0.5;
    end

    P_ch_max  = pars.P_chg_max;
    P_dis_max = pars.P_dis_max;

    dist_energy_fee  = tariff.distribution_energy_rate_huf_per_kWh;
    trans_energy_fee = tariff.transmission_energy_rate_huf_per_kWh;
    buy_p_total = buy_p_market + dist_energy_fee + trans_energy_fee;

    P_contract = tariff.contracted_capacity_kW;
    annual_contract_rate = tariff.annual_contracted_power_fee_huf_per_kW;
    annual_base_fee      = tariff.annual_base_fee_huf;
    annual_penalty_rate  = tariff.penalty_rate_huf_per_kW_year;
    P_ratchet = tariff.ratchet_factor * P_12month_max;
    P_limit_ref = max(P_contract, P_ratchet);

    overrun_penalty_day = annual_penalty_rate / tariff.days_in_year;
    peak_shadow_day = tariff.peak_shadow_weight * (annual_contract_rate / tariff.days_in_year);

    P_pv_ac = min(P_pv_dc_f * pars.inv_eta, pars.P_inv_limit_ac);

    % --------------------------------------------------------------
    % Rule-assisted elemek
    % --------------------------------------------------------------
    qcheap = tariff.grid_charge_price_quantile;
    cheap_threshold = quantile(buy_p_market, qcheap);
    cheap_mask = buy_p_market <= cheap_threshold;

    pv_surplus_mask = P_pv_ac > P_load_f;
    noncheap_charge_penalty = tariff.noncheap_charge_penalty_huf_per_kWh * ...
                              (~cheap_mask & ~pv_surplus_mask);

    hours = mod((0:N-1)' * dt_h, 24);
    peak_hours = tariff.peak_hours;
    peak_window_mask = hours >= peak_hours(1) & hours < peak_hours(2);

    soc_min_vec = pars.SoC_min * ones(N,1);
    soc_min_vec(peak_window_mask) = max(pars.SoC_min, tariff.peak_reserve_soc);

    % --------------------------------------------------------------
    % Változó indexek
    % --------------------------------------------------------------
    iGrid = 1:N;
    iCh   = N+1:2*N;
    iDis  = 2*N+1:3*N;
    iSoc  = 3*N+1:4*N;
    iMode = 4*N+1:5*N;
    iCurt = 5*N+1:6*N;
    iPeak = 6*N+1;
    iOver = 6*N+2;
    nVars = 6*N + 2;

    % --------------------------------------------------------------
    % Célfüggvény
    % --------------------------------------------------------------
    f = zeros(nVars, 1);
    f(iGrid) = buy_p_total * dt_h;
    f(iCh)   = cost_deg * dt_h + noncheap_charge_penalty * dt_h;
    f(iDis)  = cost_deg * dt_h;
    f(iCurt) = tariff.curtailment_penalty_huf_per_kWh * dt_h;
    f(iPeak) = peak_shadow_day;
    f(iOver) = overrun_penalty_day;

    % --------------------------------------------------------------
    % Egyenlőségi korlátok
    % --------------------------------------------------------------
    Aeq_energy = zeros(N, nVars);
    beq_energy = P_load_f - P_pv_ac;

    for t = 1:N
        Aeq_energy(t, iGrid(t)) =  1;
        Aeq_energy(t, iDis(t))  =  1;
        Aeq_energy(t, iCh(t))   = -1;
        Aeq_energy(t, iCurt(t)) = -1;
    end

    Aeq_soc = zeros(N, nVars);
    beq_soc = zeros(N, 1);

    Aeq_soc(1, iSoc(1)) = 1;
    beq_soc(1) = SoC_start;

    alpha_ch = (eta_c_path * dt_h) / pars.E_cap_nom;
    beta_dis = (dt_h / eta_d_path) / pars.E_cap_nom;

    for t = 2:N
        Aeq_soc(t, iSoc(t))   =  1;
        Aeq_soc(t, iSoc(t-1)) = -1;
        Aeq_soc(t, iCh(t-1))  = -alpha_ch;
        Aeq_soc(t, iDis(t-1)) =  beta_dis;
    end

    Aeq = [Aeq_energy; Aeq_soc];
    beq = [beq_energy; beq_soc];

    % --------------------------------------------------------------
    % Egyenlőtlenségi korlátok
    % --------------------------------------------------------------
    A = [];
    b = [];

    A_bin = zeros(2*N, nVars);
    b_bin = zeros(2*N, 1);

    for t = 1:N
        A_bin(t, iCh(t))   = 1;
        A_bin(t, iMode(t)) = -P_ch_max;
        b_bin(t) = 0;

        A_bin(N+t, iDis(t))  = 1;
        A_bin(N+t, iMode(t)) = P_dis_max;
        b_bin(N+t) = P_dis_max;
    end

    A = [A; A_bin];
    b = [b; b_bin];

    A_curt = zeros(N, nVars);
    b_curt = zeros(N, 1);
    for t = 1:N
        A_curt(t, iCurt(t)) = 1;
        b_curt(t) = P_pv_ac(t);
    end
    A = [A; A_curt];
    b = [b; b_curt];

    A_peak = zeros(N, nVars);
    b_peak = zeros(N, 1);
    for t = 1:N
        A_peak(t, iGrid(t)) = 1;
        A_peak(t, iPeak)    = -1;
    end
    A = [A; A_peak];
    b = [b; b_peak];

    row_over = zeros(1, nVars);
    row_over(iPeak) = 1;
    row_over(iOver) = -1;
    A = [A; row_over];
    b = [b; P_limit_ref];

    % --------------------------------------------------------------
    % Alsó/felső korlátok
    % --------------------------------------------------------------
    lb = zeros(nVars, 1);
    ub = inf(nVars, 1);

    lb(iSoc) = soc_min_vec;
    ub(iSoc) = pars.SoC_max;

    lb(iMode) = 0;
    ub(iMode) = 1;

    intcon = iMode;

    % Rövidebb max idő gyorsításhoz
    options = optimoptions('intlinprog', ...
        'Display', 'off', ...
        'MaxTime', 15, ...
        'RelativeGapTolerance', 0.01, ...
        'IntegerPreprocess', 'advanced', ...
        'RootLPAlgorithm', 'dual-simplex');

    [x, fval, exitflag] = intlinprog(f, intcon, A, b, Aeq, beq, lb, ub, options);

    % --------------------------------------------------------------
    % Kimenet
    % --------------------------------------------------------------
    plan = struct();

    if isempty(x) || exitflag <= 0
        fallback_peak = max(max(P_load_f - P_pv_ac, 0), P_limit_ref);

        plan.P_limit = fallback_peak;
        plan.P_limit_ref = P_limit_ref;
        plan.P_over_contract = max(0, fallback_peak - P_limit_ref);

        plan.trade_buy_mask  = false(1, N);
        plan.trade_sell_mask = false(1, N);

        plan.P_grid_plan = max(P_load_f - P_pv_ac, 0);
        plan.P_ch_plan   = zeros(N, 1);
        plan.P_dis_plan  = zeros(N, 1);
        plan.P_curt_plan = max(P_pv_ac - P_load_f, 0);
        plan.SoC_plan    = SoC_start * ones(N, 1);

        plan.objective_value = inf;
        plan.exitflag = exitflag;

        plan.economics.energy_cost_market      = sum(buy_p_market .* plan.P_grid_plan) * dt_h;
        plan.economics.energy_cost_network     = sum((dist_energy_fee + trans_energy_fee) .* plan.P_grid_plan) * dt_h;
        plan.economics.energy_cost_total       = plan.economics.energy_cost_market + plan.economics.energy_cost_network;
        plan.economics.degradation_cost        = 0;
        plan.economics.overrun_cost_proxy      = overrun_penalty_day * plan.P_over_contract;
        plan.economics.peak_shadow_cost        = peak_shadow_day * plan.P_limit;
        plan.economics.net_cost_operational    = inf;
        plan.economics.contract_charge_annual  = annual_contract_rate * P_contract;
        plan.economics.base_fee_annual         = annual_base_fee;
        plan.economics.P_contract              = P_contract;
        plan.economics.P_limit_ref             = P_limit_ref;
        return;
    end

    P_grid = x(iGrid);
    P_ch   = x(iCh);
    P_dis  = x(iDis);
    SoC    = x(iSoc);
    P_curt = x(iCurt);
    P_peak = x(iPeak);
    P_over = x(iOver);

    plan.P_limit = P_peak;
    plan.P_limit_ref = P_limit_ref;
    plan.P_over_contract = P_over;

    plan.trade_buy_mask  = (P_ch  > 1e-3).';
    plan.trade_sell_mask = (P_dis > 1e-3).';

    plan.P_grid_plan = P_grid;
    plan.P_ch_plan   = P_ch;
    plan.P_dis_plan  = P_dis;
    plan.P_curt_plan = P_curt;
    plan.SoC_plan    = SoC;

    plan.objective_value = fval;
    plan.exitflag = exitflag;

    energy_cost_market  = sum(buy_p_market .* P_grid) * dt_h;
    energy_cost_network = sum((dist_energy_fee + trans_energy_fee) .* P_grid) * dt_h;
    degradation_cost    = sum(cost_deg .* (P_ch + P_dis)) * dt_h;
    overrun_cost_proxy  = overrun_penalty_day * P_over;
    peak_shadow_cost    = peak_shadow_day * P_peak;

    plan.economics.energy_cost_market      = energy_cost_market;
    plan.economics.energy_cost_network     = energy_cost_network;
    plan.economics.energy_cost_total       = energy_cost_market + energy_cost_network;
    plan.economics.degradation_cost        = degradation_cost;
    plan.economics.overrun_cost_proxy      = overrun_cost_proxy;
    plan.economics.peak_shadow_cost        = peak_shadow_cost;
    plan.economics.net_cost_operational    = fval;
    plan.economics.contract_charge_annual  = annual_contract_rate * P_contract;
    plan.economics.base_fee_annual         = annual_base_fee;
    plan.economics.P_contract              = P_contract;
    plan.economics.P_limit_ref             = P_limit_ref;
end

% =========================================================================
% SEGÉDFÜGGVÉNYEK
% =========================================================================
function y = local_aggregate_series_mean(x, agg_factor)
    x = x(:);
    N = floor(numel(x) / agg_factor) * agg_factor;
    x = x(1:N);
    X = reshape(x, agg_factor, []);
    y = mean(X, 1).';
end

function y = local_expand_series_repelem(x, agg_factor, target_len)
    x = x(:);
    y = repelem(x, agg_factor, 1);
    y = y(1:target_len);
end