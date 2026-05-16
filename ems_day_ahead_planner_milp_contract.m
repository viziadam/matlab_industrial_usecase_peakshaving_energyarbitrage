
% function plan = ems_day_ahead_planner_milp_contract(P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, contract_state, target_step_min)
% % EMS_DAY_AHEAD_PLANNER_MILP_CONTRACT
% %
% % TESZTVERZIO:
% % - HARD CAP a halozati importra:
% %       grid->load + grid->batt <= P_contract
% % - a regi havi peak / overrun logika kikommentelve megmarad
% % - a kompatibilitas miatt a korabbi mezok visszaadasra kerulnek,
% %   de nullazott formaban, ha ebben a tesztverzioban nem hasznaljuk oket.
% %
% % Bemenet:
% %   P_load_f        : terhelesi forecast [kW]
% %   P_pv_dc_f       : PV DC forecast [kW]
% %   Prices.buy_huf  : veteli ar [HUF/kWh]
% %   pars            : BESS parameterek
% %   tariff          : tarifa parameterek
% %   dt_h            : eredeti idolepes [h]
% %   contract_state  : struct
% %       .P_contract_kW
% %       .P_month_max_so_far_kW
% %       .current_day_of_month
% %   target_step_min : opcionális MILP idofelbontas percben
% %                     peldaul 5, 10, 15, 30, 60
% %                     5 perc tobbszorose kell legyen
% %
% % Kimenet:
% %   plan            : az eredeti idofelbontasra visszanagyitott terv
% 
%     % ---------------------------------------------------------------------
%     % OPCIONALIS MILP IDOFELBONTAS
%     % ---------------------------------------------------------------------
%     if nargin < 8 || isempty(target_step_min)
%         target_step_min = 60;
%     end
% 
%     % ---------------------------------------------------------------------
%     % HIANYZO TARIFA MEZOK POTLASA
%     % ---------------------------------------------------------------------
%     if ~isfield(tariff, 'distribution_energy_rate_huf_per_kWh')
%         tariff.distribution_energy_rate_huf_per_kWh = 8.39;
%     end
%     if ~isfield(tariff, 'transmission_energy_rate_huf_per_kWh')
%         tariff.transmission_energy_rate_huf_per_kWh = 3.39;
%     end
%     if ~isfield(tariff, 'annual_contracted_power_fee_huf_per_kW')
%         tariff.annual_contracted_power_fee_huf_per_kW = 15924;
%     end
%     if ~isfield(tariff, 'annual_base_fee_huf')
%         tariff.annual_base_fee_huf = 216504;
%     end
%     if ~isfield(tariff, 'contracted_capacity_kW')
%         tariff.contracted_capacity_kW = 350;
%     end
%     if ~isfield(tariff, 'days_in_year')
%         tariff.days_in_year = 365;
%     end
%     if ~isfield(tariff, 'months_in_year')
%         tariff.months_in_year = 12;
%     end
%     if ~isfield(tariff, 'penalty_rate_huf_per_kW_year')
%         tariff.penalty_rate_huf_per_kW_year = 4.0 * tariff.annual_contracted_power_fee_huf_per_kW;
%     end
%     if ~isfield(tariff, 'curtailment_penalty_huf_per_kWh')
%         tariff.curtailment_penalty_huf_per_kWh = 0.0;
%     end
%     if ~isfield(tariff, 'grid_charge_price_quantile')
%         tariff.grid_charge_price_quantile = 0.25;
%     end
%     if ~isfield(tariff, 'noncheap_charge_penalty_huf_per_kWh')
%         tariff.noncheap_charge_penalty_huf_per_kWh = 0.0;
%     end
%     if ~isfield(tariff, 'within_contract_peak_weight_huf_per_kW_month')
%         tariff.within_contract_peak_weight_huf_per_kW_month = 0.0;
%     end
% 
%     % ---------------------------------------------------------------------
%     % EREDETI IDOFELBONTAS ELMENTESE
%     % ---------------------------------------------------------------------
%     P_load_f_orig  = P_load_f(:);
%     P_pv_dc_f_orig = P_pv_dc_f(:);
%     buy_p_orig     = Prices.buy_huf(:);
% 
%     N_orig = length(P_load_f_orig);
% 
%     % ---------------------------------------------------------------------
%     % AGGREGALAS MEGADOTT MILP IDOFELBONTASRA
%     % ---------------------------------------------------------------------
%     [P_load_f, P_pv_dc_f, buy_p_market, dt_milp, expand_factor] = ...
%         local_prepare_hourly_forecast( ...
%             P_load_f_orig, ...
%             P_pv_dc_f_orig, ...
%             buy_p_orig, ...
%             dt_h, ...
%             target_step_min);
% 
%     N = length(P_load_f);
% 
%     % ---------------------------------------------------------------------
%     % PARAMETEREK
%     % ---------------------------------------------------------------------
%     eta_c_path = pars.inv_eta * pars.eta_c * pars.eta_cell;
%     eta_d_path = pars.eta_cell * pars.eta_d * pars.inv_eta;
% 
%     deg_model = build_article_simple_degradation_costs(pars);
%     cost_deg_ch  = deg_model.cost_ch_huf_per_kWh;
%     cost_deg_dis = deg_model.cost_dis_huf_per_kWh;
% 
%     if isfield(pars, 'SoC_initial')
%         SoC_start = pars.SoC_initial;
%     else
%         SoC_start = 0.5;
%     end
% 
%     P_ch_max  = pars.P_chg_max;
%     P_dis_max = pars.P_dis_max;
% 
%     P_contract = contract_state.P_contract_kW;
% 
%     % ---------------------------------------------------------------------
%     % BIZTONSAGI TARTALEK A LEKOTOTT TELJESITMENYRE
%     % ---------------------------------------------------------------------
%     % A MILP nem a teljes lekotott teljesitmenyre tervez, hanem annak
%     % egy biztonsagi faktorral csokkentett ertekere.
%     %
%     % Pelda:
%     %   P_contract = 480 kW
%     %   safety_factor = 0.90
%     %   P_grid_hard_cap = 432 kW
%     %
%     % Igy a kesobbi veszteseg, forecast/actual elteres es topology
%     % vegrehajtasi hiba ellen marad tartalek.
%     if isfield(contract_state, 'P_contract_safety_factor')
%         P_contract_safety_factor = contract_state.P_contract_safety_factor;
%     else
%         P_contract_safety_factor = 0.90;
%     end
% 
%     if P_contract_safety_factor <= 0 || P_contract_safety_factor > 1
%         error('P_contract_safety_factor must be in the interval (0, 1].');
%     end
% 
%     P_grid_hard_cap = P_contract_safety_factor * P_contract;
% 
%     % ---------------------------------------------------------------------
%     % REGI VERZIOHOZ TARTOZO VALTOZOK - KOMPATIBILITAS MIATT MEGTARTVA
%     % ---------------------------------------------------------------------
%     if isfield(contract_state, 'P_month_max_so_far_kW')
%         P_month_max_so_far = contract_state.P_month_max_so_far_kW;
%     else
%         P_month_max_so_far = 0;
%     end
% 
%     prev_overrun = 0;
% 
%     dist_fee = tariff.distribution_energy_rate_huf_per_kWh;
%     trans_fee = tariff.transmission_energy_rate_huf_per_kWh;
%     buy_p_total = buy_p_market + dist_fee + trans_fee;
% 
%     % Ebben a tesztverzioban nem hasznaljuk oket, de legyenek definialva
%     monthly_overrun_cost_per_kW = 0;
%     within_contract_peak_weight = 0;
%     overrun_cost_per_kW_step = 0;
% 
%     P_pv_ac = min(P_pv_dc_f * pars.inv_eta, pars.P_inv_limit_ac);
% 
%     soc_min_vec = pars.SoC_min * ones(N,1);
% 
%     % ---------------------------------------------------------------------
%     % DONTESI VALTOZOK
%     % ---------------------------------------------------------------------
%     % P_gl    : grid -> load
%     % P_gb    : grid -> battery
%     % P_pl    : pv   -> load
%     % P_pb    : pv   -> battery
%     % P_bl    : battery -> load
%     % SoC
%     % mode    : binaris, 1 = discharge mode, 0 = charge/idle mode
%     % Curt
%     %
%     % A regi verzio:
%     % MonthPeak
%     % OverInc
%     % OverStep
%     %
%     % Ezeket most nem hasznaljuk aktivan, de kompatibilitas miatt
%     % visszaadjuk nullazott mezok formajaban.
% 
%     n0 = 0;
%     iGload     = n0 + (1:N); n0 = n0 + N;
%     iGbatt     = n0 + (1:N); n0 = n0 + N;
%     iPVload    = n0 + (1:N); n0 = n0 + N;
%     iPVbatt    = n0 + (1:N); n0 = n0 + N;
%     iBload     = n0 + (1:N); n0 = n0 + N;
%     iSoc       = n0 + (1:N); n0 = n0 + N;
%     iMode      = n0 + (1:N); n0 = n0 + N;
%     iCurt      = n0 + (1:N); n0 = n0 + N;
% 
%     % ---------------------------------------------------------------------
%     % REGI, NEM HASZNALT RESZEK - KIKOMMENTELVE
%     % ---------------------------------------------------------------------
%     % iMonthPeak = n0 + 1;     n0 = n0 + 1;
%     % iOverInc   = n0 + 1;     n0 = n0 + 1;
%     % iOverStep  = n0 + (1:N); n0 = n0 + N;
% 
%     nVars = n0;
% 
%     % ---------------------------------------------------------------------
%     % CELFUGGVENY
%     % ---------------------------------------------------------------------
%     f = zeros(nVars, 1);
% 
%     % Halozati energia
%     f(iGload) = buy_p_total * dt_milp;
%     f(iGbatt) = buy_p_total * dt_milp;
% 
%     % Degradacio
%     f(iGbatt)  = f(iGbatt)  + cost_deg_ch  * dt_milp;
%     f(iPVbatt) = f(iPVbatt) + cost_deg_ch  * dt_milp;
%     f(iBload)  = f(iBload)  + cost_deg_dis * dt_milp;
% 
%     % Curtailment
%     f(iCurt) = tariff.curtailment_penalty_huf_per_kWh * dt_milp;
% 
%     % ---------------------------------------------------------------------
%     % REGI, NEM HASZNALT RESZEK - KIKOMMENTELVE
%     % ---------------------------------------------------------------------
%     % f(iMonthPeak) = within_contract_peak_weight;
%     % f(iOverInc)   = monthly_overrun_cost_per_kW;
%     % f(iOverStep)  = overrun_cost_per_kW_step;
% 
%     % ---------------------------------------------------------------------
%     % EGYENLOSEGI FELTETELEK
%     % ---------------------------------------------------------------------
%     % Load ellatas:
%     % grid->load + pv->load + batt->load = load
%     Aeq_load = zeros(N, nVars);
%     beq_load = P_load_f;
% 
%     for t = 1:N
%         Aeq_load(t, iGload(t))  = 1;
%         Aeq_load(t, iPVload(t)) = 1;
%         Aeq_load(t, iBload(t))  = 1;
%     end
% 
%     % PV szetosztas:
%     % pv->load + pv->batt + curt = pv_ac
%     Aeq_pv = zeros(N, nVars);
%     beq_pv = P_pv_ac;
% 
%     for t = 1:N
%         Aeq_pv(t, iPVload(t)) = 1;
%         Aeq_pv(t, iPVbatt(t)) = 1;
%         Aeq_pv(t, iCurt(t))   = 1;
%     end
% 
%     % SoC dinamika
%     Aeq_soc = zeros(N, nVars);
%     beq_soc = zeros(N, 1);
% 
%     Aeq_soc(1, iSoc(1)) = 1;
%     beq_soc(1) = SoC_start;
% 
%     alpha_ch = (eta_c_path * dt_milp) / pars.E_cap_nom;
%     beta_dis = (dt_milp / eta_d_path) / pars.E_cap_nom;
% 
%     for t = 2:N
%         Aeq_soc(t, iSoc(t))       =  1;
%         Aeq_soc(t, iSoc(t-1))     = -1;
%         Aeq_soc(t, iGbatt(t-1))   = -alpha_ch;
%         Aeq_soc(t, iPVbatt(t-1))  = -alpha_ch;
%         Aeq_soc(t, iBload(t-1))   =  beta_dis;
%     end
% 
%     Aeq = [Aeq_load; Aeq_pv; Aeq_soc];
%     beq = [beq_load; beq_pv; beq_soc];
% 
%     % ---------------------------------------------------------------------
%     % EGYENLOTLENSEGI FELTETELEK
%     % ---------------------------------------------------------------------
%     A = [];
%     b = [];
% 
%     % Toltes / kisutes mod
%     % grid->batt + pv->batt <= P_ch_max * (1 - mode)
%     A_ch = zeros(N, nVars);
%     b_ch = P_ch_max * ones(N,1);
% 
%     for t = 1:N
%         A_ch(t, iGbatt(t)) = 1;
%         A_ch(t, iPVbatt(t)) = 1;
%         A_ch(t, iMode(t)) = P_ch_max;
%     end
% 
%     A = [A; A_ch];
%     b = [b; b_ch];
% 
%     % batt->load <= P_dis_max * mode
%     A_dis = zeros(N, nVars);
%     b_dis = zeros(N,1);
% 
%     for t = 1:N
%         A_dis(t, iBload(t)) = 1;
%         A_dis(t, iMode(t))  = -P_dis_max;
%     end
% 
%     A = [A; A_dis];
%     b = [b; b_dis];
% 
%     % ---------------------------------------------------------------------
%     % UJ AKTIV TESZTLOGIKA:
%     % HARD CAP a teljes halozati importra
%     % grid->load + grid->batt <= P_contract
%     % ---------------------------------------------------------------------
%     A_grid_cap = zeros(N, nVars);
%     % b_grid_cap = P_contract * ones(N,1);
%     b_grid_cap = P_grid_hard_cap * ones(N,1);
% 
%     for t = 1:N
%         A_grid_cap(t, iGload(t)) = 1;
%         A_grid_cap(t, iGbatt(t)) = 1;
%     end
% 
%     A = [A; A_grid_cap];
%     b = [b; b_grid_cap];
% 
%     % ---------------------------------------------------------------------
%     % REGI, NEM HASZNALT RESZEK - KIKOMMENTELVE
%     % ---------------------------------------------------------------------
%     % % Havi peak >= teljes halozati import
%     % A_peak = zeros(N, nVars);
%     % b_peak = zeros(N, 1);
%     % for t = 1:N
%     %     A_peak(t, iGload(t))     = 1;
%     %     A_peak(t, iGbatt(t))     = 1;
%     %     A_peak(t, iMonthPeak)    = -1;
%     % end
%     % A = [A; A_peak];
%     % b = [b; b_peak];
%     %
%     % % Overrun novekmeny:
%     % row_over = zeros(1, nVars);
%     % row_over(iMonthPeak) = 1;
%     % row_over(iOverInc)   = -1;
%     % A = [A; row_over];
%     % b = [b; P_contract + prev_overrun];
%     %
%     % % Idolepesenkenti overrun buntetes
%     % A_over_step = zeros(N, nVars);
%     % b_over_step = P_contract * ones(N,1);
%     % for t = 1:N
%     %     A_over_step(t, iGload(t))    =  1;
%     %     A_over_step(t, iGbatt(t))    =  1;
%     %     A_over_step(t, iOverStep(t)) = -1;
%     % end
%     % A = [A; A_over_step];
%     % b = [b; b_over_step];
% 
%     % Horizon vegen SoC ne legyen kisebb mint indulaskor
%     row_terminal_soc = zeros(1, nVars);
%     row_terminal_soc(iSoc(N)) = -1;
% 
%     A = [A; row_terminal_soc];
%     b = [b; -SoC_start];
% 
%     % ---------------------------------------------------------------------
%     % ALSO/FELSO KORLATOK
%     % ---------------------------------------------------------------------
%     lb = zeros(nVars, 1);
%     ub = inf(nVars, 1);
% 
%     lb(iSoc) = soc_min_vec;
%     ub(iSoc) = pars.SoC_max;
% 
%     lb(iMode) = 0;
%     ub(iMode) = 1;
% 
%     % ---------------------------------------------------------------------
%     % REGI, NEM HASZNALT RESZEK - KIKOMMENTELVE
%     % ---------------------------------------------------------------------
%     % lb(iMonthPeak) = P_month_max_so_far;
%     % lb(iOverInc)   = 0;
%     % lb(iOverStep)  = 0;
% 
%     intcon = iMode;
% 
%     % ---------------------------------------------------------------------
%     % SOLVER
%     % ---------------------------------------------------------------------
%     options = optimoptions('intlinprog', ...
%         'Display', 'off', ...
%         'MaxTime', 15, ...
%         'RelativeGapTolerance', 0.01, ...
%         'IntegerPreprocess', 'advanced', ...
%         'RootLPAlgorithm', 'dual-simplex');
% 
%     [x, fval, exitflag] = intlinprog(f, intcon, A, b, Aeq, beq, lb, ub, options);
% 
%     % ---------------------------------------------------------------------
%     % FALLBACK
%     % ---------------------------------------------------------------------
%     if isempty(x) || exitflag <= 0
%         fallback_grid = max(P_load_f - P_pv_ac, 0);
% 
%         plan_hourly = struct();
%         plan_hourly.P_contract = P_contract;
%         plan_hourly.P_month_max_so_far = P_month_max_so_far;
% 
%         % Kompatibilitasi mezok
%         plan_hourly.P_month_peak_candidate = max(fallback_grid);
%         plan_hourly.P_overrun_increment_kW = 0;
%         plan_hourly.P_over_step_plan = zeros(N,1);
% 
%         plan_hourly.trade_buy_mask  = false(1, N);
%         plan_hourly.trade_sell_mask = false(1, N);
% 
%         plan_hourly.P_grid_plan = fallback_grid;
%         plan_hourly.P_ch_plan   = zeros(N, 1);
%         plan_hourly.P_dis_plan  = zeros(N, 1);
%         plan_hourly.P_curt_plan = max(P_pv_ac - P_load_f, 0);
%         plan_hourly.SoC_plan    = SoC_start * ones(N, 1);
% 
%         plan_hourly.P_gload_plan  = fallback_grid;
%         plan_hourly.P_gbatt_plan  = zeros(N,1);
%         plan_hourly.P_pvload_plan = min(P_pv_ac, P_load_f);
%         plan_hourly.P_pvbatt_plan = zeros(N,1);
%         plan_hourly.P_bload_plan  = zeros(N,1);
% 
%         plan_hourly.exitflag = exitflag;
%         plan_hourly.objective_value = inf;
% 
%         plan_hourly.economics.energy_cost_market = sum(buy_p_market(:) .* plan_hourly.P_grid_plan(:)) * dt_milp;
%         plan_hourly.economics.energy_cost_network = sum((dist_fee + trans_fee) .* plan_hourly.P_grid_plan(:)) * dt_milp;
%         plan_hourly.economics.energy_cost_total = ...
%             plan_hourly.economics.energy_cost_market + plan_hourly.economics.energy_cost_network;
%         plan_hourly.economics.degradation_cost = 0;
%         plan_hourly.economics.overrun_increment_cost = 0;
%         plan_hourly.economics.net_cost_operational = inf;
% 
%         plan = local_expand_hourly_plan_to_original(plan_hourly, N_orig, expand_factor);
%         return;
%     end
% 
%     % ---------------------------------------------------------------------
%     % MEGOLDAS KIBONTASA
%     % ---------------------------------------------------------------------
%     P_gload  = x(iGload);
%     P_gbatt  = x(iGbatt);
%     P_pvload = x(iPVload);
%     P_pvbatt = x(iPVbatt);
%     P_bload  = x(iBload);
%     SoC      = x(iSoc);
%     P_curt   = x(iCurt);
% 
%     P_grid_total   = P_gload + P_gbatt;
%     P_charge_total = P_gbatt + P_pvbatt;
%     P_dis_total    = P_bload;
% 
%     plan_hourly = struct();
%     plan_hourly.P_contract = P_contract;
%     plan_hourly.P_month_max_so_far = P_month_max_so_far;
% 
%     % Kompatibilitasi mezok
%     plan_hourly.P_month_peak_candidate = max(P_grid_total);
%     plan_hourly.P_overrun_increment_kW = 0;
%     plan_hourly.P_over_step_plan = zeros(N,1);
% 
%     plan_hourly.trade_buy_mask  = (P_gbatt > 1e-3).';
%     plan_hourly.trade_sell_mask = (P_bload > 1e-3).';
% 
%     plan_hourly.P_grid_plan = P_grid_total;
%     plan_hourly.P_ch_plan   = P_charge_total;
%     plan_hourly.P_dis_plan  = P_dis_total;
%     plan_hourly.P_curt_plan = P_curt;
%     plan_hourly.SoC_plan    = SoC;
% 
%     plan_hourly.P_gload_plan  = P_gload;
%     plan_hourly.P_gbatt_plan  = P_gbatt;
%     plan_hourly.P_pvload_plan = P_pvload;
%     plan_hourly.P_pvbatt_plan = P_pvbatt;
%     plan_hourly.P_bload_plan  = P_bload;
% 
%     plan_hourly.exitflag = exitflag;
%     plan_hourly.objective_value = fval;
% 
%     energy_cost_market  = sum(buy_p_market(:) .* P_grid_total(:)) * dt_milp;
%     energy_cost_network = sum((dist_fee + trans_fee) .* P_grid_total(:)) * dt_milp;
%     degradation_cost    = ...
%         sum(cost_deg_ch  .* P_charge_total(:)) * dt_milp + ...
%         sum(cost_deg_dis .* P_dis_total(:))    * dt_milp;
%     overrun_increment_cost = 0;
% 
%     plan_hourly.economics.energy_cost_market = energy_cost_market;
%     plan_hourly.economics.energy_cost_network = energy_cost_network;
%     plan_hourly.economics.energy_cost_total = energy_cost_market + energy_cost_network;
%     plan_hourly.economics.degradation_cost = degradation_cost;
%     plan_hourly.economics.overrun_increment_cost = overrun_increment_cost;
%     plan_hourly.economics.net_cost_operational = ...
%         energy_cost_market + energy_cost_network + degradation_cost + overrun_increment_cost;
% 
%     % ---------------------------------------------------------------------
%     % VISSZAALAKITAS EREDETI FELBONTASRA
%     % ---------------------------------------------------------------------
%     plan = local_expand_hourly_plan_to_original(plan_hourly, N_orig, expand_factor);
% end
% 
% 
% % =========================================================================
% % BELSO SEGEDFUGGVENYEK
% % =========================================================================
% % function [P_load_h, P_pv_h, buy_h, dt_out, expand_factor] = local_prepare_hourly_forecast(P_load, P_pv, buy_p, dt_in, target_step_min)
% % % LOCAL_PREPARE_HOURLY_FORECAST
% % %
% % % Az eredeti idosorokat megadott perces MILP felbontasra aggregalja.
% % %
% % % Pelda:
% % %   dt_in = 1/12 es target_step_min = 15
% % %   Ekkor az eredeti 5 perces adatokbol 15 perces adatok keszulnek,
% % %   vagyis expand_factor = 3.
% % %
% % % Fontos:
% % %   - target_step_min 5 perc tobbszorose kell legyen
% % %   - target_step_min nem lehet kisebb, mint az eredeti idolepes
% % %   - target_step_min az eredeti idolepes egesz szamu tobbszorose kell legyen
% % 
% %     P_load = P_load(:);
% %     P_pv   = P_pv(:);
% %     buy_p  = buy_p(:);
% % 
% %     if nargin < 5 || isempty(target_step_min)
% %         target_step_min = 60;
% %     end
% % 
% %     if dt_in <= 0
% %         error('local_prepare_hourly_forecast: dt_in must be positive');
% %     end
% % 
% %     if target_step_min <= 0
% %         error('local_prepare_hourly_forecast: target_step_min must be positive');
% %     end
% % 
% %     if abs(target_step_min / 5 - round(target_step_min / 5)) > 1e-9
% %         error('local_prepare_hourly_forecast: target_step_min must be a multiple of 5 minutes');
% %     end
% % 
% %     input_step_min = dt_in * 60;
% % 
% %     if abs(input_step_min / 5 - round(input_step_min / 5)) > 1e-9
% %         error('local_prepare_hourly_forecast: input time step must be a multiple of 5 minutes');
% %     end
% % 
% %     if target_step_min < input_step_min
% %         error('local_prepare_hourly_forecast: target_step_min cannot be smaller than the input time step');
% %     end
% % 
% %     expand_factor_real = target_step_min / input_step_min;
% %     expand_factor = round(expand_factor_real);
% % 
% %     can_aggregate = ...
% %         abs(expand_factor_real - expand_factor) < 1e-9 && ...
% %         expand_factor >= 1;
% % 
% %     if ~can_aggregate
% %         error('local_prepare_hourly_forecast: target_step_min must be an integer multiple of the input time step');
% %     end
% % 
% %     if expand_factor == 1
% %         P_load_h = P_load;
% %         P_pv_h   = P_pv;
% %         buy_h    = buy_p;
% %         dt_out   = dt_in;
% %         return;
% %     end
% % 
% %     N = min([length(P_load), length(P_pv), length(buy_p)]);
% %     P_load = P_load(1:N);
% %     P_pv   = P_pv(1:N);
% %     buy_p  = buy_p(1:N);
% % 
% %     nBlocks = floor(N / expand_factor);
% % 
% %     if nBlocks < 1
% %         P_load_h = P_load;
% %         P_pv_h   = P_pv;
% %         buy_h    = buy_p;
% %         dt_out   = dt_in;
% %         expand_factor = 1;
% %         return;
% %     end
% % 
% %     N_use = nBlocks * expand_factor;
% % 
% %     P_load_use = P_load(1:N_use);
% %     P_pv_use   = P_pv(1:N_use);
% %     buy_use    = buy_p(1:N_use);
% % 
% %     P_load_mat = reshape(P_load_use, expand_factor, nBlocks);
% %     P_pv_mat   = reshape(P_pv_use,   expand_factor, nBlocks);
% %     buy_mat    = reshape(buy_use,    expand_factor, nBlocks);
% % 
% %     P_load_h = mean(P_load_mat, 1).';
% %     P_pv_h   = mean(P_pv_mat,   1).';
% %     buy_h    = mean(buy_mat,    1).';
% % 
% %     dt_out = target_step_min / 60;
% % end
% 
% function [P_load_h, P_pv_h, buy_h, dt_out, expand_factor] = local_prepare_hourly_forecast(P_load, P_pv, buy_p, dt_in, target_step_min)
% % LOCAL_PREPARE_HOURLY_FORECAST
% %
% % Az eredeti idosorokat megadott perces MILP felbontasra aggregalja.
% %
% % Konzervativ aggregalas peak shaving celra:
% %   - load esetén a blokk maximumát vesszük;
% %   - PV esetén a blokk minimumát vesszük;
% %   - ár esetén a blokk átlagát vesszük.
% %
% % Pelda:
% %   dt_in = 1/12 es target_step_min = 15
% %   Ekkor az eredeti 5 perces adatokbol 15 perces adatok keszulnek,
% %   vagyis expand_factor = 3.
% %
% % Ha egy 15 perces blokkban a load:
% %   [420, 510, 460] kW
% % akkor az aggregalt load:
% %   510 kW
% %
% % Ha ugyanabban a blokkban a PV:
% %   [180, 150, 170] kW
% % akkor az aggregalt PV:
% %   150 kW
% %
% % Fontos:
% %   - target_step_min 5 perc tobbszorose kell legyen
% %   - target_step_min nem lehet kisebb, mint az eredeti idolepes
% %   - target_step_min az eredeti idolepes egesz szamu tobbszorose kell legyen
% 
%     P_load = P_load(:);
%     P_pv   = P_pv(:);
%     buy_p  = buy_p(:);
% 
%     if nargin < 5 || isempty(target_step_min)
%         target_step_min = 60;
%     end
% 
%     if dt_in <= 0
%         error('local_prepare_hourly_forecast: dt_in must be positive');
%     end
% 
%     if target_step_min <= 0
%         error('local_prepare_hourly_forecast: target_step_min must be positive');
%     end
% 
%     if abs(target_step_min / 5 - round(target_step_min / 5)) > 1e-9
%         error('local_prepare_hourly_forecast: target_step_min must be a multiple of 5 minutes');
%     end
% 
%     input_step_min = dt_in * 60;
% 
%     if abs(input_step_min / 5 - round(input_step_min / 5)) > 1e-9
%         error('local_prepare_hourly_forecast: input time step must be a multiple of 5 minutes');
%     end
% 
%     if target_step_min < input_step_min
%         error('local_prepare_hourly_forecast: target_step_min cannot be smaller than the input time step');
%     end
% 
%     expand_factor_real = target_step_min / input_step_min;
%     expand_factor = round(expand_factor_real);
% 
%     can_aggregate = ...
%         abs(expand_factor_real - expand_factor) < 1e-9 && ...
%         expand_factor >= 1;
% 
%     if ~can_aggregate
%         error('local_prepare_hourly_forecast: target_step_min must be an integer multiple of the input time step');
%     end
% 
%     if expand_factor == 1
%         P_load_h = P_load;
%         P_pv_h   = P_pv;
%         buy_h    = buy_p;
%         dt_out   = dt_in;
%         return;
%     end
% 
%     N = min([length(P_load), length(P_pv), length(buy_p)]);
%     P_load = P_load(1:N);
%     P_pv   = P_pv(1:N);
%     buy_p  = buy_p(1:N);
% 
%     nBlocks = floor(N / expand_factor);
% 
%     if nBlocks < 1
%         P_load_h = P_load;
%         P_pv_h   = P_pv;
%         buy_h    = buy_p;
%         dt_out   = dt_in;
%         expand_factor = 1;
%         return;
%     end
% 
%     N_use = nBlocks * expand_factor;
% 
%     P_load_use = P_load(1:N_use);
%     P_pv_use   = P_pv(1:N_use);
%     buy_use    = buy_p(1:N_use);
% 
%     P_load_mat = reshape(P_load_use, expand_factor, nBlocks);
%     P_pv_mat   = reshape(P_pv_use,   expand_factor, nBlocks);
%     buy_mat    = reshape(buy_use,    expand_factor, nBlocks);
% 
%     % Konzervativ aggregalas:
%     % load: legnagyobb ertek
%     % PV:   legkisebb ertek
%     % ar:   atlag
%     P_load_h = max(P_load_mat, [], 1).';
%     P_pv_h   = min(P_pv_mat,   [], 1).';
%     buy_h    = mean(buy_mat,      1).';
% 
%     dt_out = target_step_min / 60;
% end
% 
% 
% function plan_out = local_expand_hourly_plan_to_original(plan_in, N_orig, expand_factor)
% % LOCAL_EXPAND_HOURLY_PLAN_TO_ORIGINAL
% %
% % Az aggregalt MILP-tervet visszaterjeszti az eredeti idofelbontasra.
% %
% % Pelda:
% %   eredeti adat: 5 perc
% %   MILP adat:    15 perc
% %   expand_factor = 3
% %
% % Ekkor minden 15 perces MILP dontes 3 darab 5 perces lepesre lesz
% % megismetelve.
% 
%     if expand_factor <= 1
%         plan_out = plan_in;
%         return;
%     end
% 
%     plan_out = plan_in;
% 
%     plan_out.trade_buy_mask  = local_repeat_to_length(logical(plan_in.trade_buy_mask(:)),  N_orig, expand_factor).';
%     plan_out.trade_sell_mask = local_repeat_to_length(logical(plan_in.trade_sell_mask(:)), N_orig, expand_factor).';
% 
%     plan_out.P_grid_plan = local_repeat_to_length(plan_in.P_grid_plan(:), N_orig, expand_factor);
%     plan_out.P_ch_plan   = local_repeat_to_length(plan_in.P_ch_plan(:),   N_orig, expand_factor);
%     plan_out.P_dis_plan  = local_repeat_to_length(plan_in.P_dis_plan(:),  N_orig, expand_factor);
%     plan_out.P_curt_plan = local_repeat_to_length(plan_in.P_curt_plan(:), N_orig, expand_factor);
%     plan_out.SoC_plan    = local_repeat_to_length(plan_in.SoC_plan(:),    N_orig, expand_factor);
% 
%     if isfield(plan_in, 'P_gload_plan')
%         plan_out.P_gload_plan = local_repeat_to_length(plan_in.P_gload_plan(:), N_orig, expand_factor);
%     end
%     if isfield(plan_in, 'P_gbatt_plan')
%         plan_out.P_gbatt_plan = local_repeat_to_length(plan_in.P_gbatt_plan(:), N_orig, expand_factor);
%     end
%     if isfield(plan_in, 'P_pvload_plan')
%         plan_out.P_pvload_plan = local_repeat_to_length(plan_in.P_pvload_plan(:), N_orig, expand_factor);
%     end
%     if isfield(plan_in, 'P_pvbatt_plan')
%         plan_out.P_pvbatt_plan = local_repeat_to_length(plan_in.P_pvbatt_plan(:), N_orig, expand_factor);
%     end
%     if isfield(plan_in, 'P_bload_plan')
%         plan_out.P_bload_plan = local_repeat_to_length(plan_in.P_bload_plan(:), N_orig, expand_factor);
%     end
%     if isfield(plan_in, 'P_over_step_plan')
%         plan_out.P_over_step_plan = local_repeat_to_length(plan_in.P_over_step_plan(:), N_orig, expand_factor);
%     end
% end
% 
% 
% function y = local_repeat_to_length(x, N_target, rep_factor)
% 
%     x = x(:);
%     y = repelem(x, rep_factor, 1);
% 
%     if length(y) >= N_target
%         y = y(1:N_target);
%         return;
%     end
% 
%     y = [y; repmat(y(end), N_target - length(y), 1)];
% end

