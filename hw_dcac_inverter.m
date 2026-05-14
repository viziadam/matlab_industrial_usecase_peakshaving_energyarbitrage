function [P_ac_kW, P_loss_kW, P_clip_kW] = hw_dcac_inverter(P_dc_kW, P_limit_ac_kW, eta_inv)
    % HW_DCAC_INVERTER - Kétirányú DC/AC Inverter hardver modul
    % Irány: Pozitív (+) = Inverting (Kifelé), Negatív (-) = Rectifying (Befelé)
    
    N = length(P_dc_kW);
    P_ac_kW = zeros(1, N);
    
    mask_inv = P_dc_kW >= 0; 
    mask_rec = P_dc_kW < 0;  
    
    % Ideális konverzió hatásfokkal
    P_ac_ideal = zeros(1, N);
    P_ac_ideal(mask_inv) = P_dc_kW(mask_inv) * eta_inv;
    P_ac_ideal(mask_rec) = P_dc_kW(mask_rec) / eta_inv; 
    
    % Fizikai Hardver Vágás (Clipping) az AC oldalon
    P_ac_kW(mask_inv) = min(P_ac_ideal(mask_inv), P_limit_ac_kW);
    P_ac_kW(mask_rec) = max(P_ac_ideal(mask_rec), -P_limit_ac_kW);
    
    % Veszteségek számítása
    P_loss_kW = abs(P_dc_kW) - abs(P_ac_kW); 
    P_clip_kW = abs(P_ac_ideal) - abs(P_ac_kW); % Levágott, elveszett energia
end