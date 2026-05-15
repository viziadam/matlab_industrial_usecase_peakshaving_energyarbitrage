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
% Topológiai feltételezés:
%   - PV DC -> PV inverter -> AC busz
%   - BESS külön AC oldali PCS-en keresztül csatlakozik
%   - BESS bármikor tölthető hálózatról
%   - PV nem megy közvetlenül DC oldalon a BESS-be
%   - nincs P_curt döntési változó
%
% Jelölések:
%   P_grid >= 0    hálózati import [kW]
%   P_ch   >= 0    BESS AC oldali töltés [kW]
%   P_dis  >= 0    BESS AC oldali kisütés [kW]
%
% AC busz energiamérleg:
%   Felbontott energiaáramokkal, egyenletekkel:
%
%   P_gload + P_pvload + P_bload = P_load
%   P_pvload + P_pvbatt + Pspill = P_pv_ac
%
%   ahol:
%       P_gload   = grid -> load
%       P_gbatt   = grid -> BESS
%       P_pvload  = PV -> load
%       P_pvbatt  = PV -> BESS
%       P_bload   = BESS -> load
%       Pspill    = nem hasznosított PV teljesítmény
%
% Fontos:
%   - nincs PV referencia;
%   - a MILP maga dönti el az energiaáramokat;
%   - Pspill költsége 0 HUF/kWh;
%   - a grid-limit az aktuális contractból származik.

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

    for i = 1:numel(requiredParsFields)
        if ~isfield(pars, requiredParsFields{i})
            error('Hiányzó pars mező az AC MILP-ben: pars.%s', requiredParsFields{i});
        end
    end

    requiredTariffFields = { ...
        'distribution_energy_rate_huf_per_kWh', ...
        'transmission_energy_rate_huf_per_kWh', ...
        'penalty_rate_huf_per_kW_year', ...
        'months_in_year'};

    for i = 1:numel(requiredTariffFields)
        if ~isfield(tariff, requiredTariffFields{i})
            error('Hiányzó tariff mező az AC MILP-ben: tariff.%s', requiredTariffFields{i});
        end
    end

    requiredContractFields = { ...
        'P_contract_kW', ...
        'P_month_max_so_far_kW'};

    for i = 1:numel(requiredContractFields)
        if ~isfield(contract_state, requiredContractFields{i})
            error('Hiányzó contract_state mező az AC MILP-ben: contract_state.%s', requiredContractFields{i});
        end
    end

    if ~isfield(Prices, 'buy_huf')
        error('Hiányzó Prices.buy_huf az AC MILP-ben.');
    end

    % ---------------------------------------------------------------------
    % Eredeti felbontás elmentése
    % ---------------------------------------------------------------------
    P_load_f_orig  = P_load_f(:);
    P_pv_dc_f_orig = P_pv_dc_f(:);
    buy_p_orig     = Prices.buy_huf(:);

    N_orig = numel(P_load_f_orig);

    if numel(P_pv_dc_f_orig) ~= N_orig || numel(buy_p_orig) ~= N_orig
        error('AC MILP bemeneti vektorhossz eltérés.');
    end

    % ---------------------------------------------------------------------
    % 1 órás aggregálás, ha lehet
    % ---------------------------------------------------------------------
    [P_load_f, P_pv_dc_f, buy_p_market, dt_milp, expand_factor] = ...
        local_prepare_hourly_forecast(P_load_f_orig, P_pv_dc_f_orig, buy_p_orig, dt_h);

    N = numel(P_load_f);

    % ---------------------------------------------------------------------
    % Paraméterek
    % ---------------------------------------------------------------------
    if isfield(pars, 'SoC_initial')
        SoC_start = pars.SoC_initial;
    else
        SoC_start = 0.5;
    end

    if SoC_start < pars.SoC_min - 1e-9 || SoC_start > pars.SoC_max + 1e-9
        error('AC MILP induló SoC kívül van a megengedett tartományon.');
    end

    P_ch_max  = pars.P_chg_max;
    P_dis_max = pars.P_dis_max;

    P_contract = contract_state.P_contract_kW;
    P_month_max_so_far = contract_state.P_month_max_so_far_kW;

    if isfield(contract_state, 'P_contract_safety_factor')
        P_contract_safety_factor = contract_state.P_contract_safety_factor;
    else
        P_contract_safety_factor = 0.90;
    end

    if P_contract_safety_factor <= 0 || P_contract_safety_factor > 1
        error('P_contract_safety_factor must be in the interval (0, 1].');
    end

    P_grid_limit = P_contract_safety_factor * P_contract;

    if P_grid_limit <= 0 || ~isfinite(P_grid_limit)
        error('Érvénytelen AC MILP P_grid_limit.');
    end

    prev_overrun = max(0, P_month_max_so_far - P_contract);

    dist_fee = tariff.distribution_energy_rate_huf_per_kWh;
    trans_fee = tariff.transmission_energy_rate_huf_per_kWh;
    buy_p_total = buy_p_market + dist_fee + trans_fee;

    monthly_overrun_cost_per_kW = ...
        tariff.penalty_rate_huf_per_kW_year / tariff.months_in_year;

    if isfield(tariff, 'within_contract_peak_weight_huf_per_kW_month')
        within_contract_peak_weight = tariff.within_contract_peak_weight_huf_per_kW_month;
    else
        within_contract_peak_weight = 0;
    end

    % PV AC oldali termelés AC-csatolt rendszerben
    P_pv_ac = min(P_pv_dc_f * pars.inv_eta, pars.P_inv_limit_ac);

    % BESS AC oldali közelített hatásfokok
    eta_ch_path  = pars.inv_eta * pars.eta_cell;
    eta_dis_path = pars.eta_cell * pars.inv_eta;

    deg_model = build_article_simple_degradation_costs(pars);
    cost_deg_ch  = deg_model.cost_ch_huf_per_kWh;
    cost_deg_dis = deg_model.cost_dis_huf_per_kWh;

    % Pspill költsége szándékosan 0.
    % Nem akarunk PV-referenciát vagy PV-kényszerhasznosítást bevezetni.
    spill_cost_huf_per_kWh = 0.0;

    % ---------------------------------------------------------------------
    % Döntési változók
    % ---------------------------------------------------------------------
    n0 = 0;

    iGload  = n0 + (1:N); n0 = n0 + N;   % grid -> load
    iGbatt  = n0 + (1:N); n0 = n0 + N;   % grid -> BESS
    iPVload = n0 + (1:N); n0 = n0 + N;   % PV -> load
    iPVbatt = n0 + (1:N); n0 = n0 + N;   % PV -> BESS
    iBload  = n0 + (1:N); n0 = n0 + N;   % BESS -> load
    iSpill  = n0 + (1:N); n0 = n0 + N;   % unused PV
    iSoc    = n0 + (1:N); n0 = n0 + N;
    iMode   = n0 + (1:N); n0 = n0 + N;

    iMonthPeak = n0 + 1;
    iOverInc   = n0 + 2;

    nVars = n0 + 2;

    % ---------------------------------------------------------------------
    % Célfüggvény
    % ---------------------------------------------------------------------
    f = zeros(nVars, 1);

    % Grid import költség:
    %   grid -> load
    %   grid -> BESS
    f(iGload) = buy_p_total(:) * dt_milp;
    f(iGbatt) = buy_p_total(:) * dt_milp + cost_deg_ch * dt_milp;

    % PV -> load költsége 0.
    f(iPVload) = 0;

    % PV -> BESS csak degradációs költséget kap.
    f(iPVbatt) = cost_deg_ch * dt_milp;

    % BESS -> load kisütési degradációs költség.
    f(iBload) = cost_deg_dis * dt_milp;

    % Pspill költsége 0.
    f(iSpill) = spill_cost_huf_per_kWh * dt_milp;

    % Kompatibilitási / opcionális peak tagok.
    f(iMonthPeak) = within_contract_peak_weight;
    f(iOverInc)   = monthly_overrun_cost_per_kW;

    % ---------------------------------------------------------------------
    % Egyenlőségi feltételek
    % ---------------------------------------------------------------------

    % ---------------------------------------------------------------------
    % 1) Load ellátás:
    %    P_gload + P_pvload + P_bload = P_load
    % ---------------------------------------------------------------------
    Aeq_load = zeros(N, nVars);
    beq_load = P_load_f;

    for t = 1:N
        Aeq_load(t, iGload(t))  = 1;
        Aeq_load(t, iPVload(t)) = 1;
        Aeq_load(t, iBload(t))  = 1;
    end

    % ---------------------------------------------------------------------
    % 2) PV felosztás:
    %    P_pvload + P_pvbatt + Pspill = P_pv_ac
    % ---------------------------------------------------------------------
    Aeq_pv = zeros(N, nVars);
    beq_pv = P_pv_ac;

    for t = 1:N
        Aeq_pv(t, iPVload(t)) = 1;
        Aeq_pv(t, iPVbatt(t)) = 1;
        Aeq_pv(t, iSpill(t))  = 1;
    end

    % ---------------------------------------------------------------------
    % 3) SoC dinamika
    %
    %    SoC(t) = SoC(t-1)
    %           + eta_ch_path * (P_gbatt + P_pvbatt) * dt / E
    %           - P_bload * dt / eta_dis_path / E
    % ---------------------------------------------------------------------
    Aeq_soc = zeros(N, nVars);
    beq_soc = zeros(N, 1);

    Aeq_soc(1, iSoc(1)) = 1;
    beq_soc(1) = SoC_start;

    alpha_ch = eta_ch_path * dt_milp / pars.E_cap_nom;
    beta_dis = dt_milp / eta_dis_path / pars.E_cap_nom;

    for t = 2:N
        Aeq_soc(t, iSoc(t))       =  1;
        Aeq_soc(t, iSoc(t-1))     = -1;
        Aeq_soc(t, iGbatt(t-1))   = -alpha_ch;
        Aeq_soc(t, iPVbatt(t-1))  = -alpha_ch;
        Aeq_soc(t, iBload(t-1))   =  beta_dis;
    end

    Aeq = [Aeq_load; Aeq_pv; Aeq_soc];
    beq = [beq_load; beq_pv; beq_soc];

    % ---------------------------------------------------------------------
    % Egyenlőtlenségi feltételek
    % ---------------------------------------------------------------------
    A = [];
    b = [];

    % ---------------------------------------------------------------------
    % 1) Töltés / kisütés szétválasztás bináris móddal
    %
    % mode = 1 -> töltés engedélyezett, kisütés tiltott
    % mode = 0 -> kisütés engedélyezett, töltés tiltott
    %
    % P_gbatt + P_pvbatt <= P_ch_max * mode
    % P_bload            <= P_dis_max * (1 - mode)
    % ---------------------------------------------------------------------
    A_bin = zeros(2*N, nVars);
    b_bin = zeros(2*N, 1);

    for t = 1:N
        A_bin(t, iGbatt(t))  = 1;
        A_bin(t, iPVbatt(t)) = 1;
        A_bin(t, iMode(t))   = -P_ch_max;

        A_bin(N+t, iBload(t)) = 1;
        A_bin(N+t, iMode(t))  = P_dis_max;
        b_bin(N+t) = P_dis_max;
    end

    A = [A; A_bin];
    b = [b; b_bin];

    % ---------------------------------------------------------------------
    % 2) Havi peak változó >= teljes hálózati import
    %
    % P_month_peak_candidate >= P_gload + P_gbatt
    % ---------------------------------------------------------------------
    A_peak = zeros(N, nVars);
    b_peak = zeros(N, 1);

    for t = 1:N
        A_peak(t, iGload(t)) = 1;
        A_peak(t, iGbatt(t)) = 1;
        A_peak(t, iMonthPeak) = -1;
    end

    A = [A; A_peak];
    b = [b; b_peak];

    % ---------------------------------------------------------------------
    % 3) Contract-alapú hálózati import korlát
    %
    % P_gload + P_gbatt <= P_contract_safety_factor * P_contract
    % ---------------------------------------------------------------------
    A_grid_limit = zeros(N, nVars);
    b_grid_limit = P_grid_limit * ones(N, 1);

    for t = 1:N
        A_grid_limit(t, iGload(t)) = 1;
        A_grid_limit(t, iGbatt(t)) = 1;
    end

    A = [A; A_grid_limit];
    b = [b; b_grid_limit];

    % ---------------------------------------------------------------------
    % 4) Overrun increment kompatibilitási feltétel
    %
    % iOverInc >= iMonthPeak - P_contract - prev_overrun
    % => iMonthPeak - iOverInc <= P_contract + prev_overrun
    %
    % Hard contract limit mellett normál esetben nem ez vezérli az optimumot,
    % de a mező kompatibilitási okból bent marad.
    % ---------------------------------------------------------------------
    row_over = zeros(1, nVars);
    row_over(iMonthPeak) = 1;
    row_over(iOverInc)   = -1;

    A = [A; row_over];
    b = [b; P_contract + prev_overrun];

    % ---------------------------------------------------------------------
    % Korlátok
    % ---------------------------------------------------------------------
    lb = zeros(nVars, 1);
    ub = inf(nVars, 1);

    lb(iSoc) = pars.SoC_min;
    ub(iSoc) = pars.SoC_max;

    lb(iMode) = 0;
    ub(iMode) = 1;

    lb(iMonthPeak) = P_month_max_so_far;
    lb(iOverInc) = 0;

    intcon = iMode;

    % ---------------------------------------------------------------------
    % Solver
    % ---------------------------------------------------------------------
    options = optimoptions('intlinprog', ...
        'Display', 'off', ...
        'MaxTime', maxSolverTime_s, ...
        'RelativeGapTolerance', 0.01, ...
        'IntegerPreprocess', 'advanced', ...
        'RootLPAlgorithm', 'dual-simplex');

    [x, fval, exitflag] = intlinprog( ...
        f, intcon, A, b, Aeq, beq, lb, ub, options);

    % ---------------------------------------------------------------------
    % Fallback
    % ---------------------------------------------------------------------
    if isempty(x) || exitflag <= 0

        P_pvload_fb = min(P_pv_ac, P_load_f);
        P_gload_fb  = max(P_load_f - P_pvload_fb, 0);

        P_gbatt_fb  = zeros(N, 1);
        P_pvbatt_fb = zeros(N, 1);
        P_bload_fb  = zeros(N, 1);
        Pspill_fb   = max(P_pv_ac - P_pvload_fb, 0);

        P_grid_fb = P_gload_fb + P_gbatt_fb;
        P_ch_fb   = P_gbatt_fb + P_pvbatt_fb;
        P_dis_fb  = P_bload_fb;

        fallback_peak = max(P_month_max_so_far, max(P_grid_fb));
        fallback_over_inc = ...
            max(0, max(0, fallback_peak - P_contract) - prev_overrun);

        plan_hourly = struct();

        plan_hourly.P_contract = P_contract;
        plan_hourly.P_contract_safety_factor = P_contract_safety_factor;
        plan_hourly.P_grid_limit = P_grid_limit;

        plan_hourly.P_month_max_so_far = P_month_max_so_far;
        plan_hourly.P_month_peak_candidate = fallback_peak;
        plan_hourly.P_overrun_increment_kW = fallback_over_inc;

        plan_hourly.trade_buy_mask = false(1, N);
        plan_hourly.trade_sell_mask = false(1, N);

        plan_hourly.P_grid_plan = P_grid_fb(:);
        plan_hourly.P_ch_plan = P_ch_fb(:);
        plan_hourly.P_dis_plan = P_dis_fb(:);
        plan_hourly.P_curt_plan = Pspill_fb(:);
        plan_hourly.P_spill_plan = Pspill_fb(:);

        plan_hourly.P_gload_plan = P_gload_fb(:);
        plan_hourly.P_gbatt_plan = P_gbatt_fb(:);
        plan_hourly.P_pvload_plan = P_pvload_fb(:);
        plan_hourly.P_pvbatt_plan = P_pvbatt_fb(:);
        plan_hourly.P_bload_plan = P_bload_fb(:);
        plan_hourly.P_pv_ac_plan = P_pv_ac(:);

        plan_hourly.SoC_plan = SoC_start * ones(N, 1);

        plan_hourly.exitflag = exitflag;
        plan_hourly.objective_value = inf;

        plan_hourly.economics.energy_cost_market = ...
            sum(buy_p_market(:) .* plan_hourly.P_grid_plan(:)) * dt_milp;

        plan_hourly.economics.energy_cost_network = ...
            sum((dist_fee + trans_fee) .* plan_hourly.P_grid_plan(:)) * dt_milp;

        plan_hourly.economics.energy_cost_total = ...
            plan_hourly.economics.energy_cost_market + ...
            plan_hourly.economics.energy_cost_network;

        plan_hourly.economics.degradation_cost = 0;
        plan_hourly.economics.spill_cost = 0;

        plan_hourly.economics.overrun_increment_cost = ...
            monthly_overrun_cost_per_kW * fallback_over_inc;

        plan_hourly.economics.net_cost_operational = inf;

        plan = local_expand_hourly_plan_to_original(plan_hourly, N_orig, expand_factor);
        return;
    end

    % ---------------------------------------------------------------------
    % Megoldás kibontása
    % ---------------------------------------------------------------------
    P_gload  = x(iGload);
    P_gbatt  = x(iGbatt);
    P_pvload = x(iPVload);
    P_pvbatt = x(iPVbatt);
    P_bload  = x(iBload);
    Pspill   = x(iSpill);
    SoC      = x(iSoc);

    P_grid = P_gload + P_gbatt;
    P_ch   = P_gbatt + P_pvbatt;
    P_dis  = P_bload;

    P_month_peak_candidate = x(iMonthPeak);
    P_over_inc = x(iOverInc);

    plan_hourly = struct();

    plan_hourly.P_contract = P_contract;
    plan_hourly.P_contract_safety_factor = P_contract_safety_factor;
    plan_hourly.P_grid_limit = P_grid_limit;

    plan_hourly.P_month_max_so_far = P_month_max_so_far;
    plan_hourly.P_month_peak_candidate = P_month_peak_candidate;
    plan_hourly.P_overrun_increment_kW = P_over_inc;

    plan_hourly.trade_buy_mask  = (P_ch  > 1e-3).';
    plan_hourly.trade_sell_mask = (P_dis > 1e-3).';

    plan_hourly.P_grid_plan = P_grid(:);
    plan_hourly.P_ch_plan   = P_ch(:);
    plan_hourly.P_dis_plan  = P_dis(:);

    % Interfész-kompatibilitás:
    % AC esetben ez nem DC curtailment, hanem Pspill.
    plan_hourly.P_curt_plan = Pspill(:);
    plan_hourly.P_spill_plan = Pspill(:);

    % Részletes AC energiaáramok
    plan_hourly.P_gload_plan  = P_gload(:);
    plan_hourly.P_gbatt_plan  = P_gbatt(:);
    plan_hourly.P_pvload_plan = P_pvload(:);
    plan_hourly.P_pvbatt_plan = P_pvbatt(:);
    plan_hourly.P_bload_plan  = P_bload(:);
    plan_hourly.P_pv_ac_plan  = P_pv_ac(:);

    plan_hourly.SoC_plan = SoC(:);

    plan_hourly.exitflag = exitflag;
    plan_hourly.objective_value = fval;

    energy_cost_market = ...
        sum(buy_p_market(:) .* P_grid(:)) * dt_milp;

    energy_cost_network = ...
        sum((dist_fee + trans_fee) .* P_grid(:)) * dt_milp;

    degradation_cost = ...
        sum(cost_deg_ch  .* P_ch(:))  * dt_milp + ...
        sum(cost_deg_dis .* P_dis(:)) * dt_milp;

    spill_cost = ...
        sum(spill_cost_huf_per_kWh .* Pspill(:)) * dt_milp;

    overrun_increment_cost = ...
        monthly_overrun_cost_per_kW * P_over_inc;

    plan_hourly.economics.energy_cost_market = energy_cost_market;
    plan_hourly.economics.energy_cost_network = energy_cost_network;
    plan_hourly.economics.energy_cost_total = ...
        energy_cost_market + energy_cost_network;

    plan_hourly.economics.degradation_cost = degradation_cost;
    plan_hourly.economics.spill_cost = spill_cost;

    plan_hourly.economics.overrun_increment_cost = overrun_increment_cost;

    plan_hourly.economics.net_cost_operational = ...
        energy_cost_market + ...
        energy_cost_network + ...
        degradation_cost + ...
        spill_cost + ...
        overrun_increment_cost;

    plan = local_expand_hourly_plan_to_original(plan_hourly, N_orig, expand_factor);
