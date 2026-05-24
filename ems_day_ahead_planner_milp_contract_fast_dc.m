function plan = ems_day_ahead_planner_milp_contract_fast_dc( ...
    P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, contract_state, maxSolverTime_s)

    if nargin < 8
        maxSolverTime_s = 15;
    end

    simultaneousTol_kW = 1e-5;

    Pload = P_load_f(:);
    Ppvdc = max(P_pv_dc_f(:), 0);
    buy = Prices.buy_huf(:);

    N = numel(Pload);

    if numel(Ppvdc) ~= N || numel(buy) ~= N
        error('Input length mismatch in fast DC planner.');
    end

    SoC0 = local_get_field(pars, 'SoC_initial', 0.5);
    SoC0 = min(max(SoC0, pars.SoC_min), pars.SoC_max);

    Pcontract = contract_state.P_contract_kW;
    PmonthOld = contract_state.P_month_max_so_far_kW;

    safety = local_get_field(contract_state, 'P_contract_safety_factor', 0.90);
    Plimit = safety * Pcontract;

    PchMax = pars.P_chg_max;
    PdisMax = pars.P_dis_max;

    etaChGrid = pars.inv_eta * pars.eta_c * pars.eta_cell;
    etaDisAc = pars.eta_cell * pars.eta_d * pars.inv_eta;
    etaChPv = pars.eta_c * pars.eta_cell;

    deg = build_article_simple_degradation_costs(pars);
    cCh = deg.cost_ch_huf_per_kWh;
    cDis = deg.cost_dis_huf_per_kWh;

    buyTotal = buy ...
        + tariff.distribution_energy_rate_huf_per_kWh ...
        + tariff.transmission_energy_rate_huf_per_kWh;

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

    f = zeros(nVars, 1);

    f(iPgL) = buyTotal * dt_h;
    f(iPgB) = buyTotal * dt_h + cCh * pars.inv_eta * dt_h;
    f(iPpvB) = cCh * dt_h;
    f(iPbL) = cDis * (1 / pars.inv_eta) * dt_h;

    AeqLoad = sparse(N, nVars);
    beqLoad = Pload;

    for t = 1:N
        AeqLoad(t, iPgL(t)) = 1;
        AeqLoad(t, iPpvL(t)) = 1;
        AeqLoad(t, iPbL(t)) = 1;
    end

    AeqPv = sparse(N, nVars);
    beqPv = Ppvdc;

    for t = 1:N
        AeqPv(t, iPpvL(t)) = 1 / pars.inv_eta;
        AeqPv(t, iPpvB(t)) = 1;
        AeqPv(t, iPspill(t)) = 1;
    end

    AeqSoc = sparse(N, nVars);
    beqSoc = zeros(N, 1);

    aChGrid = etaChGrid * dt_h / pars.E_cap_nom;
    aChPv = etaChPv * dt_h / pars.E_cap_nom;
    aDis = dt_h / etaDisAc / pars.E_cap_nom;

    AeqSoc(1, iSoc(1)) = 1;
    beqSoc(1) = SoC0;

    for t = 2:N
        AeqSoc(t, iSoc(t)) = 1;
        AeqSoc(t, iSoc(t-1)) = -1;
        AeqSoc(t, iPgB(t-1)) = -aChGrid;
        AeqSoc(t, iPpvB(t-1)) = -aChPv;
        AeqSoc(t, iPbL(t-1)) = aDis;
    end

    Aeq = [AeqLoad; AeqPv; AeqSoc];
    beq = [beqLoad; beqPv; beqSoc];

    A = sparse(0, nVars);
    b = zeros(0, 1);

    AMode = sparse(2 * N, nVars);
    bMode = zeros(2 * N, 1);

    for t = 1:N
        AMode(t, iPgB(t)) = pars.inv_eta;
        AMode(t, iPpvB(t)) = 1;
        AMode(t, iMode(t)) = -PchMax;

        AMode(N + t, iPbL(t)) = 1 / pars.inv_eta;
        AMode(N + t, iMode(t)) = PdisMax;
        bMode(N + t) = PdisMax;
    end

    A = [A; AMode];
    b = [b; bMode];

    AGrid = sparse(N, nVars);
    bGrid = Plimit * ones(N, 1);

    for t = 1:N
        AGrid(t, iPgL(t)) = 1;
        AGrid(t, iPgB(t)) = 1;
    end

    A = [A; AGrid];
    b = [b; bGrid];

    AInvGridCharge = sparse(N, nVars);
    bInvGridCharge = pars.P_inv_limit_ac * ones(N, 1);

    for t = 1:N
        AInvGridCharge(t, iPgB(t)) = 1;
    end

    A = [A; AInvGridCharge];
    b = [b; bInvGridCharge];

    AInvAcOutput = sparse(N, nVars);
    bInvAcOutput = pars.P_inv_limit_ac * ones(N, 1);

    for t = 1:N
        AInvAcOutput(t, iPpvL(t)) = 1;
        AInvAcOutput(t, iPbL(t)) = 1;
    end

    A = [A; AInvAcOutput];
    b = [b; bInvAcOutput];

    lb = zeros(nVars, 1);
    ub = inf(nVars, 1);

    lb(iSoc) = pars.SoC_min;
    ub(iSoc) = pars.SoC_max;

    lb(iMode) = 0;
    ub(iMode) = 1;

    try
        lpOptions = optimoptions('linprog', ...
            'Display', 'off', ...
            'Algorithm', 'dual-simplex', ...
            'MaxTime', maxSolverTime_s);
    catch
        try
            lpOptions = optimoptions('linprog', ...
                'Display', 'off', ...
                'Algorithm', 'dual-simplex');
        catch
            lpOptions = optimoptions('linprog', ...
                'Display', 'off');
        end
    end

    tLp = tic;

    [x, fval, exitflag] = linprog( ...
        f, A, b, Aeq, beq, lb, ub, lpOptions);

    lpRuntime_s = toc(tLp);

    acceptLp = false;
    maxSimultaneous_kW = inf;

    if ~isempty(x) && exitflag > 0 && isfinite(fval)
        PgB = x(iPgB);
        PpvB = x(iPpvB);
        PbL = x(iPbL);

        Pch = pars.inv_eta * PgB + PpvB;
        Pdis = PbL / pars.inv_eta;

        maxSimultaneous_kW = max(min(max(Pch(:), 0), max(Pdis(:), 0)));

        if maxSimultaneous_kW <= simultaneousTol_kW
            acceptLp = true;
        end
    end

    if ~acceptLp
        plan = local_default_fast_dc_plan( ...
            N, Pcontract, safety, Plimit, PmonthOld, SoC0, exitflag);

        plan.fastSolver = "linprog_lp_rejected_no_fallback";
        plan.fastLpAccepted = false;
        plan.fastLpRuntime_s = lpRuntime_s;
        plan.fastLpExitflag = exitflag;
        plan.fastLpMaxSimultaneousChargeDischarge_kW = maxSimultaneous_kW;
        plan.fastLpTolerance_kW = simultaneousTol_kW;
        return;
    end

    PgL = x(iPgL);
    PgB = x(iPgB);
    PpvL = x(iPpvL);
    PpvB = x(iPpvB);
    PbL = x(iPbL);
    Pspill = x(iPspill);
    SoC = x(iSoc);

    Pgrid = PgL + PgB;
    Pch = pars.inv_eta * PgB + PpvB;
    Pdis = PbL / pars.inv_eta;

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

    plan.trade_buy_mask = (Pch > 1e-6).';
    plan.trade_sell_mask = (Pdis > 1e-6).';

    plan.P_grid_plan = Pgrid(:);
    plan.P_ch_plan = Pch(:);
    plan.P_dis_plan = Pdis(:);
    plan.P_curt_plan = Pspill(:);

    plan.P_gload_plan = PgL(:);
    plan.P_gbatt_plan = PgB(:);
    plan.P_pvload_plan = PpvL(:);
    plan.P_pvbatt_plan = PpvB(:);
    plan.P_bload_plan = PbL(:);
    plan.P_spill_plan = Pspill(:);
    plan.P_over_plan = Pover(:);
    plan.P_over_step_plan = Pover(:);
    plan.P_pv_ac_plan = Ppvdc(:);

    plan.SoC_plan = SoC(:);

    plan.exitflag = exitflag;
    plan.objective_value = fval;
    plan.P_bess_plan_reference_side = "dc_bus";

    plan.fastSolver = "linprog_lp_relaxation_accepted";
    plan.fastLpAccepted = true;
    plan.fastLpRuntime_s = lpRuntime_s;
    plan.fastLpExitflag = exitflag;
    plan.fastLpMaxSimultaneousChargeDischarge_kW = maxSimultaneous_kW;
    plan.fastLpTolerance_kW = simultaneousTol_kW;

    energyMarket = sum(buy(:) .* Pgrid(:)) * dt_h;

    energyNetwork = ...
        sum((tariff.distribution_energy_rate_huf_per_kWh + ...
             tariff.transmission_energy_rate_huf_per_kWh) .* Pgrid(:)) * dt_h;

    degradationCost = ...
        sum(cCh .* Pch(:)) * dt_h + ...
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


