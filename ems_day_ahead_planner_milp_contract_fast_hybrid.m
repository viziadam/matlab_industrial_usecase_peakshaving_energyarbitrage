function plan = ems_day_ahead_planner_milp_contract_fast_hybrid( ...
    P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, contract_state, maxSolverTime_s)
% Fast LP-relaxed hybrid AC+DC BESS combined planner.
% The LP relaxation is accepted only if both BESS branches and the shared
% central inverter are practically non-simultaneous in opposite directions.

    if nargin < 8
        maxSolverTime_s = 15;
    end

    simultaneousTol_kW = 1e-5;

    Pload = P_load_f(:);
    Ppv = max(P_pv_dc_f(:), 0);
    buy = Prices.buy_huf(:);
    N = numel(Pload);

    SoC_technical_min_dc = pars.dc.SoC_technical_min;
    SoC_technical_min_ac = pars.ac.SoC_technical_min;
    SoC_technical_min = SoC_technical_min_dc;


    if numel(Ppv) ~= N || numel(buy) ~= N
        error('HYBRID fast MILP input length mismatch.');
    end

    SoC0dc = local_get_field(pars, 'SoC_initial_dc', 0.5);
    SoC0ac = local_get_field(pars, 'SoC_initial_ac', 0.5);
    SoC0dc = min(max(SoC0dc, pars.dc.SoC_min), pars.dc.SoC_max);
    SoC0ac = min(max(SoC0ac, pars.ac.SoC_min), pars.ac.SoC_max);

    Pcontract = contract_state.P_contract_kW;
    PmonthOld = contract_state.P_month_max_so_far_kW;
    safety = local_get_field(contract_state, 'P_contract_safety_factor', 0.90);
    Plimit = safety * Pcontract;

    etaInv = max(pars.central_inv_eta_nom, eps);
    etaDcdc = max(pars.dcdc_eta_nom, eps);
    etaPcs = max(pars.pcs_eta_nom, eps);

    buyTotal = buy + tariff.distribution_energy_rate_huf_per_kWh + tariff.transmission_energy_rate_huf_per_kWh;

    degDc = build_article_simple_degradation_costs(pars.dc);
    degAc = build_article_simple_degradation_costs(pars.ac);
    cChDc = degDc.cost_ch_huf_per_kWh;
    cDisDc = degDc.cost_dis_huf_per_kWh;
    cChAc = degAc.cost_ch_huf_per_kWh;
    cDisAc = degAc.cost_dis_huf_per_kWh;

    n = 0;
    iPgL      = n + (1:N); n = n + N;
    iPgBdc    = n + (1:N); n = n + N;
    iPgBac    = n + (1:N); n = n + N;
    iPpvL     = n + (1:N); n = n + N;
    iPpvBdc   = n + (1:N); n = n + N;
    iPpvBac   = n + (1:N); n = n + N;
    iPbDcL    = n + (1:N); n = n + N;
    iPbAcL    = n + (1:N); n = n + N;
    iPspill   = n + (1:N); n = n + N;
    iSocDc          = n + (1:N); n = n + N;
    iSocAc          = n + (1:N); n = n + N;
    iSocRecoveryDeficitDc  = n + (1:N); n = n + N;
    iSocRecoveryDeficitAc  = n + (1:N); n = n + N;
    iModeDc         = n + (1:N); n = n + N;
    iModeAc         = n + (1:N); n = n + N;
    iModeInv        = n + (1:N); n = n + N;
    nVars = n;

    f = zeros(nVars, 1);
    f(iPgL) = buyTotal * dt_h;
    f(iPgBdc) = buyTotal * dt_h + cChDc * etaInv * etaDcdc * dt_h;
    f(iPgBac) = buyTotal * dt_h + cChAc * etaPcs * dt_h;
    f(iPpvBdc) = cChDc * etaDcdc * dt_h;
    f(iPpvBac) = cChAc * etaPcs * dt_h;
    f(iPbDcL) = cDisDc * (1 / max(etaDcdc * etaInv, eps)) * dt_h;
    f(iPbAcL) = cDisAc * (1 / etaPcs) * dt_h;
    
    socRecoveryPenalty_HUF_per_kWh = 1e7;
    f(iSocRecoveryDeficitDc) = ...
        socRecoveryPenalty_HUF_per_kWh * pars.dc.E_cap_nom;

    f(iSocRecoveryDeficitAc) = ...
        socRecoveryPenalty_HUF_per_kWh * pars.ac.E_cap_nom;

    AeqLoad = sparse(N, nVars);
    beqLoad = Pload;
    for t = 1:N
        AeqLoad(t, iPgL(t)) = 1;
        AeqLoad(t, iPpvL(t)) = 1;
        AeqLoad(t, iPbDcL(t)) = 1;
        AeqLoad(t, iPbAcL(t)) = 1;
    end

    AeqPv = sparse(N, nVars);
    beqPv = Ppv;
    for t = 1:N
        AeqPv(t, iPpvL(t)) = 1 / etaInv;
        AeqPv(t, iPpvBac(t)) = 1 / etaInv;
        AeqPv(t, iPpvBdc(t)) = 1;
        AeqPv(t, iPspill(t)) = 1;
    end

    AeqSocDc = sparse(N, nVars);
    beqSocDc = zeros(N, 1);
    aChGridDc = etaInv * etaDcdc * pars.dc.eta_cell * dt_h / pars.dc.E_cap_nom;
    aChPvDc = etaDcdc * pars.dc.eta_cell * dt_h / pars.dc.E_cap_nom;
    aDisDc = dt_h / max(etaInv * etaDcdc * pars.dc.eta_cell, eps) / pars.dc.E_cap_nom;
    AeqSocDc(1, iSocDc(1)) = 1;
    beqSocDc(1) = SoC0dc;
    for t = 2:N
        AeqSocDc(t, iSocDc(t)) = 1;
        AeqSocDc(t, iSocDc(t-1)) = -1;
        AeqSocDc(t, iPgBdc(t-1)) = -aChGridDc;
        AeqSocDc(t, iPpvBdc(t-1)) = -aChPvDc;
        AeqSocDc(t, iPbDcL(t-1)) = aDisDc;
    end

    AeqSocAc = sparse(N, nVars);
    beqSocAc = zeros(N, 1);
    aChAc = etaPcs * pars.ac.eta_cell * dt_h / pars.ac.E_cap_nom;
    aDisAc = dt_h / max(etaPcs * pars.ac.eta_cell, eps) / pars.ac.E_cap_nom;
    AeqSocAc(1, iSocAc(1)) = 1;
    beqSocAc(1) = SoC0ac;
    for t = 2:N
        AeqSocAc(t, iSocAc(t)) = 1;
        AeqSocAc(t, iSocAc(t-1)) = -1;
        AeqSocAc(t, iPgBac(t-1)) = -aChAc;
        AeqSocAc(t, iPpvBac(t-1)) = -aChAc;
        AeqSocAc(t, iPbAcL(t-1)) = aDisAc;
    end

    Aeq = [AeqLoad; AeqPv; AeqSocDc; AeqSocAc];
    beq = [beqLoad; beqPv; beqSocDc; beqSocAc];

    A = sparse(0, nVars);
    b = zeros(0, 1);

    AGrid = sparse(N, nVars);
    bGrid = Plimit * ones(N, 1);
    for t = 1:N
        AGrid(t, iPgL(t)) = 1;
        AGrid(t, iPgBdc(t)) = 1;
        AGrid(t, iPgBac(t)) = 1;
    end
    A = [A; AGrid];
    b = [b; bGrid];

    AInv = sparse(2 * N, nVars);
    bInv = zeros(2 * N, 1);
    for t = 1:N
        AInv(t, iPpvL(t)) = 1;
        AInv(t, iPpvBac(t)) = 1;
        AInv(t, iPbDcL(t)) = 1;
        AInv(t, iModeInv(t)) = -pars.P_inv_limit_ac;
        AInv(N+t, iPgBdc(t)) = 1;
        AInv(N+t, iModeInv(t)) = pars.P_inv_limit_ac;
        bInv(N+t) = pars.P_inv_limit_ac;
    end
    A = [A; AInv];
    b = [b; bInv];

    AModeDc = sparse(2 * N, nVars);
    bModeDc = zeros(2 * N, 1);
    for t = 1:N
        AModeDc(t, iPgBdc(t)) = etaInv;
        AModeDc(t, iPpvBdc(t)) = 1;
        AModeDc(t, iModeDc(t)) = -pars.dc.P_chg_max;
        AModeDc(N+t, iPbDcL(t)) = 1 / etaInv;
        AModeDc(N+t, iModeDc(t)) = pars.dc.P_dis_max;
        bModeDc(N+t) = pars.dc.P_dis_max;
    end
    A = [A; AModeDc];
    b = [b; bModeDc];

    PchAcMax = pars.ac.P_chg_max / etaPcs;
    PdisAcMax = pars.ac.P_dis_max * etaPcs;
    AModeAc = sparse(2 * N, nVars);
    bModeAc = zeros(2 * N, 1);
    for t = 1:N
        AModeAc(t, iPgBac(t)) = 1;
        AModeAc(t, iPpvBac(t)) = 1;
        AModeAc(t, iModeAc(t)) = -PchAcMax;
        AModeAc(N+t, iPbAcL(t)) = 1;
        AModeAc(N+t, iModeAc(t)) = PdisAcMax;
        bModeAc(N+t) = PdisAcMax;
    end
    A = [A; AModeAc];
    b = [b; bModeAc];

    ASocRecovery = sparse(2 * N, nVars);
    bSocRecovery = -SoC_technical_min * ones(2 * N, 1);

    for t = 1:N
        ASocRecovery(t, iSocDc(t)) = -1;
        ASocRecovery(t, iSocRecoveryDeficitDc(t)) = -1;

        ASocRecovery(N + t, iSocAc(t)) = -1;
        ASocRecovery(N + t, iSocRecoveryDeficitAc(t)) = -1;
    end

    A = [A; ASocRecovery];
    b = [b; bSocRecovery];

    lb = zeros(nVars, 1);
    ub = inf(nVars, 1);

    lb(iSocDc) = pars.dc.SoC_min;
    ub(iSocDc) = pars.dc.SoC_max;

    lb(iSocAc) = pars.ac.SoC_min;
    ub(iSocAc) = pars.ac.SoC_max;

    lb(iSocRecoveryDeficitDc) = 0;
    ub(iSocRecoveryDeficitDc) = SoC_technical_min_dc - pars.dc.SoC_min;

    lb(iSocRecoveryDeficitAc) = 0;
    ub(iSocRecoveryDeficitAc) = SoC_technical_min_ac - pars.ac.SoC_min;


    ub(iModeDc) = 1;
    ub(iModeAc) = 1;
    ub(iModeInv) = 1;

    try
        options = optimoptions('linprog', 'Display', 'off', 'Algorithm', 'dual-simplex', 'MaxTime', maxSolverTime_s);
    catch
        options = optimoptions('linprog', 'Display', 'off');
    end

    tLp = tic;
    [x, fval, exitflag] = linprog(f, A, b, Aeq, beq, lb, ub, options);
    lpRuntime_s = toc(tLp);

    acceptLp = false;
    maxSim = inf;
    maxInvSim = inf;
    if ~isempty(x) && exitflag > 0 && isfinite(fval)
        PgBdc = x(iPgBdc); PgBac = x(iPgBac); PpvBdc = x(iPpvBdc); PpvBac = x(iPpvBac);
        PbDcL = x(iPbDcL); PbAcL = x(iPbAcL); PpvL = x(iPpvL);
        PchDc = etaInv .* PgBdc + PpvBdc;
        PdisDc = PbDcL ./ etaInv;
        PchAc = PgBac + PpvBac;
        PdisAc = PbAcL;
        invOut = PpvL + PpvBac + PbDcL;
        invIn = PgBdc;
        maxSim = max([min(max(PchDc(:), 0), max(PdisDc(:), 0)); min(max(PchAc(:), 0), max(PdisAc(:), 0))]);
        maxInvSim = max(min(max(invOut(:), 0), max(invIn(:), 0)));
        acceptLp = maxSim <= simultaneousTol_kW && maxInvSim <= simultaneousTol_kW;
    end

    if ~acceptLp
        plan = local_infeasible_hybrid_plan(N, Pcontract, safety, Plimit, PmonthOld, SoC0dc, SoC0ac, exitflag);
        plan.fastSolver = "linprog_lp_rejected_no_fallback";
        plan.fastLpAccepted = false;
        plan.fastLpRuntime_s = lpRuntime_s;
        plan.fastLpExitflag = exitflag;
        plan.fastLpMaxSimultaneousChargeDischarge_kW = maxSim;
        plan.fastLpMaxCentralInverterBidirectional_kW = maxInvSim;
        plan.fastLpTolerance_kW = simultaneousTol_kW;
        return;
    end

    PgL = x(iPgL); PgBdc = x(iPgBdc); PgBac = x(iPgBac);
    PpvL = x(iPpvL); PpvBdc = x(iPpvBdc); PpvBac = x(iPpvBac);
    PbDcL = x(iPbDcL); PbAcL = x(iPbAcL); Pspill = x(iPspill);
    SocDc = x(iSocDc); SocAc = x(iSocAc);

    Pgrid = PgL + PgBdc + PgBac;
    PchDc = etaInv .* PgBdc + PpvBdc;
    PdisDc = PbDcL ./ etaInv;
    PchAc = PgBac + PpvBac;
    PdisAc = PbAcL;
    Pch = PchDc + PchAc;
    Pdis = PdisDc + PdisAc;
    Pover = max(Pgrid - Plimit, 0);
    Ppeak = max(PmonthOld, max(Pgrid));

    plan = local_build_plan(N, Pcontract, safety, Plimit, PmonthOld, SoC0dc, SoC0ac, exitflag);
    plan.is_feasible = true;
    plan.used_fallback = false;
    plan.P_month_peak_candidate = Ppeak;
    plan.P_overrun_increment_kW = max(Pover);
    plan.trade_buy_mask = (Pch > 1e-6).';
    plan.trade_sell_mask = (Pdis > 1e-6).';
    plan.P_grid_plan = Pgrid(:);
    plan.P_ch_plan = Pch(:);
    plan.P_dis_plan = Pdis(:);
    plan.P_curt_plan = Pspill(:);
    plan.P_gload_plan = PgL(:);
    plan.P_gbatt_dc_plan = PgBdc(:);
    plan.P_gbatt_ac_plan = PgBac(:);
    plan.P_gbatt_plan = PgBdc(:) + PgBac(:);
    plan.P_pvload_plan = PpvL(:);
    plan.P_pvbatt_dc_plan = PpvBdc(:);
    plan.P_pvbatt_ac_plan = PpvBac(:);
    plan.P_pvbatt_plan = PpvBdc(:) + PpvBac(:);
    plan.P_bload_dc_plan = PbDcL(:);
    plan.P_bload_ac_plan = PbAcL(:);
    plan.P_bload_plan = PbDcL(:) + PbAcL(:);
    plan.P_spill_plan = Pspill(:);
    plan.P_over_plan = Pover(:);
    plan.P_over_step_plan = Pover(:);
    plan.P_ch_dc_plan = PchDc(:);
    plan.P_dis_dc_plan = PdisDc(:);
    plan.P_ch_ac_plan = PchAc(:);
    plan.P_dis_ac_plan = PdisAc(:);
    plan.SoC_dc_plan = SocDc(:);
    plan.SoC_ac_plan = SocAc(:);
    plan.SoC_plan = ((SocDc(:) .* pars.dc.E_cap_nom) + (SocAc(:) .* pars.ac.E_cap_nom)) ./ max(pars.dc.E_cap_nom + pars.ac.E_cap_nom, eps);
    plan.objective_value = fval;
    plan.fastSolver = "linprog_lp_relaxation_accepted";
    plan.fastLpAccepted = true;
    plan.fastLpRuntime_s = lpRuntime_s;
    plan.fastLpExitflag = exitflag;
    plan.fastLpMaxSimultaneousChargeDischarge_kW = maxSim;
    plan.fastLpMaxCentralInverterBidirectional_kW = maxInvSim;
    plan.fastLpTolerance_kW = simultaneousTol_kW;

    energyMarket = sum(buy(:) .* Pgrid(:)) * dt_h;
    energyNetwork = sum((tariff.distribution_energy_rate_huf_per_kWh + tariff.transmission_energy_rate_huf_per_kWh) .* Pgrid(:)) * dt_h;
    degradationCost = sum(cChDc .* (PchDc(:) * etaDcdc)) * dt_h + sum(cDisDc .* (PdisDc(:) / max(etaDcdc, eps))) * dt_h + sum(cChAc .* (PchAc(:) * etaPcs)) * dt_h + sum(cDisAc .* (PdisAc(:) / max(etaPcs, eps))) * dt_h;
    plan.economics.energy_cost_market = energyMarket;
    plan.economics.energy_cost_network = energyNetwork;
    plan.economics.energy_cost_total = energyMarket + energyNetwork;
    plan.economics.degradation_cost = degradationCost;
    plan.economics.spill_cost = 0;
    plan.economics.overrun_increment_cost = 0;
    plan.economics.net_cost_operational = energyMarket + energyNetwork + degradationCost;
