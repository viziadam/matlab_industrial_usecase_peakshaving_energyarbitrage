function plan = ems_day_ahead_planner_milp_contract_ac( ...
    P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, contract_state, maxSolverTime_s)
% EMS_DAY_AHEAD_PLANNER_MILP_CONTRACT_AC
%
% AC-csatolt PV+BESS MILP planner.
%
% Szigoru grid-limit logika:
%   PgL + PgB <= P_grid_limit
%
% Fontos:
%   - nincs Pover = 0 trukk;
%   - Pover nem dontesi valtozo;
%   - a hatar feletti reszt a megoldas utan szamitjuk diagnosztikai
%     celra: max(Pgrid - P_grid_limit, 0);
%   - ha a terheles/PV/BESS korlatok mellett a grid-limit nem tarthato,
%     az intlinprog infeasible megoldast ad, a plan pedig is_feasible = false.

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
            error('Hianyzo pars mezo az AC MILP-ben: pars.%s', requiredParsFields{k});
        end
    end

    requiredTariffFields = { ...
        'distribution_energy_rate_huf_per_kWh', ...
        'transmission_energy_rate_huf_per_kWh'};

    for k = 1:numel(requiredTariffFields)
        if ~isfield(tariff, requiredTariffFields{k})
            error('Hianyzo tariff mezo az AC MILP-ben: tariff.%s', requiredTariffFields{k});
        end
    end

    requiredContractFields = { ...
        'P_contract_kW', ...
        'P_month_max_so_far_kW'};

    for k = 1:numel(requiredContractFields)
        if ~isfield(contract_state, requiredContractFields{k})
            error('Hianyzo contract_state mezo az AC MILP-ben: contract_state.%s', ...
                requiredContractFields{k});
        end
    end

    if ~isfield(Prices, 'buy_huf')
        error('Hianyzo Prices.buy_huf az AC MILP-ben.');
    end

    Pload = P_load_f(:);
    Ppvdc = P_pv_dc_f(:);
    buy   = Prices.buy_huf(:);

    N = numel(Pload);

    if numel(Ppvdc) ~= N || numel(buy) ~= N
        error('AC MILP bemeneti vektorhossz elteres.');
    end

    if isfield(pars, 'SoC_initial')
        SoC0 = pars.SoC_initial;
    else
        SoC0 = 0.5;
    end

    socTol = 1e-4;

    if SoC0 < pars.SoC_min - socTol || SoC0 > pars.SoC_max + socTol
        error(['AC MILP indulo SoC kivul van a megengedett tartomanyon. ', ...
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

    % =====================================================================
    % Egyenlosegek
    % =====================================================================
    AeqLoad = zeros(N, nVars);
    beqLoad = Pload;

    for t = 1:N
        AeqLoad(t, iPgL(t))  = 1;
        AeqLoad(t, iPpvL(t)) = 1;
        AeqLoad(t, iPbL(t))  = 1;
    end

    AeqPv = zeros(N, nVars);
    beqPv = Ppv;

    for t = 1:N
        AeqPv(t, iPpvL(t))   = 1;
        AeqPv(t, iPpvB(t))   = 1;
        AeqPv(t, iPspill(t)) = 1;
    end

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

    % Szigoru grid-limit:
    %   PgL + PgB <= Plimit
    % Ez nem Pover-nullazas, hanem kozvetlen fizikai importkorlat.
    AGrid = zeros(N, nVars);
    bGrid = Plimit * ones(N, 1);

    for t = 1:N
        AGrid(t, iPgL(t)) = 1;
        AGrid(t, iPgB(t)) = 1;
    end

    A = [A; AGrid];
    b = [b; bGrid];

    % =====================================================================
    % Korlatok
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

    if isempty(x) || exitflag <= 0 || ~isfinite(fval)
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
    SoC    = x(iSoc);

    Pgrid = PgL + PgB;
    Pch   = PgB + PpvB;
    Pdis  = PbL;

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

    plan.economics.energy_cost_market = energyMarket;
    plan.economics.energy_cost_network = energyNetwork;
    plan.economics.energy_cost_total = energyMarket + energyNetwork;
    plan.economics.degradation_cost = degradationCost;
    plan.economics.spill_cost = 0;
    plan.economics.overrun_increment_cost = 0;
    plan.economics.net_cost_operational = ...
        energyMarket + energyNetwork + degradationCost;
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
