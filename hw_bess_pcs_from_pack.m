function [P_ac_actual_kW, P_loss_pcs_kW, P_clip_pcs_kW, eta_pcs_vec] = ...
    hw_bess_pcs_from_pack( ...
        P_pack_actual_kW, ...
        P_pcs_dis_limit_ac_kW, ...
        P_pcs_ch_limit_ac_kW, ...
        eta_nom, ...
        eff_load_points, ...
        eff_eta_points)
% HW_BESS_PCS_FROM_PACK
%
% Pack oldali tenyleges teljesitmenybol szamolja az AC oldali BESS
% teljesitmenyt AC-csatolt topologiaban.
%
% Jelkonvencio:
%   P_pack_actual_kW > 0  -> pack kisutes
%   P_pack_actual_kW < 0  -> pack toltes

    P_pack_actual_kW = P_pack_actual_kW(:).';

    P_pcs_rated_ac_kW = max(P_pcs_dis_limit_ac_kW, P_pcs_ch_limit_ac_kW);

    eta_pcs_vec = hw_efficiency_from_loading( ...
        P_pack_actual_kW, ...
        P_pcs_rated_ac_kW, ...
        eff_load_points, ...
        eff_eta_points);

    eta_safe = max(eta_pcs_vec, eps);

    P_ac_raw_kW = zeros(size(P_pack_actual_kW));
    P_loss_pcs_kW = zeros(size(P_pack_actual_kW));

    mask_dis = P_pack_actual_kW > 0;
    mask_ch  = P_pack_actual_kW < 0;

    % Kisutes:
    %   P_ac = P_pack * eta
    P_ac_raw_kW(mask_dis) = ...
        P_pack_actual_kW(mask_dis) .* eta_safe(mask_dis);

    P_loss_pcs_kW(mask_dis) = ...
        P_pack_actual_kW(mask_dis) - P_ac_raw_kW(mask_dis);

    % Toltes:
    %   P_pack = P_ac * eta
    %   P_ac = P_pack / eta
    P_ac_raw_kW(mask_ch) = ...
        P_pack_actual_kW(mask_ch) ./ eta_safe(mask_ch);

    P_loss_pcs_kW(mask_ch) = ...
        abs(P_ac_raw_kW(mask_ch)) - abs(P_pack_actual_kW(mask_ch));

    P_ac_actual_kW = min(P_ac_raw_kW,  P_pcs_dis_limit_ac_kW);
    P_ac_actual_kW = max(P_ac_actual_kW, -P_pcs_ch_limit_ac_kW);

    P_clip_pcs_kW = max(abs(P_ac_raw_kW) - abs(P_ac_actual_kW), 0);

    P_loss_pcs_kW = max(P_loss_pcs_kW, 0);

    zeroMask = abs(P_pack_actual_kW) < 1e-9;
    P_ac_actual_kW(zeroMask) = 0;
    P_loss_pcs_kW(zeroMask) = 0;
    P_clip_pcs_kW(zeroMask) = 0;
end