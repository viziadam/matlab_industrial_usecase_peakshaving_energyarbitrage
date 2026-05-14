function [step_res, state_bess] = ems_realtime_controller_dc(P_pv_dc, P_load_actual, Prices, plan, pars, state_bess, dt_h)
    % EMS_REALTIME_CONTROLLER_DC - Szigorú Fizikai és Pénzügyi Végrehajtó
    
    N = length(P_pv_dc);
    
    % --- 1. INVERTER AC CÉLÉRTÉKÉNEK (TARGET) KISZÁMÍTÁSA ---
    % Kiszámoljuk, mennyi energiának KELL átfolynia az inverteren a hálózat/gyár felé.
    
    % A) Alapvető PV önfogyasztás (Csak a fogyasztást fedezzük, amíg lehet)
    P_ac_from_pv = min(P_load_actual, P_pv_dc .* pars.inv_eta);
    
    % B) Csúcslevágási minimum (Ha a gyár átlépi a limitet, az inverternek KÖTELEZŐ tolnia)
    P_req_peak = P_load_actual - plan.P_limit;
    
    % Célérték a fenti kettő maximuma
    P_inv_ac_target = max(P_ac_from_pv, P_req_peak);
    
    % C) Arbitrázs VÉTEL (Headroom / Grid-Constrained Charging)
    % Cél: Szívjuk a hálózatot pontosan a büntetési limitig (P_limit).
    % Inverter AC cél = Fogyasztás - Limit (Ez negatív lesz, ha a fogyasztás kicsi!)
    P_inv_ac_target(plan.trade_buy_mask) = P_load_actual(plan.trade_buy_mask) - plan.P_limit;
    
    % D) Arbitrázs ELADÁS
    % Cél: Toljuk ki a maximumot a hálózatra.
    P_inv_ac_target(plan.trade_sell_mask) = pars.P_inv_limit_ac;
    
    % Inverter fizikai korlátok beállítása (Bidirectional limit)
    P_inv_ac_target = min(P_inv_ac_target, pars.P_inv_limit_ac);
    P_inv_ac_target = max(P_inv_ac_target, -pars.P_inv_limit_ac);

    % --- 2. DC SÍN MÉRLEG KISZÁMÍTÁSA ---
    % Mennyi DC teljesítmény kell az inverter AC céljának eléréséhez?
    P_inv_dc_req = zeros(1, N);
    inv_dis = P_inv_ac_target >= 0; % Kifelé (Inverting)
    inv_chg = P_inv_ac_target < 0;  % Befelé (Rectifying)
    
    P_inv_dc_req(inv_dis) = P_inv_ac_target(inv_dis) / pars.inv_eta;
    P_inv_dc_req(inv_chg) = P_inv_ac_target(inv_chg) * pars.inv_eta; % Ez negatív érték!
    
    % AZ AKKUMULÁTOR FELADATA A DC SÍN KIEGYENLÍTÉSE
    % Ha PV > Inverter igény, BESS_req negatív lesz (TÖLT). (Itt menti meg a Clippinget is!)
    % Ha Inverter igény > PV, BESS_req pozitív lesz (KISÜT).
    P_bess_dc_req = P_inv_dc_req - P_pv_dc;
    
    % Akku DC teljesítmény határai
    P_bess_dc_req = min(P_bess_dc_req, pars.P_dis_max);
    P_bess_dc_req = max(P_bess_dc_req, -pars.P_chg_max);

    % --- 3. HARDVER ÉS CELLAMODELL VÉGREHAJTÁS ---
    E_req_dc = P_bess_dc_req .* dt_h;
    
    mask_bess_chg = P_bess_dc_req < 0;
    mask_bess_dis = P_bess_dc_req > 0;
    
    % Konverter modellek a DC sínen
    conv_chg = dcdc_converter_model_vector(abs(E_req_dc .* mask_bess_chg), 'charge', pars.P_rated, dt_h);
    conv_dis = dcdc_converter_model_vector(E_req_dc .* mask_bess_dis, 'discharge', pars.P_rated, dt_h);
    
    E_cell_req = zeros(1, N);
    E_cell_req(mask_bess_chg) = conv_chg.E_out(mask_bess_chg);
    E_cell_req(mask_bess_dis) = -conv_dis.E_out(mask_bess_dis);
    
    % Akkumulátor mag hívása
    [bat, state_bess] = battery_core_model_vector(E_cell_req, 'mixed', pars, dt_h, state_bess);
    
    % Mennyit tudott *valójában* leadni/felvenni az akku a DC sínen?
    % (Ha tele van, vagy lemerült, a bat.E_stored / bat.E_discharged kisebb lesz a kértnél)
    conv_dis_actual = dcdc_converter_model_vector(bat.E_out, 'charge', pars.P_rated, dt_h);
    
    P_bess_dc_actual = zeros(1, N);
    % Visszaszámolás a ténylegesen végbement folyamatokból
    P_bess_dc_actual(mask_bess_chg) = -(bat.E_stored ./ dt_h) / pars.eta_c; 
    P_bess_dc_actual(mask_bess_dis) = (conv_dis_actual.E_out(mask_bess_dis) ./ dt_h);

    % --- 4. TÉNYLEGES HÁLÓZATI (AC) FIZIKA VISSZASZÁMOLÁSA ---
    % A DC sín végső állapota
    P_bus_dc_actual = P_pv_dc + P_bess_dc_actual;
    
    % Inverter végrehajtás a fizikai limiten (Clipping itt történik fizikailag)
    inv_actual_dis = P_bus_dc_actual >= 0;
    inv_actual_chg = P_bus_dc_actual < 0;
    
    P_inv_ac_actual = zeros(1, N);
    P_inv_ac_actual(inv_actual_dis) = min(P_bus_dc_actual(inv_actual_dis) .* pars.inv_eta, pars.P_inv_limit_ac);
    P_inv_ac_actual(inv_actual_chg) = max(P_bus_dc_actual(inv_actual_chg) ./ pars.inv_eta, -pars.P_inv_limit_ac);
    
    % A hálózati mérő által látott valós adatok
    P_grid_final = P_load_actual - P_inv_ac_actual;
    
    % --- 5. PÉNZÜGYI ÉS ENERGETIKAI KÖNYVELÉS ---
    step_res.E_pv_dc        = P_pv_dc .* dt_h;
    step_res.E_load         = P_load_actual .* dt_h;
    step_res.E_grid_import  = max(P_grid_final, 0) .* dt_h;
    step_res.E_grid_export  = abs(min(P_grid_final, 0)) .* dt_h;
    
    step_res.Cost_import_HUF = step_res.E_grid_import .* Prices.buy_huf;
    step_res.Rev_export_HUF  = step_res.E_grid_export .* Prices.sell_huf;
    
    step_res.E_stored       = bat.E_stored;
    step_res.E_discharged   = bat.E_discharged;
    step_res.E_bess_dc      = P_bess_dc_actual .* dt_h; % Könyveléshez DC érték
    
    step_res.E_block_cap    = bat.E_block_cap;
    step_res.E_block_power  = conv_chg.E_loss_conv_clipped + conv_dis.E_loss_conv_clipped;
    
    step_res.E_act          = bat.E_act;
    step_res.E_cap_eff      = bat.E_cap_eff;
end