function plan = ems_day_ahead_planner_milp_contract( ...
    P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, contract_state, maxSolverTime_s)
% EMS_DAY_AHEAD_PLANNER_MILP_CONTRACT
%
% DC-csatolt PV+BESS MILP planner.
%
% Felbontott energiaaramok:
%   PgL     grid -> load
%   PgB     grid -> BESS
%   PpvL    PV   -> load
%   PpvB    PV   -> BESS
%   PbL     BESS -> load
%   Pspill  nem hasznositott PV
%   Pover   P_grid_limit feletti halozati import
%
% Egyenletek:
%   PgL + PpvL + PbL = Pload
%   PpvL + PpvB + Pspill = Ppv_ac
%
% Soft grid-limit:
%   PgL + PgB - Pover <= P_grid_limit
%   Pover >= 0
%
% Vagyis a limit tullepheto, de minden idolepesben buntetett.
%
% DC-csatolasbol adodo sajatossag:
%   A PV DC oldali teljesitmeny a plannerben inverteren keresztul
%   AC oldali hasznosithato PV teljesitmenykent jelenik meg:
%
%       Ppv = min(Ppvdc * pars.inv_eta, pars.P_inv_limit_ac)
%
%   A BESS toltes/kisutes SoC-hatasfokai a DC-csatolt utvonalat kovetik:
%
%       etaCh  = pars.inv_eta * pars.eta_c * pars.eta_cell
%       etaDis = pars.eta_cell * pars.eta_d * pars.inv_eta

    if nargin < 8
        maxSolverTime_s = 15;
    end

    requiredParsFields = { ...
        'E_cap_nom', ...
        'P_chg_max', ...
        'P_dis_max', ...
        'SoC_min', ...
        'SoC_max', ...
        'inv_eta', ...
        'eta_c', ...
        'eta_d', ...
        'eta_cell', ...
        'P_inv_limit_ac'};

    for k = 1:numel(requiredParsFields)
        if ~isfield(pars, requiredParsFields{k})
            error('Hianyzo pars mezo a DC MILP-ben: pars.%s', requiredParsFields{k});
        end
    end

    requiredTariffFields = { ...
        'distribution_energy_rate_huf_per_kWh', ...
        'transmission_energy_rate_huf_per_kWh', ...
        'penalty_rate_huf_per_kW_year', ...
        'months_in_year'};

    for k = 1:numel(requiredTariffFields)
        if ~isfield(tariff, requiredTariffFields{k})
            error('Hianyzo tariff mezo a DC MILP-ben: tariff.%s', requiredTariffFields{k});
        end
    end

    requiredContractFields = { ...
        'P_contract_kW', ...
        'P_month_max_so_far_kW'};

    for k = 1:numel(requiredContractFields)
        if ~isfield(contract_state, requiredContractFields{k})
            error('Hianyzo contract_state mezo a DC MILP-ben: contract_state.%s', ...
                requiredContractFields{k});
        end
    end

    if ~isfield(Prices, 'buy_huf')
        error('Hianyzo Prices.buy_huf a DC MILP-ben.');
    end

    Pload = P_load_f(:);
    Ppvdc = P_pv_dc_f(:);
    buy   = Prices.buy_huf(:);

    N = numel(Pload);

    if numel(Ppvdc) ~= N || numel(buy) ~= N
        error('DC MILP bemeneti vektorhossz elteres.');
    end

    if isfield(pars, 'SoC_initial')
        SoC0 = pars.SoC_initial;
    else
        SoC0 = 0.5;
    end

    socTol = 1e-4;

    if SoC0 < pars.SoC_min - socTol || SoC0 > pars.SoC_max + socTol
        error(['DC MILP indulo SoC kivul van a megengedett tartomanyon. ', ...
            'SoC0 = %.8f, SoC_min = %.8f, SoC_max = %.8f'], ...
            SoC0, pars.SoC_min, pars.SoC_max);
    end

    SoC0 = min(max(SoC0, pars.SoC_min), pars.SoC_max);

    Pcontract = contract_state.P_contract_kW;
    PmonthOld = contract_state.P_month_max_so_far_kW;

    if isfield(contract_state, 'P_contract_safety_factor')
        safety = contract_state.P_contract_safety_factor;
    else
        safety = 0.90;
    end

    if safety <= 0 || safety > 1
        error('P_contract_safety_factor must be in the interval (0, 1].');
    end

    Plimit = safety * Pcontract;

    % =====================================================================
    % DC-csatolas sajatossagai
    % =====================================================================
    Ppv = min(Ppvdc * pars.inv_eta, pars.P_inv_limit_ac);

    PchMax  = pars.P_chg_max;
    PdisMax = pars.P_dis_max;

    etaCh  = pars.inv_eta * pars.eta_c * pars.eta_cell;
    etaDis = pars.eta_cell * pars.eta_d * pars.inv_eta;

    deg = build_article_simple_degradation_costs(pars);
    cCh  = deg.cost_ch_huf_per_kWh;
    cDis = deg.cost_dis_huf_per_kWh;

    buyTotal = buy ...
        + tariff.distribution_energy_rate_huf_per_kWh ...
        + tariff.transmission_energy_rate_huf_per_kWh;

    % AC plannerrel azonos overrun koltseglogika.
    %cOver = tariff.penalty_rate_huf_per_kW_year / (30);
    cOver = tariff.penalty_rate_huf_per_kW_year / tariff.months_in_year;

    oldOverrun = max(0, PmonthOld - Plimit);

    % =====================================================================
    % Dontesi valtozok
    % =====================================================================
    n = 0;

    iPgL    = n + (1:N); n = n + N;
    iPgB    = n + (1:N); n = n + N;
    iPpvL   = n + (1:N); n = n + N;
    iPpvB   = n + (1:N); n = n + N;
    iPbL    = n + (1:N); n = n + N;
    iPspill = n + (1:N); n = n + N;
    iPover  = n + (1:N); n = n + N;
    iMonthPeak = n + 1;     n = n + 1;
    iOverInc   = n + 1;     n = n + 1;
    iSoc    = n + (1:N); n = n + N;
    iMode   = n + (1:N); n = n + N;

    nVars = n;

    % =====================================================================
    % Celfuggveny
    % =====================================================================
    f = zeros(nVars, 1);

    f(iPgL)   = buyTotal * dt_h;
    f(iPgB)   = buyTotal * dt_h + cCh * dt_h;
    f(iPpvB)  = cCh * dt_h;
    f(iPbL)   = cDis * dt_h;
    % f(iPover) = cOver;
    f(iOverInc) = cOver;

    % PpvL es Pspill koltsege 0, az AC plannerrel azonos logika szerint.

    % =====================================================================
    % Egyenlosegek
    % =====================================================================

    % Load:
    %   PgL + PpvL + PbL = Pload
    AeqLoad = zeros(N, nVars);
    beqLoad = Pload;

    for t = 1:N
        AeqLoad(t, iPgL(t))  = 1;
        AeqLoad(t, iPpvL(t)) = 1;
        AeqLoad(t, iPbL(t))  = 1;
    end

    % PV:
    %   PpvL + PpvB + Pspill = Ppv
    AeqPv = zeros(N, nVars);
    beqPv = Ppv;

    for t = 1:N
        AeqPv(t, iPpvL(t))   = 1;
        AeqPv(t, iPpvB(t))   = 1;
        AeqPv(t, iPspill(t)) = 1;
    end

    % SoC:
    %   SoC(1) = SoC0
    %   SoC(t) = SoC(t-1)
    %          + etaCh*(PgB+PpvB)*dt/E
    %          - PbL*dt/(etaDis*E)
    AeqSoc = zeros(N, nVars);
    beqSoc = zeros(N, 1);

    aCh  = etaCh * dt_h / pars.E_cap_nom;
    aDis = dt_h / etaDis / pars.E_cap_nom;

    AeqSoc(1, iSoc(1)) = 1;
    beqSoc(1) = SoC0;

    for t = 2:N
        AeqSoc(t, iSoc(t))    =  1;
        AeqSoc(t, iSoc(t-1))  = -1;
        AeqSoc(t, iPgB(t-1))  = -aCh;
        AeqSoc(t, iPpvB(t-1)) = -aCh;
        AeqSoc(t, iPbL(t-1))  =  aDis;
    end

    Aeq = [AeqLoad; AeqPv; AeqSoc];
    beq = [beqLoad; beqPv; beqSoc];

    % =====================================================================
    % Egyenlotlensegek
    % =====================================================================
    A = [];
    b = [];

    % Toltes / kisutes kizaras:
    %   PgB + PpvB <= PchMax * mode
    %   PbL <= PdisMax * (1 - mode)
    %
    % Itt az AC planner szerkezeti logikajat kovetjuk.
    AMode = zeros(2*N, nVars);
    bMode = zeros(2*N, 1);

    for t = 1:N
        AMode(t, iPgB(t))  = 1;
        AMode(t, iPpvB(t)) = 1;
        AMode(t, iMode(t)) = -PchMax;

        AMode(N+t, iPbL(t))  = 1;
        AMode(N+t, iMode(t)) = PdisMax;
        bMode(N+t) = PdisMax;
    end

    A = [A; AMode];
    b = [b; bMode];

    % Soft grid-limit:
    %   PgL + PgB - Pover <= Plimit
    AGrid = zeros(N, nVars);
    bGrid = Plimit * ones(N, 1);

    for t = 1:N
        AGrid(t, iPgL(t))   =  1;
        AGrid(t, iPgB(t))   =  1;
        AGrid(t, iPover(t)) = -1;
    end

    A = [A; AGrid];
    b = [b; bGrid];
    
    % Havi peak jelolt:
    %   MonthPeak >= PgL + PgB
    Apeak = zeros(N, nVars);
    bpeak = zeros(N, 1);

    for t = 1:N
        Apeak(t, iPgL(t))       =  1;
        Apeak(t, iPgB(t))       =  1;
        Apeak(t, iMonthPeak)    = -1;
    end

    A = [A; Apeak];
    b = [b; bpeak];


    % Overrun novekmeny:
    %   OverInc >= MonthPeak - Plimit - oldOverrun
    %
    % Atirva <= alakra:
    %   MonthPeak - OverInc <= Plimit + oldOverrun
    AoverInc = zeros(1, nVars);
    boverInc = Plimit + oldOverrun;

    AoverInc(iMonthPeak) =  1;
    AoverInc(iOverInc)   = -1;

    A = [A; AoverInc];
    b = [b; boverInc];


    % Pover felso kotese:
    %   Pover(t) <= oldOverrun + OverInc
    %
    % Ez nem nullazza Pover-t, csak megakadalyozza,
    % hogy koltsegmentes, tetszolegesen nagy slack legyen.
    AoverStep = zeros(N, nVars);
    boverStep = oldOverrun * ones(N, 1);

    for t = 1:N
        AoverStep(t, iPover(t)) =  1;
        AoverStep(t, iOverInc)  = -1;
    end

    A = [A; AoverStep];
    b = [b; boverStep];
    % =====================================================================
    % Korlatok
    % =====================================================================
    lb = zeros(nVars, 1);
    ub = inf(nVars, 1);

    lb(iSoc) = pars.SoC_min;
    ub(iSoc) = pars.SoC_max;

    lb(iMode) = 0;
    ub(iMode) = 1;

    lb(iMonthPeak) = PmonthOld;
    lb(iOverInc) = 0;

    % Ha hard cap modban akarod futtatni, ezt lehet kulso flaggel aktivalni.
    % Peak-only esethez hasznos lesz.
    

    intcon = iMode;

    % =====================================================================
    % Solver
    % =====================================================================
    options = optimoptions('intlinprog', ...
        'Display', 'off', ...
        'MaxTime', maxSolverTime_s, ...
        'RelativeGapTolerance', 0.01, ...
        'IntegerPreprocess', 'advanced', ...
        'RootLPAlgorithm', 'dual-simplex');

    [x, fval, exitflag] = intlinprog( ...
        f, intcon, A, b, Aeq, beq, lb, ub, options);

    if isempty(x) || exitflag <= 0
        plan = local_infeasible_dc_plan( ...
            N, Pcontract, safety, Plimit, PmonthOld, SoC0, exitflag);
        return;
    end

    % =====================================================================
    % Kimenet
    % =====================================================================
    PgL    = x(iPgL);
    PgB    = x(iPgB);
    PpvL   = x(iPpvL);
    PpvB   = x(iPpvB);
    PbL    = x(iPbL);
    Pspill = x(iPspill);
    Pover_raw = x(iPover);
    MonthPeak = x(iMonthPeak);
    OverInc = x(iOverInc);
    SoC = x(iSoc);

    Pgrid = PgL + PgB;
    Pch   = PgB + PpvB;
    Pdis  = PbL;

    % A riporthoz a valos idolepeses overrun erteket szamoljuk,
    % nem a slack valtozo numerikus erteket hasznaljuk.
    Pover = max(Pgrid - Plimit, 0);

    Ppeak = max(PmonthOld, max(Pgrid));

    plan = struct();

    plan.is_feasible = true;
    plan.used_fallback = false;

    plan.P_contract = Pcontract;
    plan.P_contract_safety_factor = safety;
    plan.P_grid_limit = Plimit;

    plan.P_month_max_so_far = PmonthOld;
    plan.P_month_peak_candidate = Ppeak;

    % AC plannerrel azonos ertelmezes:
    % a P_grid_limit feletti legnagyobb idolepeses tullepes.
    plan.P_overrun_increment_kW = OverInc;

    plan.trade_buy_mask  = (Pch  > 1e-6).';
    plan.trade_sell_mask = (Pdis > 1e-6).';

    plan.P_grid_plan = Pgrid(:);
    plan.P_ch_plan   = Pch(:);
    plan.P_dis_plan  = Pdis(:);
    plan.P_curt_plan = Pspill(:);

    plan.P_gload_plan  = PgL(:);
    plan.P_gbatt_plan  = PgB(:);
    plan.P_pvload_plan = PpvL(:);
    plan.P_pvbatt_plan = PpvB(:);
    plan.P_bload_plan  = PbL(:);
    plan.P_spill_plan  = Pspill(:);
    plan.P_over_plan   = Pover(:);
    plan.P_over_step_plan = Pover(:);
    plan.P_pv_ac_plan  = Ppv(:);

    plan.SoC_plan = SoC(:);

    plan.exitflag = exitflag;
    plan.objective_value = fval;

    energyMarket = sum(buy(:) .* Pgrid(:)) * dt_h;

    energyNetwork = ...
        sum((tariff.distribution_energy_rate_huf_per_kWh + ...
             tariff.transmission_energy_rate_huf_per_kWh) .* Pgrid(:)) * dt_h;

    degradationCost = ...
        sum(cCh  .* Pch(:))  * dt_h + ...
        sum(cDis .* Pdis(:)) * dt_h;

    overrunCost = OverInc * cOver;

    plan.economics.energy_cost_market = energyMarket;
    plan.economics.energy_cost_network = energyNetwork;
    plan.economics.energy_cost_total = energyMarket + energyNetwork;
    plan.economics.degradation_cost = degradationCost;
    plan.economics.spill_cost = 0;
    plan.economics.overrun_increment_cost = overrunCost;
    plan.economics.net_cost_operational = ...
        energyMarket + energyNetwork + degradationCost + overrunCost;
