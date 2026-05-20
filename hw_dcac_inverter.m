% function [P_ac_kW, P_loss_kW, P_clip_kW] = hw_dcac_inverter(P_dc_kW, P_limit_ac_kW, eta_inv)
%     % HW_DCAC_INVERTER - Kétirányú DC/AC Inverter hardver modul
%     % Irány: Pozitív (+) = Inverting (Kifelé), Negatív (-) = Rectifying (Befelé)
% 
%     N = length(P_dc_kW);
%     P_ac_kW = zeros(1, N);
% 
%     mask_inv = P_dc_kW >= 0; 
%     mask_rec = P_dc_kW < 0;  
% 
%     % Ideális konverzió hatásfokkal
%     P_ac_ideal = zeros(1, N);
%     P_ac_ideal(mask_inv) = P_dc_kW(mask_inv) * eta_inv;
%     P_ac_ideal(mask_rec) = P_dc_kW(mask_rec) / eta_inv; 
% 
%     % Fizikai Hardver Vágás (Clipping) az AC oldalon
%     P_ac_kW(mask_inv) = min(P_ac_ideal(mask_inv), P_limit_ac_kW);
%     P_ac_kW(mask_rec) = max(P_ac_ideal(mask_rec), -P_limit_ac_kW);
% 
%     % Veszteségek számítása
%     P_loss_kW = abs(P_dc_kW) - abs(P_ac_kW); 
%     P_clip_kW = abs(P_ac_ideal) - abs(P_ac_kW); % Levágott, elveszett energia
% end

function [P_ac_kW, P_loss_kW, P_clip_kW] = hw_dcac_inverter(P_dc_kW, P_limit_ac_kW, eta_inv)
% HW_DCAC_INVERTER
%
% Ketiranyu DC/AC inverter modell.
%
% Jelkonvencio:
%   P_dc_kW > 0  -> DC busz -> AC oldal
%   P_dc_kW < 0  -> AC oldal -> DC busz
%
% Kimenetek:
%   P_ac_kW:
%       AC oldali teljesitmeny [kW]
%       pozitiv: AC oldalra betaplalt teljesitmeny
%       negativ: AC oldalrol felvett teljesitmeny
%
%   P_loss_kW:
%       Valodi konverzios hoveszteseg [kW].
%       Ez nem tartalmazza a clippinget.
%
%   P_clip_kW:
%       AC-ekvivalens levagott teljesitmeny [kW].
%       Ez kulon jelenik meg, nem keveredik bele az invertervesztesegbe.

    P_dc_kW = P_dc_kW(:).';

    N = numel(P_dc_kW);

    P_ac_kW = zeros(1, N);
    P_loss_kW = zeros(1, N);
    P_clip_kW = zeros(1, N);

    eta_inv = max(eta_inv, eps);

    mask_inv = P_dc_kW >= 0;
    mask_rec = P_dc_kW < 0;

    % =====================================================================
    % 1) DC -> AC irany
    % =====================================================================
    %
    % Ideal eset:
    %   P_ac_ideal = P_dc * eta
    %
    % Ha clipping van, akkor az inverter csak P_ac_actual-t ad ki.
    % A hoveszteseg csak a tenylegesen felhasznalt DC teljesitmeny es az
    % AC oldali kimenet kulonbsege.

    P_dc_inv = P_dc_kW(mask_inv);

    P_ac_ideal_inv = P_dc_inv .* eta_inv;
    P_ac_actual_inv = min(P_ac_ideal_inv, P_limit_ac_kW);

    P_ac_kW(mask_inv) = P_ac_actual_inv;

    P_dc_used_inv = P_ac_actual_inv ./ eta_inv;

    P_loss_kW(mask_inv) = max(P_dc_used_inv - P_ac_actual_inv, 0);
    P_clip_kW(mask_inv) = max(P_ac_ideal_inv - P_ac_actual_inv, 0);

    % =====================================================================
    % 2) AC -> DC irany
    % =====================================================================
    %
    % Itt P_dc_kW negativ: a DC busz oldalon ekkora negativ teljesitmenyt
    % szeretnenk eloallitani, vagyis BESS tolteshez DC oldali teljesitmeny
    % kell.
    %
    % Ideal eset:
    %   P_ac_ideal = P_dc / eta
    %
    % Mivel mindketto negativ, az AC oldali teljesitmeny abszolut erteke
    % nagyobb, mint a DC oldali hasznos teljesitmeny.

    P_dc_rec = P_dc_kW(mask_rec);

    P_ac_ideal_rec = P_dc_rec ./ eta_inv;
    P_ac_actual_rec = max(P_ac_ideal_rec, -P_limit_ac_kW);

    P_ac_kW(mask_rec) = P_ac_actual_rec;

    P_ac_used_rec = abs(P_ac_actual_rec);
    P_dc_delivered_rec = P_ac_used_rec .* eta_inv;

    P_loss_kW(mask_rec) = max(P_ac_used_rec - P_dc_delivered_rec, 0);
    P_clip_kW(mask_rec) = max(abs(P_ac_ideal_rec) - abs(P_ac_actual_rec), 0);
end