end


function [P_load_h, P_pv_h, buy_h, dt_out, expand_factor] = ...
    local_prepare_hourly_forecast(P_load, P_pv, buy_p, dt_in)

    P_load = P_load(:);
    P_pv   = P_pv(:);
    buy_p  = buy_p(:);

    if dt_in <= 0
        error('local_prepare_hourly_forecast: dt_in must be positive');
    end

    expand_factor_real = 1 / dt_in;
    expand_factor_round = round(expand_factor_real);

    can_aggregate = ...
        abs(expand_factor_real - expand_factor_round) < 1e-9 && ...
        expand_factor_round >= 1;

    if ~can_aggregate || expand_factor_round == 1
        P_load_h = P_load;
        P_pv_h = P_pv;
        buy_h = buy_p;
        dt_out = dt_in;
        expand_factor = 1;
        return;
    end

    N = numel(P_load);
    nBlocks = floor(N / expand_factor_round);

    if nBlocks < 1
        P_load_h = P_load;
        P_pv_h = P_pv;
        buy_h = buy_p;
        dt_out = dt_in;
        expand_factor = 1;
        return;
    end

    N_use = nBlocks * expand_factor_round;

    P_load_use = P_load(1:N_use);
    P_pv_use = P_pv(1:N_use);
    buy_use = buy_p(1:N_use);

    P_load_mat = reshape(P_load_use, expand_factor_round, nBlocks);
    P_pv_mat = reshape(P_pv_use, expand_factor_round, nBlocks);
    buy_mat = reshape(buy_use, expand_factor_round, nBlocks);

    P_load_h = mean(P_load_mat, 1).';
    P_pv_h = mean(Pv_mat_placeholder(P_pv_mat), 1).';
    buy_h = mean(buy_mat, 1).';

    dt_out = 1.0;
    expand_factor = expand_factor_round;
