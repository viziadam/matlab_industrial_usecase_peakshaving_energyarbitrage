% function plan = ems_day_ahead_planner_milp_contract_ac( ...
%     P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, contract_state, maxSolverTime_s)
% % EMS_DAY_AHEAD_PLANNER_MILP_CONTRACT_AC
% %
% % AC-csatolt PV+BESS MILP planner.
% %
% % Topológiai feltételezés:
% %   - PV DC -> PV inverter -> AC busz
% %   - BESS külön AC oldali PCS-en keresztül csatlakozik
% %   - BESS bármikor tölthető hálózatról
% %   - PV nem megy közvetlenül DC oldalon a BESS-be
% %   - nincs P_curt döntési változó
% %
% % Jelölések:
% %   P_grid >= 0    hálózati import [kW]
% %   P_ch   >= 0    BESS AC oldali töltés [kW]
% %   P_dis  >= 0    BESS AC oldali kisütés [kW]
% %
% % AC busz egyenlőtlenség:
% %   P_grid + P_dis + P_pv_ac >= P_load + P_ch
% %
% % Ez azt jelenti, hogy ha PV többlet van, azt nem kell explicit curtailment
% % változóval lekönyvelni a MILP-ben. A fizikai topology később kezeli a
% % tényleges PV clippinget / felesleget.
% 
%     if nargin < 8
%         maxSolverTime_s = 15;
%     end
% 
%     requiredParsFields = { ...
%         'E_cap_nom', ...
%         'P_chg_max', ...
%         'P_dis_max', ...
%         'SoC_min', ...
%         'SoC_max', ...
%         'inv_eta', ...
%         'eta_cell', ...
%         'P_inv_limit_ac'};
% 
%     for i = 1:numel(requiredParsFields)
%         if ~isfield(pars, requiredParsFields{i})
%             error('Hiányzó pars mező az AC MILP-ben: pars.%s', requiredParsFields{i});
%         end
%     end
% 
%     requiredTariffFields = { ...
%         'distribution_energy_rate_huf_per_kWh', ...
%         'transmission_energy_rate_huf_per_kWh', ...
%         'penalty_rate_huf_per_kW_year', ...
%         'months_in_year'};
% 
%     for i = 1:numel(requiredTariffFields)
%         if ~isfield(tariff, requiredTariffFields{i})
%             error('Hiányzó tariff mező az AC MILP-ben: tariff.%s', requiredTariffFields{i});
%         end
%     end
% 
%     requiredContractFields = { ...
%         'P_contract_kW', ...
%         'P_month_max_so_far_kW'};
% 
%     for i = 1:numel(requiredContractFields)
%         if ~isfield(contract_state, requiredContractFields{i})
%             error('Hiányzó contract_state mező az AC MILP-ben: contract_state.%s', requiredContractFields{i});
%         end
%     end
% 
%     if ~isfield(Prices, 'buy_huf')
%         error('Hiányzó Prices.buy_huf az AC MILP-ben.');
%     end
% 
%     % ---------------------------------------------------------------------
%     % Eredeti felbontás elmentése
%     % ---------------------------------------------------------------------
%     P_load_f_orig  = P_load_f(:);
%     P_pv_dc_f_orig = P_pv_dc_f(:);
%     buy_p_orig     = Prices.buy_huf(:);
% 
%     N_orig = numel(P_load_f_orig);
% 
%     if numel(P_pv_dc_f_orig) ~= N_orig || numel(buy_p_orig) ~= N_orig
%         error('AC MILP bemeneti vektorhossz eltérés.');
%     end
% 
%     % ---------------------------------------------------------------------
%     % 1 órás aggregálás, ha lehet
%     % ---------------------------------------------------------------------
%     [P_load_f, P_pv_dc_f, buy_p_market, dt_milp, expand_factor] = ...
%         local_prepare_hourly_forecast(P_load_f_orig, P_pv_dc_f_orig, buy_p_orig, dt_h);
% 
%     N = numel(P_load_f);
% 
%     % ---------------------------------------------------------------------
%     % Paraméterek
%     % ---------------------------------------------------------------------
%     if isfield(pars, 'SoC_initial')
%         SoC_start = pars.SoC_initial;
%     else
%         SoC_start = 0.5;
%     end
% 
%     if SoC_start < pars.SoC_min - 1e-9 || SoC_start > pars.SoC_max + 1e-9
%         error('AC MILP induló SoC kívül van a megengedett tartományon.');
%     end
% 
%     P_ch_max  = pars.P_chg_max;
%     P_dis_max = pars.P_dis_max;
% 
%     P_contract = contract_state.P_contract_kW;
%     P_month_max_so_far = contract_state.P_month_max_so_far_kW;
%     if isfield(contract_state, 'P_contract_safety_factor')
%         P_contract_safety_factor = contract_state.P_contract_safety_factor;
%     else
%         P_contract_safety_factor = 0.90;
%     end
% 
%     % P_grid_cap = ...
%     %     P_contract * ...
%     %     P_contract_safety_factor;
%     P_grid_limit = P_contract_safety_factor * P_contract;
% 
%     if P_grid_cap <= 0 || ~isfinite(P_grid_cap)
%         error('Érvénytelen AC MILP P_grid_cap.');
%     end
% 
%     prev_overrun = max(0, P_month_max_so_far - P_contract);
% 
%     dist_fee = tariff.distribution_energy_rate_huf_per_kWh;
%     trans_fee = tariff.transmission_energy_rate_huf_per_kWh;
%     buy_p_total = buy_p_market + dist_fee + trans_fee;
% 
%     monthly_overrun_cost_per_kW = ...
%         tariff.penalty_rate_huf_per_kW_year / tariff.months_in_year;
% 
%     if isfield(tariff, 'within_contract_peak_weight_huf_per_kW_month')
%         within_contract_peak_weight = tariff.within_contract_peak_weight_huf_per_kW_month;
%     else
%         within_contract_peak_weight = 0;
%     end
% 
%     % PV AC oldali termelés AC-csatolt rendszerben
%     P_pv_ac = min(P_pv_dc_f * pars.inv_eta, pars.P_inv_limit_ac);
% 
%     % BESS AC oldali közelített hatásfokok
%     eta_ch_path  = pars.inv_eta * pars.eta_cell;
%     eta_dis_path = pars.eta_cell * pars.inv_eta;
% 
%     deg_model = build_article_simple_degradation_costs(pars);
%     cost_deg_ch  = deg_model.cost_ch_huf_per_kWh;
%     cost_deg_dis = deg_model.cost_dis_huf_per_kWh;
% 
%     % ---------------------------------------------------------------------
%     % Döntési változók
%     % ---------------------------------------------------------------------
%     n0 = 0;
% 
%     iGrid = n0 + (1:N); n0 = n0 + N;
%     iCh   = n0 + (1:N); n0 = n0 + N;
%     iDis  = n0 + (1:N); n0 = n0 + N;
%     iSoc  = n0 + (1:N); n0 = n0 + N;
%     iMode = n0 + (1:N); n0 = n0 + N;
% 
%     iMonthPeak = n0 + 1;
%     iOverInc   = n0 + 2;
% 
%     nVars = n0 + 2;
% 
%     % ---------------------------------------------------------------------
%     % Célfüggvény
%     % ---------------------------------------------------------------------
%     f = zeros(nVars, 1);
% 
%     f(iGrid) = buy_p_total(:) * dt_milp;
%     f(iCh)   = cost_deg_ch  * dt_milp;
%     f(iDis)  = cost_deg_dis * dt_milp;
% 
%     f(iMonthPeak) = within_contract_peak_weight;
%     f(iOverInc)   = monthly_overrun_cost_per_kW;
% 
%     % ---------------------------------------------------------------------
%     % SoC egyenlőségek
%     % ---------------------------------------------------------------------
%     Aeq_soc = zeros(N, nVars);
%     beq_soc = zeros(N, 1);
% 
%     Aeq_soc(1, iSoc(1)) = 1;
%     beq_soc(1) = SoC_start;
% 
%     alpha_ch = eta_ch_path * dt_milp / pars.E_cap_nom;
%     beta_dis = dt_milp / eta_dis_path / pars.E_cap_nom;
% 
%     for t = 2:N
%         Aeq_soc(t, iSoc(t))   =  1;
%         Aeq_soc(t, iSoc(t-1)) = -1;
%         Aeq_soc(t, iCh(t-1))  = -alpha_ch;
%         Aeq_soc(t, iDis(t-1)) =  beta_dis;
%     end
% 
%     Aeq = Aeq_soc;
%     beq = beq_soc;
% 
%     % ---------------------------------------------------------------------
%     % Egyenlőtlenségek
%     % ---------------------------------------------------------------------
%     A = [];
%     b = [];
% 
%     % AC busz mérleg:
%     %   P_grid + P_dis + P_pv_ac >= P_load + P_ch
%     % => -P_grid - P_dis + P_ch <= -(P_load - P_pv_ac)
%     A_bus = zeros(N, nVars);
%     b_bus = -(P_load_f - P_pv_ac);
% 
%     for t = 1:N
%         A_bus(t, iGrid(t)) = -1;
%         A_bus(t, iDis(t))  = -1;
%         A_bus(t, iCh(t))   =  1;
%     end
% 
%     A = [A; A_bus];
%     b = [b; b_bus];
% 
%     % Töltés / kisütés szétválasztás bináris móddal
%     A_bin = zeros(2*N, nVars);
%     b_bin = zeros(2*N, 1);
% 
%     for t = 1:N
%         % P_ch <= P_ch_max * mode
%         A_bin(t, iCh(t))   = 1;
%         A_bin(t, iMode(t)) = -P_ch_max;
% 
%         % P_dis <= P_dis_max * (1 - mode)
%         % P_dis + P_dis_max*mode <= P_dis_max
%         A_bin(N+t, iDis(t))  = 1;
%         A_bin(N+t, iMode(t)) = P_dis_max;
%         b_bin(N+t) = P_dis_max;
%     end
% 
%     A = [A; A_bin];
%     b = [b; b_bin];
% 
%     % Havi peak változó >= grid import
%     A_peak = zeros(N, nVars);
%     b_peak = zeros(N, 1);
% 
%     for t = 1:N
%         A_peak(t, iGrid(t)) = 1;
%         A_peak(t, iMonthPeak) = -1;
%     end
% 
%     A = [A; A_peak];
%     b = [b; b_peak];
% 
%     % Hard cap / safety factor a grid importra
%     A_cap = zeros(N, nVars);
%     b_cap = P_grid_cap * ones(N, 1);
% 
%     for t = 1:N
%         A_cap(t, iGrid(t)) = 1;
%     end
% 
%     A = [A; A_cap];
%     b = [b; b_cap];
% 
%     % Overrun increment:
%     % iOverInc >= iMonthPeak - P_contract - prev_overrun
%     % => iMonthPeak - iOverInc <= P_contract + prev_overrun
%     row_over = zeros(1, nVars);
%     row_over(iMonthPeak) = 1;
%     row_over(iOverInc)   = -1;
% 
%     A = [A; row_over];
%     b = [b; P_contract + prev_overrun];
% 
%     % ---------------------------------------------------------------------
%     % Korlátok
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
%     lb(iMonthPeak) = P_month_max_so_far;
%     lb(iOverInc) = 0;
% 
%     intcon = iMode;
% 
%     % ---------------------------------------------------------------------
%     % Solver
%     % ---------------------------------------------------------------------
%     options = optimoptions('intlinprog', ...
%         'Display', 'off', ...
%         'MaxTime', maxSolverTime_s, ...
%         'RelativeGapTolerance', 0.01, ...
%         'IntegerPreprocess', 'advanced', ...
%         'RootLPAlgorithm', 'dual-simplex');
% 
%     [x, fval, exitflag] = intlinprog( ...
%         f, intcon, A, b, Aeq, beq, lb, ub, options);
% 
%     % ---------------------------------------------------------------------
%     % Fallback
%     % ---------------------------------------------------------------------
%     if isempty(x) || exitflag <= 0
% 
%         fallback_grid = max(P_load_f - P_pv_ac, 0);
%         fallback_grid = min(fallback_grid, P_grid_cap);
% 
%         fallback_peak = max(P_month_max_so_far, max(fallback_grid));
%         fallback_over_inc = ...
%             max(0, max(0, fallback_peak - P_contract) - prev_overrun);
% 
%         plan_hourly = struct();
% 
%         plan_hourly.P_contract = P_contract;
%         plan_hourly.P_month_max_so_far = P_month_max_so_far;
%         plan_hourly.P_month_peak_candidate = fallback_peak;
%         plan_hourly.P_overrun_increment_kW = fallback_over_inc;
% 
%         plan_hourly.trade_buy_mask = false(1, N);
%         plan_hourly.trade_sell_mask = false(1, N);
% 
%         plan_hourly.P_grid_plan = fallback_grid(:);
%         plan_hourly.P_ch_plan = zeros(N, 1);
%         plan_hourly.P_dis_plan = zeros(N, 1);
% 
%         % Nem AC MILP döntési változó. Csak interfész-kompatibilis,
%         % becsült/implicit PV felesleg.
%         plan_hourly.P_curt_plan = max(P_pv_ac - P_load_f, 0);
% 
%         plan_hourly.SoC_plan = SoC_start * ones(N, 1);
% 
%         plan_hourly.exitflag = exitflag;
%         plan_hourly.objective_value = inf;
% 
%         plan_hourly.economics.energy_cost_market = ...
%             sum(buy_p_market(:) .* plan_hourly.P_grid_plan(:)) * dt_milp;
% 
%         plan_hourly.economics.energy_cost_network = ...
%             sum((dist_fee + trans_fee) .* plan_hourly.P_grid_plan(:)) * dt_milp;
% 
%         plan_hourly.economics.energy_cost_total = ...
%             plan_hourly.economics.energy_cost_market + ...
%             plan_hourly.economics.energy_cost_network;
% 
%         plan_hourly.economics.degradation_cost = 0;
%         plan_hourly.economics.overrun_increment_cost = ...
%             monthly_overrun_cost_per_kW * fallback_over_inc;
% 
%         plan_hourly.economics.net_cost_operational = inf;
% 
%         plan = local_expand_hourly_plan_to_original(plan_hourly, N_orig, expand_factor);
%         return;
%     end
% 
%     % ---------------------------------------------------------------------
%     % Megoldás kibontása
%     % ---------------------------------------------------------------------
%     P_grid = x(iGrid);
%     P_ch   = x(iCh);
%     P_dis  = x(iDis);
%     SoC    = x(iSoc);
% 
%     P_month_peak_candidate = x(iMonthPeak);
%     P_over_inc = x(iOverInc);
% 
%     implicit_pv_surplus = ...
%         max(P_pv_ac + P_grid + P_dis - P_load_f - P_ch, 0);
% 
%     plan_hourly = struct();
% 
%     plan_hourly.P_contract = P_contract;
%     plan_hourly.P_month_max_so_far = P_month_max_so_far;
%     plan_hourly.P_month_peak_candidate = P_month_peak_candidate;
%     plan_hourly.P_overrun_increment_kW = P_over_inc;
% 
%     plan_hourly.trade_buy_mask  = (P_ch  > 1e-3).';
%     plan_hourly.trade_sell_mask = (P_dis > 1e-3).';
% 
%     plan_hourly.P_grid_plan = P_grid;
%     plan_hourly.P_ch_plan   = P_ch;
%     plan_hourly.P_dis_plan  = P_dis;
% 
%     % Nem döntési változó, csak interface / diagnosztikai kompatibilitás.
%     plan_hourly.P_curt_plan = implicit_pv_surplus;
% 
%     plan_hourly.SoC_plan = SoC;
% 
%     plan_hourly.exitflag = exitflag;
%     plan_hourly.objective_value = fval;
% 
%     energy_cost_market = sum(buy_p_market(:) .* P_grid(:)) * dt_milp;
% 
%     energy_cost_network = ...
%         sum((dist_fee + trans_fee) .* P_grid(:)) * dt_milp;
% 
%     degradation_cost = ...
%         sum(cost_deg_ch  .* P_ch(:))  * dt_milp + ...
%         sum(cost_deg_dis .* P_dis(:)) * dt_milp;
% 
%     overrun_increment_cost = ...
%         monthly_overrun_cost_per_kW * P_over_inc;
% 
%     plan_hourly.economics.energy_cost_market = energy_cost_market;
%     plan_hourly.economics.energy_cost_network = energy_cost_network;
%     plan_hourly.economics.energy_cost_total = ...
%         energy_cost_market + energy_cost_network;
% 
%     plan_hourly.economics.degradation_cost = degradation_cost;
%     plan_hourly.economics.overrun_increment_cost = overrun_increment_cost;
% 
%     plan_hourly.economics.net_cost_operational = ...
%         energy_cost_market + ...
%         energy_cost_network + ...
%         degradation_cost + ...
%         overrun_increment_cost;
% 
%     plan = local_expand_hourly_plan_to_original(plan_hourly, N_orig, expand_factor);
% end
% 
% 
% function [P_load_h, P_pv_h, buy_h, dt_out, expand_factor] = ...
%     local_prepare_hourly_forecast(P_load, P_pv, buy_p, dt_in)
% 
%     P_load = P_load(:);
%     P_pv   = P_pv(:);
%     buy_p  = buy_p(:);
% 
%     if dt_in <= 0
%         error('local_prepare_hourly_forecast: dt_in must be positive');
%     end
% 
%     expand_factor_real = 1 / dt_in;
%     expand_factor_round = round(expand_factor_real);
% 
%     can_aggregate = ...
%         abs(expand_factor_real - expand_factor_round) < 1e-9 && ...
%         expand_factor_round >= 1;
% 
%     if ~can_aggregate || expand_factor_round == 1
%         P_load_h = P_load;
%         P_pv_h = P_pv;
%         buy_h = buy_p;
%         dt_out = dt_in;
%         expand_factor = 1;
%         return;
%     end
% 
%     N = numel(P_load);
%     nBlocks = floor(N / expand_factor_round);
% 
%     if nBlocks < 1
%         P_load_h = P_load;
%         P_pv_h = P_pv;
%         buy_h = buy_p;
%         dt_out = dt_in;
%         expand_factor = 1;
%         return;
%     end
% 
%     N_use = nBlocks * expand_factor_round;
% 
%     P_load_use = P_load(1:N_use);
%     P_pv_use = P_pv(1:N_use);
%     buy_use = buy_p(1:N_use);
% 
%     P_load_mat = reshape(P_load_use, expand_factor_round, nBlocks);
%     P_pv_mat = reshape(P_pv_use, expand_factor_round, nBlocks);
%     buy_mat = reshape(buy_use, expand_factor_round, nBlocks);
% 
%     P_load_h = mean(P_load_mat, 1).';
%     P_pv_h = mean(P_pv_mat, 1).';
%     buy_h = mean(buy_mat, 1).';
% 
%     dt_out = 1.0;
%     expand_factor = expand_factor_round;
% end
% 
% 
% function plan_out = local_expand_hourly_plan_to_original(plan_in, N_orig, expand_factor)
% 
%     if expand_factor <= 1
%         plan_out = plan_in;
%         return;
%     end
% 
%     plan_out = plan_in;
% 
%     plan_out.trade_buy_mask = ...
%         local_repeat_to_length(logical(plan_in.trade_buy_mask(:)), N_orig, expand_factor).';
% 
%     plan_out.trade_sell_mask = ...
%         local_repeat_to_length(logical(plan_in.trade_sell_mask(:)), N_orig, expand_factor).';
% 
%     plan_out.P_grid_plan = ...
%         local_repeat_to_length(plan_in.P_grid_plan(:), N_orig, expand_factor);
% 
%     plan_out.P_ch_plan = ...
%         local_repeat_to_length(plan_in.P_ch_plan(:), N_orig, expand_factor);
% 
%     plan_out.P_dis_plan = ...
%         local_repeat_to_length(plan_in.P_dis_plan(:), N_orig, expand_factor);
% 
%     plan_out.P_curt_plan = ...
%         local_repeat_to_length(plan_in.P_curt_plan(:), N_orig, expand_factor);
% 
%     plan_out.SoC_plan = ...
%         local_repeat_to_length(plan_in.SoC_plan(:), N_orig, expand_factor);
% end
% 
% 
% function y = local_repeat_to_length(x, N_target, rep_factor)
% 
%     x = x(:);
%     y = repelem(x, rep_factor, 1);
% 
%     if numel(y) >= N_target
%         y = y(1:N_target);
%         return;
%     end
% 
%     y = [y; repmat(y(end), N_target - numel(y), 1)];
% end
function plan = ems_day_ahead_planner_milp_contract_ac( ...
    P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, contract_state, maxSolverTime_s)