function plan = local_default_fast_dc_plan( ...
    N, Pcontract, safety, Plimit, PmonthOld, SoC0, exitflag)

    plan = struct();

    plan.is_feasible = false;
    plan.used_fallback = false;

    plan.P_contract = Pcontract;
    plan.P_contract_safety_factor = safety;
    plan.P_grid_limit = Plimit;

    plan.P_month_max_so_far = PmonthOld;
    plan.P_month_peak_candidate = inf;
    plan.P_overrun_increment_kW = inf;

    plan.trade_buy_mask = false(1, N);
    plan.trade_sell_mask = false(1, N);

    plan.P_grid_plan = inf(N, 1);
    plan.P_ch_plan = zeros(N, 1);
    plan.P_dis_plan = zeros(N, 1);
    plan.P_curt_plan = zeros(N, 1);

    plan.P_gload_plan = inf(N, 1);
    plan.P_gbatt_plan = zeros(N, 1);
    plan.P_pvload_plan = zeros(N, 1);
    plan.P_pvbatt_plan = zeros(N, 1);
    plan.P_bload_plan = zeros(N, 1);
    plan.P_spill_plan = zeros(N, 1);
    plan.P_over_plan = inf(N, 1);
    plan.P_over_step_plan = inf(N, 1);
    plan.P_pv_ac_plan = zeros(N, 1);

    plan.SoC_plan = SoC0 * ones(N, 1);

    plan.exitflag = exitflag;
    plan.objective_value = inf;
    plan.P_bess_plan_reference_side = "dc_bus";

    plan.economics.energy_cost_market = inf;
    plan.economics.energy_cost_network = inf;
    plan.economics.energy_cost_total = inf;
    plan.economics.degradation_cost = inf;
    plan.economics.spill_cost = 0;
    plan.economics.overrun_increment_cost = inf;
    plan.economics.net_cost_operational = inf;
end


function value = local_get_field(S, fieldName, defaultValue)

    if isstruct(S) && isfield(S, fieldName)
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end