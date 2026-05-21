function [P_ac_actual_kW, P_pack_req_kW, P_loss_pcs_kW, P_clip_pcs_kW, eta_pcs_vec] = ...
    hw_bess_pcs_inverter( ...
        P_ac_req_kW, ...
        P_pcs_dis_limit_ac_kW, ...
        P_pcs_ch_limit_ac_kW, ...
        eta_nom, ...
        eff_load_points, ...
        eff_eta_points)
% HW_BESS_PCS_INVERTER
%
% Ketiranyu BESS PCS / battery inverter AC-csatolt topologiahoz.
%
% Jelkonvencio:
%   P_ac_req_kW > 0  -> BESS kisutes az AC buszra
%   P_ac_req_kW < 0  -> BESS toltes az AC buszrol
%
% Kimenetek:
%   P_ac_actual_kW:
%       tenyleges AC oldali BESS teljesitmeny [kW]
%
%   P_pack_req_kW:
%       pack oldali teljesitmenykeres [kW]
%       pozitiv: pack kisutes
%       negativ: pack toltes
%
%   P_loss_pcs_kW:
%       PCS konverzios veszteseg [kW]
%
%   P_clip_pcs_kW:
%       PCS teljesitmenykorlat miatt nem teljesitett AC oldali teljesitmeny [kW]
%
%   eta_pcs_vec:
%       idolepesenkenti PCS hatasfok [-]

    P_ac_req_kW = P_ac_req_kW(:).';

    if P_pcs_dis_limit_ac_kW <= 0
        error('P_pcs_dis_limit_ac_kW must be positive.');
    end

    if P_pcs_ch_limit_ac_kW <= 0
        error('P_pcs_ch_limit_ac_kW must be positive.');
    end

    P_ac_actual_kW = min(P_ac_req_kW,  P_pcs_dis_limit_ac_kW);
    P_ac_actual_kW = max(P_ac_actual_kW, -P_pcs_ch_limit_ac_kW);

    P_clip_pcs_kW = max(abs(P_ac_req_kW) - abs(P_ac_actual_kW), 0);

    P_pcs_rated_ac_kW = max(P_pcs_dis_limit_ac_kW, P_pcs_ch_limit_ac_kW);

    eta_pcs_vec = hw_efficiency_from_loading( ...
        P_ac_actual_kW, ...
        P_pcs_rated_ac_kW, ...
        eff_load_points, ...
        eff_eta_points);

    eta_safe = max(eta_pcs_vec, eps);

    P_pack_req_kW = zeros(size(P_ac_actual_kW));
    P_loss_pcs_kW = zeros(size(P_ac_actual_kW));

    mask_dis = P_ac_actual_kW > 0;
    mask_ch  = P_ac_actual_kW < 0;

    % Kisutes:
    %   pack -> PCS -> AC busz
    %   P_ac = P_pack * eta
    P_pack_req_kW(mask_dis) = ...
        P_ac_actual_kW(mask_dis) ./ eta_safe(mask_dis);

    P_loss_pcs_kW(mask_dis) = ...
        P_pack_req_kW(mask_dis) - P_ac_actual_kW(mask_dis);

    % Toltes:
    %   AC busz -> PCS -> pack
    %   P_pack = P_ac * eta
    % Mindketto negativ.
    P_pack_req_kW(mask_ch) = ...
        P_ac_actual_kW(mask_ch) .* eta_safe(mask_ch);

    P_loss_pcs_kW(mask_ch) = ...
        abs(P_ac_actual_kW(mask_ch)) - abs(P_pack_req_kW(mask_ch));

    P_loss_pcs_kW = max(P_loss_pcs_kW, 0);

    zeroMask = abs(P_ac_actual_kW) < 1e-9;
    P_pack_req_kW(zeroMask) = 0;
    P_loss_pcs_kW(zeroMask) = 0;
end