end


function plan = local_infeasible_dc_plan( ...
    N, Pcontract, safety, Plimit, PmonthOld, SoC0, exitflag)
% LOCAL_INFEASIBLE_DC_PLAN
%
% AC plannerrel azonos fallback logika:
% ha nincs MILP megoldas, nem probalunk csendben helyettesito dispatch-et
% gyartani, hanem inf kimenetekkel jelezzuk, hogy ez a contract/nap
% nem kezelheto a megadott korlatok mellett.

    plan = struct();

    plan.is_feasible = false;
    plan.used_fallback = true;

    plan.P_contract = Pcontract;
    plan.P_contract_safety_factor = safety;
    plan.P_grid_limit = Plimit;

    plan.P_month_max_so_far = PmonthOld;
    plan.P_month_peak_candidate = inf;
    plan.P_overrun_increment_kW = inf;

    plan.trade_buy_mask = false(1, N);
    plan.trade_sell_mask = false(1, N);

    plan.P_grid_plan = inf(N, 1);
    plan.P_ch_plan   = zeros(N, 1);
    plan.P_dis_plan  = zeros(N, 1);
    plan.P_curt_plan = zeros(N, 1);

    plan.P_gload_plan  = inf(N, 1);
    plan.P_gbatt_plan  = zeros(N, 1);
    plan.P_pvload_plan = zeros(N, 1);
    plan.P_pvbatt_plan = zeros(N, 1);
    plan.P_bload_plan  = zeros(N, 1);
    plan.P_spill_plan  = zeros(N, 1);
    plan.P_over_plan   = inf(N, 1);
    plan.P_over_step_plan = inf(N, 1);
    plan.P_pv_ac_plan  = zeros(N, 1);

    plan.SoC_plan = SoC0 * ones(N, 1);

    plan.exitflag = exitflag;
    plan.objective_value = inf;

    plan.economics.energy_cost_market = inf;
    plan.economics.energy_cost_network = inf;
    plan.economics.energy_cost_total = inf;
    plan.economics.degradation_cost = inf;
    plan.economics.spill_cost = 0;
    plan.economics.overrun_increment_cost = inf;
    plan.economics.net_cost_operational = inf;
end