end

function plan = local_infeasible_hybrid_plan(N, Pcontract, safety, Plimit, PmonthOld, SoC0dc, SoC0ac, exitflag)
    plan = local_build_plan(N, Pcontract, safety, Plimit, PmonthOld, SoC0dc, SoC0ac, exitflag);
end

function plan = local_build_plan(N, Pcontract, safety, Plimit, PmonthOld, SoC0dc, SoC0ac, exitflag)
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
    plan.P_ch_plan = zeros(N, 1);
    plan.P_dis_plan = zeros(N, 1);
    plan.P_curt_plan = zeros(N, 1);
    plan.P_ch_dc_plan = zeros(N, 1);
    plan.P_dis_dc_plan = zeros(N, 1);
    plan.P_ch_ac_plan = zeros(N, 1);
    plan.P_dis_ac_plan = zeros(N, 1);
    plan.P_gload_plan = inf(N, 1);
    plan.P_gbatt_dc_plan = zeros(N, 1);
    plan.P_gbatt_ac_plan = zeros(N, 1);
    plan.P_gbatt_plan = zeros(N, 1);
    plan.P_pvload_plan = zeros(N, 1);
    plan.P_pvbatt_dc_plan = zeros(N, 1);
    plan.P_pvbatt_ac_plan = zeros(N, 1);
    plan.P_pvbatt_plan = zeros(N, 1);
    plan.P_bload_dc_plan = zeros(N, 1);
    plan.P_bload_ac_plan = zeros(N, 1);
    plan.P_bload_plan = zeros(N, 1);
    plan.P_spill_plan = zeros(N, 1);
    plan.P_over_plan = inf(N, 1);
    plan.P_over_step_plan = inf(N, 1);
    plan.SoC_dc_plan = SoC0dc * ones(N, 1);
    plan.SoC_ac_plan = SoC0ac * ones(N, 1);
    plan.SoC_plan = 0.5 * (plan.SoC_dc_plan + plan.SoC_ac_plan);
    plan.exitflag = exitflag;
    plan.objective_value = inf;
    plan.P_bess_plan_reference_side = "hybrid_split";
end

function value = local_get_field(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName)
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end
