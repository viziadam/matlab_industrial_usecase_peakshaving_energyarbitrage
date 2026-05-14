function plan = ems_day_ahead_planner(P_load_forecast, P_pv_dc_forecast, Prices, pars, dt_h, current_period_peak)
    % EMS_DAY_AHEAD_PLANNER - Kiegészítve a "Kilincsmű-effektus" memóriájával
    
    N = length(P_load_forecast);
    
    % --- 1. HATÁSFOKOK ÉS KÖLTSÉGEK KISZÁMÍTÁSA ---
    % (Ezeket KÖTELEZŐ legfelül definiálni, mert később hivatkozunk rájuk!)
    eta_in  = pars.inv_eta * pars.eta_c * pars.eta_cell;
    eta_out = pars.eta_cell * pars.eta_d * pars.inv_eta;
    
    if isfield(pars, 'deg_cost_huf_kwh')
        cost_deg = pars.deg_cost_huf_kwh;
    else
        cost_deg = 5.0; % Alapértelmezett amortizációs költség [HUF/kWh]
    end
    
    % --- 2. CSÚCSLEVÁGÁS TERVEZÉSE (Peak Shaving) ---
    P_pv_ac_forecast = min(P_pv_dc_forecast .* pars.inv_eta, pars.P_inv_limit_ac);
    P_net_forecast = P_load_forecast - P_pv_ac_forecast;
    
    E_usable_ac = pars.E_cap_nom * (pars.SoC_max - pars.SoC_min) * eta_out;
    E_reserved_for_peak = E_usable_ac * 0.80; 
    
    sorted_net = sort(P_net_forecast, 'descend');
    max_forecast_peak = max(0, sorted_net(1));
    
    % Ha a várható napi csúcs kisebb, mint amit már úgyis kifizettünk a hónapban,
    % akkor nincs értelme csúcsot vágni! A limit marad az eddigi maximum.
    if max_forecast_peak <= current_period_peak
        plan.P_limit = current_period_peak;
    else
        % Ha a várható csúcs nagyobb, mint a havi eddigi maximum, 
        % akkor megpróbáljuk minél jobban lelapítani, de legfeljebb a havi maximumig.
        P_limit_target = max_forecast_peak;
        step_kW = 2.5; 
        
        while P_limit_target > current_period_peak
            peaks = sorted_net(sorted_net > P_limit_target);
            E_req = sum(peaks - P_limit_target) * dt_h;
            
            if E_req >= E_reserved_for_peak
                break; % Elértük az akku kapacitás határát
            end
            P_limit_target = P_limit_target - step_kW;
        end
        plan.P_limit = max(current_period_peak, P_limit_target);
    end

    % --- 3. ARBITRÁZS TERVEZÉSE ---
    % Tényleges marginális költség / bevétel
    Effective_Buy_Cost = (Prices.buy_huf ./ eta_in) + cost_deg;
    Effective_Sell_Rev = Prices.sell_huf .* eta_out;
    
    trade_buy_mask = false(1, N);
    trade_sell_mask = false(1, N);
    
    [min_buy_cost, min_buy_idx] = min(Effective_Buy_Cost);
    [max_sell_rev, max_sell_idx] = max(Effective_Sell_Rev);
    
    % Kereskedési feltétel: Később adjuk el, mint ahogy vesszük ÉS a profit > 0
    if (max_sell_idx > min_buy_idx) && (max_sell_rev > min_buy_cost)
        buy_range = max(1, min_buy_idx-12) : min(N, min_buy_idx+12);
        sell_range = max(1, max_sell_idx-12) : min(N, max_sell_idx+12);
        
        peak_danger_mask = (P_net_forecast > (plan.P_limit * 0.9)); 
        
        for b = buy_range
            % Csak ha profitábilis ÉS nincs csúcsveszély
            if Effective_Sell_Rev(max_sell_idx) > Effective_Buy_Cost(b) && ~peak_danger_mask(b)
                trade_buy_mask(b) = true;
            end
        end
        trade_sell_mask(sell_range) = true;
    end
    
    plan.trade_buy_mask = trade_buy_mask;
    plan.trade_sell_mask = trade_sell_mask;
end

