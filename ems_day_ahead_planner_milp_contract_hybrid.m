function plan = ems_day_ahead_planner_milp_contract_hybrid( ...
    P_load_f, P_pv_dc_f, Prices, pars, tariff, dt_h, contract_state, maxSolverTime_s)
% EMS_DAY_AHEAD_PLANNER_MILP_CONTRACT_HYBRID
%
% Combined mode MILP planner hybrid AC+DC BESS rendszerhez.
%
% A modell ket kulon energiatárolot kezel:
%   - DC BESS: PV DC busz <-> DC/DC <-> BESS pack
%   - AC BESS: AC busz <-> PCSB <-> BESS pack
%
% A MILP-ben a konverterek nevleges hatasfokkal szerepelnek, a teljes
% teljesitmenyfuggo vesztesegszamitas a topology_hybrid_coupled fuggvenyben
% tortenik.

    if nargin < 8
        maxSolverTime_s = 15;
    end

    requiredParsFields = { ...
        'dc', 'ac', ...
        'P_inv_limit_ac', ...
        'central_inv_eta_nom', ...
        'dcdc_eta_nom', ...
        'pcs_eta_nom'};

    for k = 1:numel(requiredParsFields)
        if ~isfield(pars, requiredParsFields{k})
            error('Hianyzo pars mezo a HYBRID MILP-ben: pars.%s', requiredParsFields{k});
        end
    end

    requiredSubFields = {'E_cap_nom', 'P_chg_max', 'P_dis_max', 'SoC_min', 'SoC_max', 'eta_cell'};

    for k = 1:numel(requiredSubFields)
        if ~isfield(pars.dc, requiredSubFields{k})
            error('Hianyzo pars.dc mezo a HYBRID MILP-ben: pars.dc.%s', requiredSubFields{k});
        end

        if ~isfield(pars.ac, requiredSubFields{k})
            error('Hianyzo pars.ac mezo a HYBRID MILP-ben: pars.ac.%s', requiredSubFields{k});
        end
    end

    requiredTariffFields = { ...
        'distribution_energy_rate_huf_per_kWh', ...
        'transmission_energy_rate_huf_per_kWh'};

    for k = 1:numel(requiredTariffFields)
        if ~isfield(tariff, requiredTariffFields{k})
            error('Hianyzo tariff mezo a HYBRID MILP-ben: tariff.%s', requiredTariffFields{k});
        end
    end

    Pload = P_load_f(:);
    Ppvdc = P_pv_dc_f(:);
    buy = Prices.buy_huf(:);

    N = numel(Pload);

    if numel(Ppvdc) ~= N || numel(buy) ~= N
        error('HYBRID MILP bemeneti vektorhossz elteres.');
    end

    if isfield(pars, 'SoC_initial_dc')
        SoC0dc = pars.SoC_initial_dc;
    else
        SoC0dc = 0.5;
    end

    if isfield(pars, 'SoC_initial_ac')
        SoC0ac = pars.SoC_initial_ac;
    else
        SoC0ac = 0.5;
    end

    SoC0dc = min(max(SoC0dc, pars.dc.SoC_min), pars.dc.SoC_max);
    SoC0ac = min(max(SoC0ac, pars.ac.SoC_min), pars.ac.SoC_max);

    Pcontract = contract_state.P_contract_kW;
    PmonthOld = contract_state.P_month_max_so_far_kW;

    if isfield(contract_state, 'P_contract_safety_factor')
        safety = contract_state.P_contract_safety_factor;
    else
        safety = 0.90;
    end

    Plimit = safety * Pcontract;

    etaInv = max(pars.central_inv_eta_nom, eps);
    etaDcdc = max(pars.dcdc_eta_nom, eps);
    etaPcs = max(pars.pcs_eta_nom, eps);

    Ppv = max(Ppvdc, 0);

    buyTotal = buy ...
        + tariff.distribution_energy_rate_huf_per_kWh ...
        + tariff.transmission_energy_rate_huf_per_kWh;

    degDc = build_article_simple_degradation_costs(pars.dc);
    degAc = build_article_simple_degradation_costs(pars.ac);

    cChDc = degDc.cost_ch_huf_per_kWh;
    cDisDc = degDc.cost_dis_huf_per_kWh;
    cChAc = degAc.cost_ch_huf_per_kWh;
    cDisAc = degAc.cost_dis_huf_per_kWh;

    % =====================================================================
    % Dontesi valtozok
    % =====================================================================
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
    iSocDc    = n + (1:N); n = n + N;
    iSocAc    = n + (1:N); n = n + N;
    iModeDc   = n + (1:N); n = n + N;
    iModeAc   = n + (1:N); n = n + N;

    nVars = n;

    % =====================================================================
    % Celfuggveny
    % =====================================================================
    f = zeros(nVars, 1);

    f(iPgL) = buyTotal * dt_h;
    f(iPgBdc) = buyTotal * dt_h + cChDc * etaInv * etaDcdc * dt_h;
    f(iPgBac) = buyTotal * dt_h + cChAc * etaPcs * dt_h;
    f(iPpvBdc) = cChDc * etaDcdc * dt_h;
    f(iPpvBac) = cChAc * etaPcs * dt_h;
    f(iPbDcL) = cDisDc * (1 / max(etaDcdc * etaInv, eps)) * dt_h;
    f(iPbAcL) = cDisAc * (1 / etaPcs) * dt_h;

    % =====================================================================
    % Egyenlosegek
    % =====================================================================
    AeqLoad = zeros(N, nVars);
    beqLoad = Pload;

    for t = 1:N
        AeqLoad(t, iPgL(t)) = 1;
        AeqLoad(t, iPpvL(t)) = 1;
        AeqLoad(t, iPbDcL(t)) = 1;
        AeqLoad(t, iPbAcL(t)) = 1;
    end

    % PV DC merleg:
    %   (PV->load + PV->AC-BESS) / etaInv + PV->DC-BESS + spill = PVdc
    AeqPv = zeros(N, nVars);
    beqPv = Ppv;

    for t = 1:N
        AeqPv(t, iPpvL(t)) = 1 / etaInv;
        AeqPv(t, iPpvBac(t)) = 1 / etaInv;
        AeqPv(t, iPpvBdc(t)) = 1;
        AeqPv(t, iPspill(t)) = 1;
    end

    AeqSocDc = zeros(N, nVars);
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

    AeqSocAc = zeros(N, nVars);
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

    % =====================================================================
    % Egyenlotlensegek
    % =====================================================================
    A = [];
    b = [];

    % Grid limit: load import + DC-BESS grid charge + AC-BESS grid charge
    AGrid = zeros(N, nVars);
    bGrid = Plimit * ones(N, 1);

    for t = 1:N
        AGrid(t, iPgL(t)) = 1;
        AGrid(t, iPgBdc(t)) = 1;
        AGrid(t, iPgBac(t)) = 1;
    end

    A = [A; AGrid];
    b = [b; bGrid];

    % Central inverter AC oldali kimeneti korlat.
    AInvOut = zeros(N, nVars);
    bInvOut = pars.P_inv_limit_ac * ones(N, 1);

    for t = 1:N
        AInvOut(t, iPpvL(t)) = 1;
        AInvOut(t, iPpvBac(t)) = 1;
        AInvOut(t, iPbDcL(t)) = 1;
    end

    A = [A; AInvOut];
    b = [b; bInvOut];

    % Central inverter grid -> DC-BESS toltes korlat.
    AInvGridCharge = zeros(N, nVars);
    bInvGridCharge = pars.P_inv_limit_ac * ones(N, 1);

    for t = 1:N
        AInvGridCharge(t, iPgBdc(t)) = 1;
    end

    A = [A; AInvGridCharge];
    b = [b; bInvGridCharge];

    % DC-BESS toltes/kisutes kizaras es teljesitmenykorlat.
    AModeDc = zeros(2*N, nVars);
    bModeDc = zeros(2*N, 1);

    for t = 1:N
        % DC busz oldali charge: etaInv*PgBdc + PpvBdc <= P_chg_max * modeDc
        AModeDc(t, iPgBdc(t)) = etaInv;
        AModeDc(t, iPpvBdc(t)) = 1;
        AModeDc(t, iModeDc(t)) = -pars.dc.P_chg_max;

        % DC busz oldali discharge: PbDcL / etaInv <= P_dis_max * (1-modeDc)
        AModeDc(N+t, iPbDcL(t)) = 1 / etaInv;
        AModeDc(N+t, iModeDc(t)) = pars.dc.P_dis_max;
        bModeDc(N+t) = pars.dc.P_dis_max;
    end

    A = [A; AModeDc];
    b = [b; bModeDc];

    % AC-BESS toltes/kisutes kizaras es teljesitmenykorlat.
    PchAcMax = pars.ac.P_chg_max / etaPcs;
    PdisAcMax = pars.ac.P_dis_max * etaPcs;

    AModeAc = zeros(2*N, nVars);
    bModeAc = zeros(2*N, 1);

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

    % =====================================================================
    % Korlatok
    % =====================================================================
    lb = zeros(nVars, 1);
    ub = inf(nVars, 1);

    lb(iSocDc) = pars.dc.SoC_min;
    ub(iSocDc) = pars.dc.SoC_max;

    lb(iSocAc) = pars.ac.SoC_min;
    ub(iSocAc) = pars.ac.SoC_max;

    lb(iModeDc) = 0;
    ub(iModeDc) = 1;

    lb(iModeAc) = 0;
    ub(iModeAc) = 1;

    intcon = [iModeDc, iModeAc];

    options = optimoptions('intlinprog', ...
        'Display', 'off', ...
        'MaxTime', maxSolverTime_s, ...
        'RelativeGapTolerance', 0.01, ...
        'IntegerPreprocess', 'advanced', ...
        'RootLPAlgorithm', 'dual-simplex');

    [x, fval, exitflag] = intlinprog(f, intcon, A, b, Aeq, beq, lb, ub, options);

    if isempty(x) || exitflag <= 0 || ~isfinite(fval)
        plan = local_infeasible_hybrid_plan(N, Pcontract, safety, Plimit, PmonthOld, SoC0dc, SoC0ac, exitflag);
        return;
    end

    PgL = x(iPgL);
    PgBdc = x(iPgBdc);
    PgBac = x(iPgBac);
    PpvL = x(iPpvL);
    PpvBdc = x(iPpvBdc);
    PpvBac = x(iPpvBac);
    PbDcL = x(iPbDcL);
    PbAcL = x(iPbAcL);
    Pspill = x(iPspill);
    SocDc = x(iSocDc);
    SocAc = x(iSocAc);

    Pgrid = PgL + PgBdc + PgBac;
    PchDc = etaInv .* PgBdc + PpvBdc;
    PdisDc = PbDcL ./ etaInv;
    PchAc = PgBac + PpvBac;
    PdisAc = PbAcL;

    Pch = PchDc + PchAc;
    Pdis = PdisDc + PdisAc;
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
    plan.P_gbatt_dc_plan = PgBdc(:);
    plan.P_gbatt_ac_plan = PgBac(:);
    plan.P_gbatt_plan = (PgBdc + PgBac);
    plan.P_pvload_plan = PpvL(:);
    plan.P_pvbatt_dc_plan = PpvBdc(:);
    plan.P_pvbatt_ac_plan = PpvBac(:);
    plan.P_pvbatt_plan = (PpvBdc + PpvBac);
    plan.P_bload_dc_plan = PbDcL(:);
    plan.P_bload_ac_plan = PbAcL(:);
    plan.P_bload_plan = (PbDcL + PbAcL);
    plan.P_spill_plan = Pspill(:);
    plan.P_over_plan = Pover(:);
    plan.P_over_step_plan = Pover(:);

    plan.P_ch_dc_plan = PchDc(:);
    plan.P_dis_dc_plan = PdisDc(:);
    plan.P_ch_ac_plan = PchAc(:);
    plan.P_dis_ac_plan = PdisAc(:);

    plan.SoC_dc_plan = SocDc(:);
    plan.SoC_ac_plan = SocAc(:);
    plan.SoC_plan = ((SocDc(:) .* pars.dc.E_cap_nom) + (SocAc(:) .* pars.ac.E_cap_nom)) ./ ...
        max(pars.dc.E_cap_nom + pars.ac.E_cap_nom, eps);

    plan.exitflag = exitflag;
    plan.objective_value = fval;
    plan.P_bess_plan_reference_side = "hybrid_split";
    plan.central_inv_eta_nom = etaInv;
    plan.dcdc_eta_nom = etaDcdc;
    plan.pcs_eta_nom = etaPcs;

    energyMarket = sum(buy(:) .* Pgrid(:)) * dt_h;
    energyNetwork = sum((tariff.distribution_energy_rate_huf_per_kWh + tariff.transmission_energy_rate_huf_per_kWh) .* Pgrid(:)) * dt_h;
    degradationCost = ...
        sum(cChDc .* (PchDc(:) * etaDcdc)) * dt_h + ...
        sum(cDisDc .* (PdisDc(:) / max(etaDcdc, eps))) * dt_h + ...
        sum(cChAc .* (PchAc(:) * etaPcs)) * dt_h + ...
        sum(cDisAc .* (PdisAc(:) / max(etaPcs, eps))) * dt_h;

    plan.economics.energy_cost_market = energyMarket;
    plan.economics.energy_cost_network = energyNetwork;
    plan.economics.energy_cost_total = energyMarket + energyNetwork;
    plan.economics.degradation_cost = degradationCost;
    plan.economics.spill_cost = 0;
    plan.economics.overrun_increment_cost = 0;
    plan.economics.net_cost_operational = energyMarket + energyNetwork + degradationCost;
end


function plan = local_infeasible_hybrid_plan(N, Pcontract, safety, Plimit, PmonthOld, SoC0dc, SoC0ac, exitflag)

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
    plan.P_pvload_plan = zeros(N, 1);
    plan.P_pvbatt_dc_plan = zeros(N, 1);
    plan.P_pvbatt_ac_plan = zeros(N, 1);
    plan.P_bload_dc_plan = zeros(N, 1);
    plan.P_bload_ac_plan = zeros(N, 1);
    plan.P_spill_plan = zeros(N, 1);
    plan.P_over_plan = inf(N, 1);
    plan.P_over_step_plan = inf(N, 1);
    plan.SoC_dc_plan = SoC0dc * ones(N, 1);
    plan.SoC_ac_plan = SoC0ac * ones(N, 1);
    plan.SoC_plan = 0.5 * (plan.SoC_dc_plan + plan.SoC_ac_plan);
    plan.exitflag = exitflag;
    plan.objective_value = inf;
end
