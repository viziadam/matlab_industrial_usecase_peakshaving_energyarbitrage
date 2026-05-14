% function plan = ems_day_ahead_planner_milp(P_load_f, P_pv_dc_f, Prices, pars, dt_h, current_period_peak)
%     % MILP alapú EMS tervező - Peak Shaving + Arbitrage szimultán optimalizáció
%     N = length(P_load_f);
% 
%     % --- 1. Hatásfokok és Degradáció ---
%     eta_in  = pars.inv_eta * pars.eta_c * pars.eta_cell;
%     eta_out = pars.eta_cell * pars.eta_d * pars.inv_eta;
%     cost_deg = 5.0; % HUF/kWh
% 
%     % --- 2. Változók definiálása (x vektor struktúrája) ---
%     % x(1:N)      -> P_ch (Töltés [kW])
%     % x(N+1:2N)   -> P_dis (Kisütés [kW])
%     % x(2N+1:3N)  -> SoC (Töltöttség [0-1])
%     % x(3N+1:4N)  -> u (Bináris: 1=tölt, 0=kisüt/vár)
%     % x(4N+1)     -> P_peak (A napra tervezett hálózati csúcs)
% 
%     nVars = 4*N + 1;
% 
%     % --- 3. Célfüggvény (Minimalizálandó költség) ---
%     f = zeros(nVars, 1);
%     % Energiaköltség (Vétel - Eladás) + Degradáció
%     f(1:N)      = (Prices.buy_huf / eta_in) + cost_deg; % Töltés költsége
%     f(N+1:2*N)   = -(Prices.sell_huf * eta_out) + cost_deg; % Kisütés (bevétel negatív, deg pozitív)
%     % Peak Shaving súlya (Nagyon nagy szám, hogy ez legyen a prioritás!)
%     f(4*N+1)    = 100000; 
% 
%     % --- 4. Korlátok (A*x <= b) ---
%     A = []; b = [];
% 
%     % A) Hálózati egyenlet és Peak tracking: P_grid <= P_peak
%     % P_load - P_pv_ac + P_ch - P_dis <= P_peak
%     % P_ch - P_dis - P_peak <= P_pv_ac - P_load
%     for t = 1:N
%         row = zeros(1, nVars);
%         row(t) = 1;             % P_ch
%         row(N+t) = -1;          % P_dis
%         row(4*N+1) = -1;        % -P_peak
%         A = [A; row];
%         P_pv_ac = min(P_pv_dc_f(t) * pars.inv_eta, pars.P_inv_limit_ac);
%         b = [b; P_pv_ac - P_load_f(t)];
%     end
% 
%     % B) Ratchet-effektus: P_peak >= current_period_peak
%     % -P_peak <= -current_period_peak
%     row = zeros(1, nVars);
%     row(4*N+1) = -1;
%     A = [A; row];
%     b = [b; -current_period_peak];
% 
%     % --- 5. Egyenlőségi korlátok 
%     Aeq = zeros(N, nVars);
%     beq = zeros(N, 1);
%     SoC_start = 0.5; % Feltételezett induló SoC a nap elején
% 
%     for t = 1:N
%         Aeq(t, 2*N+t) = 1; % SoC(t)
%         if t == 1
%             beq(t) = SoC_start; 
%         else
%             Aeq(t, 2*N+t-1) = -1; % -SoC(t-1)
%             Aeq(t, t-1) = -(eta_in * dt_h) / pars.E_cap_nom;
%             Aeq(t, N+t-1) = (1/eta_out * dt_h) / pars.E_cap_nom;
%         end
%     end
% 
%     % --- 6. Határértékek (lb, ub) ---
%     lb = zeros(nVars, 1);
%     ub = inf(nVars, 1);
% 
%     lb(2*N+1:3*N) = pars.SoC_min;
%     ub(2*N+1:3*N) = pars.SoC_max;
% 
%     ub(1:N) = pars.P_inv_limit_ac; % Max töltés
%     ub(N+1:2*N) = pars.P_inv_limit_ac; % Max kisütés
% 
%     % --- 7. Megoldás ---
%     intcon = (3*N+1):(4*N); % Bináris változók indexei
%     options = optimoptions('intlinprog', 'Display', 'off');
% 
%     [x, ~] = intlinprog(f, intcon, A, b, Aeq, beq, lb, ub, options);
% 
%     % --- 8. Eredmények kinyerése ---
%     if isempty(x)
%         % Ha nem talált megoldást (fallback)
%         plan.P_limit = max(current_period_peak, max(P_load_f));
%         plan.trade_buy_mask = false(1, N);
%         plan.trade_sell_mask = false(1, N);
%     else
%         plan.P_limit = x(4*N+1);
%         plan.trade_buy_mask = x(1:N) > 0.1;
%         plan.trade_sell_mask = x(N+1:2*N) > 0.1;
%         plan.P_ch_plan = x(1:N);
%         plan.P_dis_plan = x(N+1:2*N);
%     end
% end