% =========================================================================
% === EMS VEZÉRLŐ ADATSZÓTÁR (DATA DICTIONARY) ÉS VÁLTOZÓ DEFINÍCIÓK ===
% =========================================================================
%
% 1. RENDSZER BEMENETEK (INPUTS)
% -------------------------------------------------------------------------
% P_load_forecast     : [1xN double sorvektor] (pl. 1x288)
%                       Előrejelzett gyári AC fogyasztás a vizsgált napra. 
%                       Mértékegység: [kW].
%                       Származás: Heti perzisztencia (d-7 napi valós adat).
%
% P_pv_dc_forecast    : [1xN double sorvektor] (pl. 1x288)
%                       Előrejelzett nyers egyenáramú (DC) napelem termelés.
%                       Mértékegység: [kW]. 
%                       Származás: A két tájolási csoport (A és B) DC összessége.
%
% Prices              : [1x1 struct]
%                       A másnapi (Day-Ahead) tőzsdei árakat tartalmazza.
%                       Mezői:
%                         - buy_huf  : [1xN sorvektor] Hálózati vétel ára [HUF/kWh]
%                         - sell_huf : [1xN sorvektor] Hálózati eladás ára [HUF/kWh]
%
% dt_h                : [Skalár double]
%                       A szimuláció időlépése órában kifejezve. 
%                       Értéke fixen: 5/60 (azaz 5 perc).
%
% current_period_peak : [Skalár double]
%                       A "Kilincsmű-effektus" (Ratchet Effect) memóriája.
%                       Az aktuális elszámolási időszakban (pl. adott hónapban) 
%                       eddig mért LEGMAGASABB valós hálózati import csúcs.
%                       Mértékegység: [kW]. Alapértelmezett induló értéke: 0.
%
% pars                : [1x1 struct]
%                       A fizikai hardver (BESS + Inverter) fix paraméterei.
%                       Kritikus mezők a tervezőnek:
%                         - E_cap_nom      : Névleges akku kapacitás [kWh]
%                         - P_inv_limit_ac : A PV inverterek AC korlátja [kW] (pl. 550)
%                         - SoC_max / min  : Használható töltöttségi ablak (pl. 0.8 és 0.2)
%                         - inv_eta        : PV inverter hatásfoka (pl. 0.98)
%                         - eta_c / eta_d  : DC/DC konverter töltési/kisütési hatásfoka
%                         - eta_cell       : Akkumulátor cella kémiai hatásfoka
%
%
% 2. BELSŐ (SZÁMÍTOTT) VÁLTOZÓK A TERVEZŐBEN
% -------------------------------------------------------------------------
% eta_in / eta_out    : [Skalár double] 
%                       A hálózattól a celláig (és vissza) mért teljes Kerek-Út 
%                       (Round-Trip) hatásfok. Pl. 0.98 * 0.98 * 0.95 = 0.912.
%                       Dimenziónélküli szorzószám (0 és 1 között).
%
% cost_deg            : [Skalár double]
%                       1 kWh energia betárolásának és kitárolásának degradációs 
%                       költsége (amortizáció). Mértékegység: [HUF/kWh].
%
% P_pv_ac_forecast    : [1xN double sorvektor] [kW]
%                       A PV termelés azon része, ami a DC/AC átalakítás és az
%                       inverter AC limitjének vágása (clipping) UTÁN ténylegesen
%                       ki tud jutni a gyári AC hálózatra.
%
% P_net_forecast      : [1xN double sorvektor] [kW]
%                       A várható nettó hálózati terhelés (Fogyasztás - P_pv_ac).
%                       Ha pozitív: A gyár a hálózatról szívna áramot.
%                       Ha negatív: A napelem visszatáplálna a hálózatba.
%
% E_usable_ac         : [Skalár double] [kWh]
%                       A fizikailag AC oldalon kivehető maximális energia, 
%                       figyelembe véve az SoC korlátokat és a kitárolási veszteséget.
%
% P_limit_target      : [Skalár double] [kW]
%                       A Water-Filling (Vízfeltöltés) iterációs algoritmus belső 
%                       teszt-változója. Fentről (max csúcs) halad lefelé, amíg 
%                       az ehhez tartozó "E_req" el nem éri az akku kapacitását.
%
% Effective_Buy_Cost  : [1xN double sorvektor] [HUF/kWh]
%                       A hálózatról való töltés TÉNYLEGES költsége. Magában 
%                       foglalja az eredeti tőzsdei árat, a betöltési veszteséget
%                       (eta_in miatt több áramot kell venni), és a degradációt.
%
% Effective_Sell_Rev  : [1xN double sorvektor] [HUF/kWh]
%                       A hálózatra történő eladás TÉNYLEGES bevétele. Csökkentve
%                       a kitárolási veszteséggel (eta_out miatt kevesebb jut ki).
%
% peak_danger_mask    : [1xN logical sorvektor] (Igaz/Hamis)
%                       Biztonsági zóna. Igaz, ha az adott 5-perces blokkban a 
%                       várható hálózati terhelés túllépi a cél-limit 90%-át. 
%                       Ilyenkor szigorúan TILOS hálózatról (arbitrázs célból) tölteni.
%
%
% 3. KIMENETEK (A "plan" STRUKTÚRA)
% -------------------------------------------------------------------------
% plan.P_limit        : [Skalár double] [kW]
%                       A matematikai optimalizáció által kiszámolt (vagy a havi
%                       memória által kikényszerített) maximális engedélyezett 
%                       hálózati csúcs. A Valós Idejű Vezérlő ez alapján avatkozik be.
%
% plan.trade_buy_mask : [1xN logical sorvektor] (Igaz/Hamis)
%                       Időbeli maszk. Ahol "Igaz" (1), ott a Tervező anyagilag 
%                       profitábilisnak ítélte a hálózatról történő töltést, 
%                       és engedélyezi a Valós Idejű Vezérlőnek a Headroom kihasználását.
%
% plan.trade_sell_mask: [1xN logical sorvektor] (Igaz/Hamis)
%                       Időbeli maszk. Ahol "Igaz" (1), ott az EMS megpróbálja 
%                       a maximális inverter kapacitással a hálózatra tolni az
%                       akkumulátorban lévő (korábban olcsón megvett) energiát.
% =========================================================================