end


function P_pv_mat_out = Pv_mat_placeholder(P_pv_mat)
% Csak azért van külön segéd, hogy véletlenül se maradjon névütközés.
% A kimenet változatlan.
    P_pv_mat_out = P_pv_mat;
end


function plan_out = local_expand_hourly_plan_to_original(plan_in, N_orig, expand_factor)

    if expand_factor <= 1
        plan_out = plan_in;
        return;
    end

    plan_out = plan_in;

    plan_out.trade_buy_mask = ...
        local_repeat_to_length(logical(plan_in.trade_buy_mask(:)), N_orig, expand_factor).';

    plan_out.trade_sell_mask = ...
        local_repeat_to_length(logical(plan_in.trade_sell_mask(:)), N_orig, expand_factor).';

    plan_out.P_grid_plan = ...
        local_repeat_to_length(plan_in.P_grid_plan(:), N_orig, expand_factor);

    plan_out.P_ch_plan = ...
        local_repeat_to_length(plan_in.P_ch_plan(:), N_orig, expand_factor);

    plan_out.P_dis_plan = ...
        local_repeat_to_length(plan_in.P_dis_plan(:), N_orig, expand_factor);

    plan_out.P_curt_plan = ...
        local_repeat_to_length(plan_in.P_curt_plan(:), N_orig, expand_factor);

    plan_out.P_spill_plan = ...
        local_repeat_to_length(plan_in.P_spill_plan(:), N_orig, expand_factor);

    plan_out.SoC_plan = ...
        local_repeat_to_length(plan_in.SoC_plan(:), N_orig, expand_factor);

    plan_out.P_gload_plan = ...
        local_repeat_to_length(plan_in.P_gload_plan(:), N_orig, expand_factor);

    plan_out.P_gbatt_plan = ...
        local_repeat_to_length(plan_in.P_gbatt_plan(:), N_orig, expand_factor);

    plan_out.P_pvload_plan = ...
        local_repeat_to_length(plan_in.P_pvload_plan(:), N_orig, expand_factor);

    plan_out.P_pvbatt_plan = ...
        local_repeat_to_length(plan_in.P_pvbatt_plan(:), N_orig, expand_factor);

    plan_out.P_bload_plan = ...
        local_repeat_to_length(plan_in.P_bload_plan(:), N_orig, expand_factor);

    plan_out.P_pv_ac_plan = ...
        local_repeat_to_length(plan_in.P_pv_ac_plan(:), N_orig, expand_factor);
end


function y = local_repeat_to_length(x, N_target, rep_factor)

    x = x(:);
    y = repelem(x, rep_factor, 1);

    if numel(y) >= N_target
        y = y(1:N_target);
        return;
    end

    y = [y; repmat(y(end), N_target - numel(y), 1)];
end