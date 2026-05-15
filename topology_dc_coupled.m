function [step_res, state_bess] = topology_dc_coupled(P_bess_dc_req_kW, P_pv_dc_kW, P_load_kW, Prices, pars, state_bess, dt_h)
    % TOPOLOGY_DC_COUPLED - DC-csatolt rendszer fizikai kábelezése
    % Ez a modul szimulálja a hardverek tényleges viselkedését, veszteségeit
    % és a DC/AC sín áramlásait az EMS kérése alapján.

    N = length(P_pv_dc_kW);

    % --- 1. KOMPONENS: DC/DC Konverter (Lefelé az akkuhoz) ---
    % Az EMS kérését [kW] átküldjük a konverteren.
    % A konverterből kijövő, ténylegesen a cellákra jutó teljesítményt [W]-ban kapjuk.
    [P_pack_req_W, ~] = hw_dcdc_converter(P_bess_dc_req_kW * 1000, pars.P_chg_max * 1000, pars.eta_c, pars.eta_d);

    % --- 2. KOMPONENS: Akkumulátor Csomag (BESS Pack) ---
    % Meghívjuk a te részletes (Bolun Xu) cellamodeledet
    pack_params = struct('T_vec', 25 * ones(1, N));
    if isfield(pars, 'T_vec'), pack_params.T_vec = pars.T_vec; end

    [pack_out, state_bess] = bess_pack_model(P_pack_req_W, 'run', pack_params, dt_h, state_bess);

    % Kiszámoljuk a ténylegesen leadott/felvett akku teljesítményt [W]-ban
    P_pack_actual_W = (pack_out.E_discharged - pack_out.E_stored) ./ dt_h;

    % --- 3. KOMPONENS: DC/DC Konverter (Felfelé a DC Sínre) ---
    % Visszafejtjük, hogy a valós akku válasz mit jelent a DC sínen terhelésként.
    % Mivel lentről (Akku) megyünk felfelé (DC Sín), az inverz hatásfokokkal hívjuk:
    [P_bess_dc_actual_W, P_loss_dcdc_W] = hw_dcdc_converter(P_pack_actual_W, pars.P_chg_max * 1000, 1/pars.eta_c, 1/pars.eta_d);
    P_bess_dc_actual_kW = P_bess_dc_actual_W / 1000;

    % --- 4. CSOMÓPONT: A Közös DC Sín (DC Bus) ---
    % Itt találkozik a nyers napelem és a tényleges akku egyenáram
    P_bus_dc_actual_kW = P_pv_dc_kW + P_bess_dc_actual_kW;

    % --- 5. KOMPONENS: Fő Inverter (DC/AC) ---
    % A DC sínt rákötjük a hálózatra. Itt történik a fizikai Clipping!
    [P_inv_ac_kW, P_loss_inv_kW, P_clip_kW] = hw_dcac_inverter(P_bus_dc_actual_kW, pars.P_inv_limit_ac, pars.inv_eta);

    % --- 6. CSOMÓPONT: Az AC Hálózat Mérlege ---
    % --- 6. CSOMÓPONT: Az AC Hálózat Mérlege ---
    % A gyár fogyasztását levonjuk abból, amit az inverter AC oldalon betáplál
    P_grid_final_kW = P_load_kW - P_inv_ac_kW;
    
    % --- BASELINE (AKKU NÉLKÜLI) FIZIKA ---
    % Mi történt volna, ha a PV közvetlenül az inverterre megy BESS nélkül?
    P_inv_ac_base = min(P_pv_dc_kW .* pars.inv_eta, pars.P_inv_limit_ac);
    P_grid_base_kW = P_load_kW - P_inv_ac_base;

    % =====================================================================
    % --- 7. KÖNYVELÉS (CSAK NYERS, ALAPVETŐ ADATOK) ---
    % =====================================================================
    step_res = struct();
    
    % =====================================================================
    % Egységes actual teljesítménymezők plothoz / diagnosztikához
    % =====================================================================
    P_grid_net_kW    = P_grid_final_kW;
    P_grid_import_kW = max(P_grid_net_kW, 0);
    P_grid_export_kW = max(-P_grid_net_kW, 0);

    step_res.P_grid_net_kW = P_grid_net_kW(:);
    step_res.P_grid_import_kW = P_grid_import_kW(:);
    step_res.P_grid_export_kW = P_grid_export_kW(:);

    % DC topológiában a BESS tényleges teljesítménye a DC busz oldali érték.
    step_res.P_bess_actual_kW = P_bess_dc_actual_kW(:);
    step_res.P_bess_dc_actual_kW = P_bess_dc_actual_kW(:);

    % A DC rendszerben nincs külön PV AC ág, mert PV+BESS közös DC buszról
    % megy a fő inverterre. Plothoz a tényleges inverter AC kimenetet mentjük.
    step_res.P_inv_ac_kW = P_inv_ac_kW(:);

    % Baseline PV inverter AC kimenet, BESS nélkül.
    step_res.P_pv_ac_base_kW = P_inv_ac_base(:);

    % Kompatibilis név: DC esetben ez nem tiszta PV ág,
    % hanem a fő inverter tényleges AC kimenete.
    step_res.P_pv_ac_kW = P_inv_ac_kW(:);

    % DC esetben a tényleges "spill"/curtailment az inverter clipping.
    step_res.P_spill_kW = P_clip_kW(:);

    % 7.6. Belső Állapotok (Nap végi profilokhoz / mentéshez)
    step_res.SoC            = pack_out.SOC(:);
    step_res.SoH            = pack_out.SOH(:);
    step_res.SOC_end        = pack_out.SOC(end);
    step_res.SOH_end        = pack_out.SOH(end);
    step_res.T_cell_max     = max(pack_out.T_cell);
end