% EMS_DAY_AHEAD_PLANNER_MILP_CONTRACT_AC
%
% AC-csatolt PV+BESS MILP planner.
%
% Felbontott AC energiaáramok:
%   PgL     grid -> load
%   PgB     grid -> BESS
%   PpvL    PV   -> load
%   PpvB    PV   -> BESS
%   PbL     BESS -> load
%   Pspill  nem hasznosított PV
%   Pover   P_grid_limit feletti hálózati import
%
% Egyenletek:
%   PgL + PpvL + PbL = Pload
%   PpvL + PpvB + Pspill = Ppv_ac
%
% Soft grid-limit:
%   PgL + PgB - Pover <= P_grid_limit
%   Pover >= 0
%
% Vagyis a limit túlléphető, de minden időlépésben büntetett.

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
        'eta_cell', ...
        'P_inv_limit_ac'};

    for k = 1:numel(requiredParsFields)
        if ~isfield(pars, requiredParsFields{k})
            error('Hiányzó pars mező az AC MILP-ben: pars.%s', requiredParsFields{k});
        end
    end

    requiredTariffFields = { ...
        'distribution_energy_rate_huf_per_kWh', ...
        'transmission_energy_rate_huf_per_kWh', ...
        'penalty_rate_huf_per_kW_year', ...
        'months_in_year'};

    for k = 1:numel(requiredTariffFields)
        if ~isfield(tariff, requiredTariffFields{k})
            error('Hiányzó tariff mező az AC MILP-ben: tariff.%s', requiredTariffFields{k});
        end
    end

    requiredContractFields = { ...
        'P_contract_kW', ...
        'P_month_max_so_far_kW'};

    for k = 1:numel(requiredContractFields)
        if ~isfield(contract_state, requiredContractFields{k})
            error('Hiányzó contract_state mező az AC MILP-ben: contract_state.%s', requiredContractFields{k});
        end
    end

    if ~isfield(Prices, 'buy_huf')
        error('Hiányzó Prices.buy_huf az AC MILP-ben.');
    end

    Pload = P_load_f(:);
    Ppvdc = P_pv_dc_f(:);
    buy   = Prices.buy_huf(:);

    N = numel(Pload);

    if numel(Ppvdc) ~= N || numel(buy) ~= N
        error('AC MILP bemeneti vektorhossz eltérés.');
    end

    if isfield(pars, 'SoC_initial')
        SoC0 = pars.SoC_initial;
    else
        SoC0 = 0.5;
    end

    if SoC0 < pars.SoC_min || SoC0 > pars.SoC_max
        error('AC MILP induló SoC kívül van a megengedett tartományon.');
    end

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

    Ppv = min(Ppvdc * pars.inv_eta, pars.P_inv_limit_ac);

    PchMax  = pars.P_chg_max / pars.inv_eta;
    PdisMax = pars.P_dis_max * pars.inv_eta;

    etaCh  = pars.inv_eta * pars.eta_cell;
    etaDis = pars.inv_eta * pars.eta_cell;

    deg = build_article_simple_degradation_costs(pars);
    cCh  = deg.cost_ch_huf_per_kWh;
    cDis = deg.cost_dis_huf_per_kWh;

    buyTotal = buy ...
        + tariff.distribution_energy_rate_huf_per_kWh ...
        + tariff.transmission_energy_rate_huf_per_kWh;

    % Időlépésre fajlagosított túllépési büntetés.
    % Egység:
    %   penalty_rate_huf_per_kW_year [HUF/kW/year]
    %   dt_h / (365*24)              [year]
    %   => HUF/kW per timestep
    cOver = tariff.penalty_rate_huf_per_kW_year * dt_h / (365 * 24);

    % =====================================================================
    % Döntési változók
    % =====================================================================
    n = 0;

    iPgL    = n + (1:N); n = n + N;
    iPgB    = n + (1:N); n = n + N;
    iPpvL   = n + (1:N); n = n + N;
    iPpvB   = n + (1:N); n = n + N;
    iPbL    = n + (1:N); n = n + N;
    iPspill = n + (1:N); n = n + N;
    iPover  = n + (1:N); n = n + N;
    iSoc    = n + (1:N); n = n + N;
    iMode   = n + (1:N); n = n + N;

    nVars = n;

    % =====================================================================
    % Célfüggvény
    % =====================================================================
    f = zeros(nVars, 1);

    f(iPgL)   = buyTotal * dt_h;
    f(iPgB)   = buyTotal * dt_h + cCh * dt_h;
    f(iPpvB)  = cCh * dt_h;
    f(iPbL)   = cDis * dt_h;
    f(iPover) = cOver;

    % PpvL és Pspill költsége 0.

    % =====================================================================
    % Egyenlőségek
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
    %   SoC(t) = SoC(t-1) + etaCh*(PgB+PpvB)*dt/E - PbL*dt/(etaDis*E)
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
    % Egyenlőtlenségek
    % =====================================================================
    A = [];
    b = [];

    % Töltés / kisütés kizárás:
    %   PgB + PpvB <= PchMax * mode
    %   PbL <= PdisMax * (1 - mode)
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

    % =====================================================================
    % Korlátok
    % =====================================================================
    lb = zeros(nVars, 1);
    ub = inf(nVars, 1);

    lb(iSoc) = pars.SoC_min;
    ub(iSoc) = pars.SoC_max;

    lb(iMode) = 0;
    ub(iMode) = 1;

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
        plan = local_infeasible_ac_plan( ...
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
    Pover  = x(iPover);
    SoC    = x(iSoc);

    Pgrid = PgL + PgB;
    Pch   = PgB + PpvB;
    Pdis  = PbL;

    Ppeak = max(PmonthOld, max(Pgrid));

    plan = struct();

    plan.is_feasible = true;
    plan.used_fallback = false;

    plan.P_contract = Pcontract;
    plan.P_contract_safety_factor = safety;
    plan.P_grid_limit = Plimit;

    plan.P_month_max_so_far = PmonthOld;
    plan.P_month_peak_candidate = Ppeak;

    % Most már nem havi peak-hez viszonyított inkrementum,
    % hanem a P_grid_limit feletti legnagyobb időlépéses túllépés.
    plan.P_overrun_increment_kW = max(Pover);

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

    overrunCost = sum(Pover(:)) * cOver;

    plan.economics.energy_cost_market = energyMarket;
    plan.economics.energy_cost_network = energyNetwork;
    plan.economics.energy_cost_total = energyMarket + energyNetwork;
    plan.economics.degradation_cost = degradationCost;
    plan.economics.spill_cost = 0;
    plan.economics.overrun_increment_cost = overrunCost;
    plan.economics.net_cost_operational = ...
        energyMarket + energyNetwork + degradationCost + overrunCost;
end


function plan = local_infeasible_ac_plan( ...
    N, Pcontract, safety, Plimit, PmonthOld, SoC0, exitflag)

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