function plan = ems_day_ahead_planner_milp(P_load_f, P_pv_dc_f, Prices, pars, dt_h, current_period_peak)
    % N dinamikus meghatározása (lehet 288 vagy 576 is)
    N = length(P_load_f);
    
    % --- 1. Hatásfokok és Paraméterek ---
    eta_in  = pars.inv_eta * pars.eta_c * pars.eta_cell;
    eta_out = pars.eta_cell * pars.eta_d * pars.inv_eta;
    cost_deg = 5.0; % HUF/kWh
    
    % Vektorok oszloppá alakítása (KÖTELEZŐ az intlinprog-hoz)
    buy_p = Prices.buy_huf(:);
    sell_p = Prices.sell_huf(:);

    % --- 2. Változók száma ---
    % x(1:N)      -> P_ch
    % x(N+1:2N)   -> P_dis
    % x(2N+1:3N)  -> SoC
    % x(3N+1:4N)  -> u (bináris: 1=töltés, 0=kisütés/semmi)
    % x(4N+1)     -> P_peak
    nVars = 4*N + 1;

    % --- 3. Célfüggvény ---
    f = zeros(nVars, 1);
    f(1:N)        = (buy_p ./ eta_in) + cost_deg; 
    f(N+1:2*N)    = -(sell_p .* eta_out) + cost_deg; 
    f(4*N+1)      = 100000; % Peak Shaving prioritás súlya

    % --- 4. Egyenlőtlenségi korlátok (A*x <= b) ---
    A = []; b = [];
    
    % A) Grid Power Tracking: P_ch(t) - P_dis(t) - P_peak <= P_pv_ac(t) - P_load(t)
    A_grid = zeros(N, nVars);
    b_grid = zeros(N, 1);
    for t = 1:N
        P_pv_ac = min(P_pv_dc_f(t) * pars.inv_eta, pars.P_inv_limit_ac);
        A_grid(t, t)     = 1;   % P_ch
        A_grid(t, N+t)   = -1;  % P_dis
        A_grid(t, 4*N+1) = -1;  % -P_peak
        b_grid(t)        = P_pv_ac - P_load_f(t);
    end
    A = [A; A_grid]; b = [b; b_grid];

    % B) Bináris korlátok: Ne töltsön és süssön egyszerre
    % P_ch(t) <= u(t) * P_max
    % P_dis(t) <= (1 - u(t)) * P_max  ==> P_dis(t) + u(t)*P_max <= P_max
    A_bin = zeros(2*N, nVars);
    b_bin = zeros(2*N, 1);
    P_max = pars.P_inv_limit_ac;
    for t = 1:N
        % P_ch(t) - u(t)*P_max <= 0
        A_bin(t, t) = 1;
        A_bin(t, 3*N+t) = -P_max;
        b_bin(t) = 0;
        % P_dis(t) + u(t)*P_max <= P_max
        A_bin(N+t, N+t) = 1;
        A_bin(N+t, 3*N+t) = P_max;
        b_bin(N+t) = P_max;
    end
    A = [A; A_bin]; b = [b; b_bin];

    % C) Ratchet-effektus
    row_r = zeros(1, nVars);
    row_r(4*N+1) = -1;
    A = [A; row_r]; b = [b; -current_period_peak];

    % --- 5. Egyenlőségi korlátok (SoC dinamika) ---
    Aeq = zeros(N, nVars);
    beq = zeros(N, 1);
    SoC_start = 0.5; % Ezt érdemes lehet majd a state_bess-ből beadni!
    
    for t = 1:N
        Aeq(t, 2*N+t) = 1; % SoC(t)
        if t == 1
            beq(t) = SoC_start;
        else
            Aeq(t, 2*N+t-1) = -1; 
            Aeq(t, t-1)     = -(eta_in * dt_h) / pars.E_cap_nom;
            Aeq(t, N+t-1)   = (1/eta_out * dt_h) / pars.E_cap_nom;
        end
    end

    % --- 6. Határértékek ---
    lb = zeros(nVars, 1);
    ub = inf(nVars, 1);
    lb(2*N+1:3*N) = pars.SoC_min;
    ub(2*N+1:3*N) = pars.SoC_max;
    ub(3*N+1:4*N) = 1; % Binárisok felső határa

    % --- 7. Megoldás ---
    intcon = (3*N+1):(4*N);
    options = optimoptions('intlinprog', 'Display', 'off');
    [x, ~] = intlinprog(f, intcon, A, b, Aeq, beq, lb, ub, options);

    % --- 8. Eredmények ---
    if isempty(x)
        plan.P_limit = max(current_period_peak, max(P_load_f));
        plan.trade_buy_mask = false(1, N);
        plan.trade_sell_mask = false(1, N);
    else
        plan.P_limit = x(4*N+1);
        plan.trade_buy_mask  = x(1:N) > 0.1;
        plan.trade_sell_mask = x(N+1:2*N) > 0.1;
        plan.P_ch_plan  = x(1:N);
        plan.P_dis_plan = x(N+1:2*N);
        plan.SoC_plan   = x(2*N+1:3*N);
    end
end

