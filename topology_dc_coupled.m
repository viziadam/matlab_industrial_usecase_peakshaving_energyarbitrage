function [step_res, state_bess] = topology_dc_coupled(P_bess_dc_req_kW, P_pv_dc_kW, P_load_kW, Prices, pars, state_bess, dt_h)
% TOPOLOGY_DC_COUPLED
% DC-csatolt PV+BESS topologia load-dependent central_inv es dcdc modellel.
%
% A fizikai mukodesi logika valtozatlan marad:
%   BESS pack <-> DC/DC <-> kozos DC busz <-> central inverter <-> AC busz
%
% A fajl explicit, topologia-szintu energiaaramlasi mezoket is visszaad,
% hogy a kiertekeles es a diagnosztika ne szarmaztasson kulonbozo modon
% azonos fizikai mennyisegeket.

    P_bess_dc_req_kW = P_bess_dc_req_kW(:).';
    P_pv_dc_kW = P_pv_dc_kW(:).';
    P_load_kW = P_load_kW(:).';

    N = numel(P_load_kW);

    if numel(P_bess_dc_req_kW) ~= N
        error('P_bess_dc_req_kW length differs from P_load_kW length.');
    end
    if numel(P_pv_dc_kW) ~= N
        error('P_pv_dc_kW length differs from P_load_kW length.');
    end
    if numel(Prices.buy_huf(:)) ~= N
        error('Prices.buy_huf length differs from P_load_kW length.');
    end
    if numel(Prices.sell_huf(:)) ~= N
        error('Prices.sell_huf length differs from P_load_kW length.');
    end

    requiredParsFields = { ...
        'P_inv_limit_ac', 'P_chg_max', 'P_dis_max', ...
        'central_inv_eta_nom', 'central_inv_eff_load_points', 'central_inv_eff_eta_points', ...
        'dcdc_eta_nom', 'dcdc_eff_load_points', 'dcdc_eff_eta_points'};

    for i = 1:numel(requiredParsFields)
        fieldName = requiredParsFields{i};
        if ~isfield(pars, fieldName)
            error('Missing pars field in DC topology: pars.%s', fieldName);
        end
    end

    P_bess_dc_req_original_kW = P_bess_dc_req_kW;
    P_bess_dc_req_limited_kW = P_bess_dc_req_kW;
    etaInvNom = max(pars.central_inv_eta_nom, eps);

    for t = 1:N
        if P_bess_dc_req_limited_kW(t) > 0
            pAvail = pars.P_inv_limit_ac / etaInvNom - P_pv_dc_kW(t);
            P_bess_dc_req_limited_kW(t) = min(P_bess_dc_req_limited_kW(t), max(pAvail, 0));
        elseif P_bess_dc_req_limited_kW(t) < 0
            pAvail = pars.P_inv_limit_ac * etaInvNom + P_pv_dc_kW(t);
            P_bess_dc_req_limited_kW(t) = max(P_bess_dc_req_limited_kW(t), -pAvail);
        end
    end

    P_bess_dc_req_kW = P_bess_dc_req_limited_kW;

    [P_pack_req_W, ~, eta_dcdc_req_vec] = hw_dcdc_converter( ...
        P_bess_dc_req_kW * 1000, ...
        pars.P_chg_max * 1000, ...
        pars.dcdc_eta_nom, ...
        pars.dcdc_eff_load_points, ...
        pars.dcdc_eff_eta_points);

    pack_params = struct();
    pack_params.T_vec = 25 * ones(1, N);
    if isfield(pars, 'T_vec')
        pack_params.T_vec = pars.T_vec(:).';
    end

    [pack_out, state_bess] = bess_pack_model(P_pack_req_W, 'run', pack_params, dt_h, state_bess);

    P_pack_actual_W = (pack_out.E_discharged - pack_out.E_stored) ./ dt_h;
    P_pack_actual_kW = P_pack_actual_W / 1000;

    P_bess_dc_actual_W = zeros(1, N);
    P_loss_dcdc_W = zeros(1, N);
    eta_dcdc_actual_vec = zeros(1, N);

    mask_chg = P_pack_actual_W < 0;
    mask_dis = P_pack_actual_W > 0;

    eta_dcdc_from_pack = hw_efficiency_from_loading( ...
        P_pack_actual_W ./ 1000, ...
        pars.P_chg_max, ...
        pars.dcdc_eff_load_points, ...
        pars.dcdc_eff_eta_points);
    eta_dcdc_from_pack = max(eta_dcdc_from_pack, eps);

    P_bess_dc_actual_W(mask_chg) = P_pack_actual_W(mask_chg) ./ eta_dcdc_from_pack(mask_chg);
    P_bess_dc_actual_W(mask_dis) = P_pack_actual_W(mask_dis) .* eta_dcdc_from_pack(mask_dis);

    P_loss_dcdc_W(mask_chg | mask_dis) = abs(P_bess_dc_actual_W(mask_chg | mask_dis) - P_pack_actual_W(mask_chg | mask_dis));
    eta_dcdc_actual_vec(mask_chg | mask_dis) = eta_dcdc_from_pack(mask_chg | mask_dis);

    P_bess_dc_actual_kW = P_bess_dc_actual_W / 1000;

    P_bus_dc_actual_kW = P_pv_dc_kW + P_bess_dc_actual_kW;

    [P_inv_ac_kW, P_loss_inv_kW, P_clip_kW, eta_inv_vec] = hw_dcac_inverter( ...
        P_bus_dc_actual_kW, ...
        pars.P_inv_limit_ac, ...
        pars.central_inv_eta_nom, ...
        pars.central_inv_eff_load_points, ...
        pars.central_inv_eff_eta_points);

    P_grid_net_kW = P_load_kW - P_inv_ac_kW;
    P_grid_import_kW = max(P_grid_net_kW, 0);
    P_grid_export_kW = max(-P_grid_net_kW, 0);

    [P_inv_ac_base_kW, ~, P_clip_base_kW, eta_inv_base_vec] = hw_dcac_inverter( ...
        P_pv_dc_kW, ...
        pars.P_inv_limit_ac, ...
        pars.central_inv_eta_nom, ...
        pars.central_inv_eff_load_points, ...
        pars.central_inv_eff_eta_points);

    P_grid_base_kW = P_load_kW - P_inv_ac_base_kW;
    P_grid_import_base_kW = max(P_grid_base_kW, 0);
    P_grid_export_base_kW = max(-P_grid_base_kW, 0);

     % =====================================================================
    % Explicit topology-level canonical energy-flow attribution
    % =====================================================================
    P_dcdc_loss_kW = P_loss_dcdc_W ./ 1000;

    P_bess_charge_dc_bus_kW = max(-P_bess_dc_actual_kW, 0);
    P_bess_discharge_dc_bus_kW = max(P_bess_dc_actual_kW, 0);

    P_bess_charge_pack_terminal_kW = max(-P_pack_actual_kW, 0);
    P_bess_discharge_pack_terminal_kW = max(P_pack_actual_kW, 0);

    P_bess_charge_pack_kW = P_bess_charge_pack_terminal_kW;
    P_bess_discharge_pack_kW = P_bess_discharge_pack_terminal_kW;

    P_bess_internal_loss_kW = ...
        (pack_out.E_loss_joule + pack_out.E_loss_sat + pack_out.E_loss_empty) ./ ...
        1000 ./ dt_h;

    P_bess_internal_charge_loss_kW = zeros(1, N);
    P_bess_internal_discharge_loss_kW = zeros(1, N);

    chargePackMask = P_pack_actual_kW < -1e-9;
    dischargePackMask = P_pack_actual_kW > 1e-9;

    P_bess_internal_charge_loss_kW(chargePackMask) = ...
        P_bess_internal_loss_kW(chargePackMask);

    P_bess_internal_discharge_loss_kW(dischargePackMask) = ...
        P_bess_internal_loss_kW(dischargePackMask);

    P_bess_charge_stored_after_internal_kW = max( ...
        P_bess_charge_pack_terminal_kW - P_bess_internal_charge_loss_kW, ...
        0);

    % ---------------------------------------------------------------------
    % Central inverter AC output allocation
    % ---------------------------------------------------------------------
    P_inv_ac_positive_kW = max(P_inv_ac_kW, 0);
    P_inv_ac_rectifier_kW = max(-P_inv_ac_kW, 0);

    P_central_loss_to_ac_kW = zeros(1, N);
    positiveInvMask = P_bus_dc_actual_kW > 1e-9;

    P_central_loss_to_ac_kW(positiveInvMask) = ...
        P_loss_inv_kW(positiveInvMask);

    P_dc_used_by_ac_kW = ...
        P_inv_ac_positive_kW + P_central_loss_to_ac_kW;

    P_dc_used_by_ac_kW = min( ...
        P_dc_used_by_ac_kW, ...
        max(P_bus_dc_actual_kW, 0));

    P_pv_to_inverter_dc_kW = min(P_pv_dc_kW, P_dc_used_by_ac_kW);

    P_remaining_dc_used_by_ac_kW = max( ...
        P_dc_used_by_ac_kW - P_pv_to_inverter_dc_kW, ...
        0);

    P_bess_to_inverter_dc_kW = min( ...
        P_bess_discharge_dc_bus_kW, ...
        P_remaining_dc_used_by_ac_kW);

    P_total_to_inverter_dc_kW = ...
        P_pv_to_inverter_dc_kW + P_bess_to_inverter_dc_kW;

    invSourceDen = max(P_total_to_inverter_dc_kW, eps);

    pvInvShare = P_pv_to_inverter_dc_kW ./ invSourceDen;
    bessInvShare = P_bess_to_inverter_dc_kW ./ invSourceDen;

    noInvSourceMask = P_total_to_inverter_dc_kW <= 1e-9;
    pvInvShare(noInvSourceMask) = 0;
    bessInvShare(noInvSourceMask) = 0;

    P_pv_ac_direct_kW = P_inv_ac_positive_kW .* pvInvShare;
    P_bess_ac_after_conversion_kW = P_inv_ac_positive_kW .* bessInvShare;

    P_pv_to_load_direct_kW = min(P_pv_ac_direct_kW, P_load_kW);

    remainingLoadAfterPv_kW = max( ...
        P_load_kW - P_pv_to_load_direct_kW, ...
        0);

    P_bess_to_load_kW = min( ...
        P_bess_ac_after_conversion_kW, ...
        remainingLoadAfterPv_kW);

    remainingLoadAfterBess_kW = max( ...
        P_load_kW - P_pv_to_load_direct_kW - P_bess_to_load_kW, ...
        0);

    P_grid_to_load_kW = remainingLoadAfterBess_kW;

    % ---------------------------------------------------------------------
    % Charge direction
    %
    % PV -> BESS:
    %   PV DC -> DC/DC -> pack terminal -> internal cell loss -> stored
    %
    % Grid -> BESS:
    %   grid AC -> central inverter rectifier -> DC bus -> DC/DC ->
    %   pack terminal -> internal cell loss -> stored
    % ---------------------------------------------------------------------
    P_pv_remaining_after_inverter_kW = max( ...
        P_pv_dc_kW - P_pv_to_inverter_dc_kW, ...
        0);

    P_pv_to_bess_kW = min( ...
        P_pv_remaining_after_inverter_kW, ...
        P_bess_charge_dc_bus_kW);

    P_grid_to_bess_after_central_kW = max( ...
        P_bess_charge_dc_bus_kW - P_pv_to_bess_kW, ...
        0);

    P_grid_to_bess_kW = zeros(1, N);

    rectifierMask = P_grid_to_bess_after_central_kW > 1e-9;

    P_grid_to_bess_kW(rectifierMask) = ...
        P_grid_to_bess_after_central_kW(rectifierMask) + ...
        P_loss_inv_kW(rectifierMask);

    P_grid_to_bess_kW = max(P_grid_to_bess_kW, P_inv_ac_rectifier_kW);

    P_central_loss_grid_to_bess_kW = max( ...
        P_grid_to_bess_kW - P_grid_to_bess_after_central_kW, ...
        0);

    chargeDen = max(P_bess_charge_dc_bus_kW, eps);

    pvChargeShare = P_pv_to_bess_kW ./ chargeDen;
    gridChargeShare = P_grid_to_bess_after_central_kW ./ chargeDen;

    noChargeMask = P_bess_charge_dc_bus_kW <= 1e-9;
    pvChargeShare(noChargeMask) = 0;
    gridChargeShare(noChargeMask) = 0;

    P_dcdc_charge_loss_kW = zeros(1, N);
    P_dcdc_charge_loss_kW(noChargeMask == false) = ...
        P_dcdc_loss_kW(noChargeMask == false);

    P_pv_to_bess_loss_kW = ...
        pvChargeShare .* ...
        (P_dcdc_charge_loss_kW + P_bess_internal_charge_loss_kW);

    P_grid_to_bess_loss_kW = ...
        P_central_loss_grid_to_bess_kW + ...
        gridChargeShare .* ...
        (P_dcdc_charge_loss_kW + P_bess_internal_charge_loss_kW);

    P_pv_to_bess_stored_kW = ...
        pvChargeShare .* P_bess_charge_stored_after_internal_kW;

    P_grid_to_bess_stored_kW = ...
        gridChargeShare .* P_bess_charge_stored_after_internal_kW;

    % ---------------------------------------------------------------------
    % Discharge direction
    %
    % BESS -> load:
    %   stored/pack -> internal cell loss -> DC/DC -> central inverter ->
    %   AC load
    %
    % The output metric bessToLoadConversionLoss remains external
    % converter loss only. Internal battery loss is kept separately in
    % bessInternalLoss.
    % ---------------------------------------------------------------------
    P_bess_discharge_before_conversion_kW = P_bess_discharge_pack_terminal_kW;

    P_dcdc_discharge_loss_kW = zeros(1, N);
    dischargeMask = P_bess_discharge_dc_bus_kW > 1e-9;

    P_dcdc_discharge_loss_kW(dischargeMask) = ...
        P_dcdc_loss_kW(dischargeMask);

    P_central_loss_bess_to_ac_kW = ...
        P_central_loss_to_ac_kW .* bessInvShare;

    P_bess_discharge_external_loss_kW = ...
        P_dcdc_discharge_loss_kW + P_central_loss_bess_to_ac_kW;

    bessAcDen = max(P_bess_ac_after_conversion_kW, eps);

    bessToLoadShare = P_bess_to_load_kW ./ bessAcDen;
    bessToLoadShare(P_bess_ac_after_conversion_kW <= 1e-9) = 0;

    P_bess_to_load_conversion_loss_kW = ...
        bessToLoadShare .* P_bess_discharge_external_loss_kW;

    P_grid_import_total_kW = P_grid_import_kW;

    buy_huf = Prices.buy_huf(:).';

    C_grid_to_bess_import_HUF = ...
        P_grid_to_bess_kW .* dt_h .* buy_huf;

    C_grid_to_bess_stored_import_equiv_HUF = ...
        P_grid_to_bess_stored_kW .* dt_h .* buy_huf;

    C_bess_stored_import_equiv_HUF = ...
        P_bess_charge_pack_kW .* dt_h .* buy_huf;

    C_bess_discharge_before_conversion_import_equiv_HUF = ...
        P_bess_discharge_before_conversion_kW .* dt_h .* buy_huf;

    C_bess_to_load_import_equiv_HUF = ...
        P_bess_to_load_kW .* dt_h .* buy_huf;

    step_res = struct();
    step_res.E_pv_dc = P_pv_dc_kW .* dt_h;
    step_res.E_load = P_load_kW .* dt_h;
    step_res.E_grid_import = P_grid_import_kW .* dt_h;
    step_res.E_grid_export = P_grid_export_kW .* dt_h;
    step_res.E_stored = pack_out.E_stored / 1000;
    step_res.E_discharged = pack_out.E_discharged / 1000;
    step_res.E_bess_dc = P_bess_dc_actual_kW .* dt_h;
    step_res.E_loss_joule = pack_out.E_loss_joule / 1000;
    step_res.E_loss_dcdc = (P_loss_dcdc_W / 1000) .* dt_h;
    step_res.E_loss_inv = P_loss_inv_kW .* dt_h;
    step_res.E_loss_central_inv = P_loss_inv_kW .* dt_h;
    step_res.E_loss_pcsb_inv = zeros(1, N);
    step_res.E_clip_inv = P_clip_kW .* dt_h;
    step_res.E_curtailment = step_res.E_clip_inv;
    step_res.E_clip_base = P_clip_base_kW .* dt_h;
    step_res.E_grid_import_base = P_grid_import_base_kW .* dt_h;
    step_res.E_grid_export_base = P_grid_export_base_kW .* dt_h;

    step_res.Cost_import_HUF = step_res.E_grid_import .* Prices.buy_huf(:).';
    step_res.Rev_export_HUF = step_res.E_grid_export .* Prices.sell_huf(:).';
    step_res.Cost_import_base_HUF = step_res.E_grid_import_base .* Prices.buy_huf(:).';

    step_res.P_grid_net_kW = P_grid_net_kW(:);
    step_res.P_grid_import_kW = P_grid_import_kW(:);
    step_res.P_grid_export_kW = P_grid_export_kW(:);

    step_res.P_pv_to_bess_kW = P_pv_to_bess_kW(:);
    step_res.P_grid_to_bess_kW = P_grid_to_bess_kW(:);
    step_res.P_pv_to_bess_stored_kW = P_pv_to_bess_stored_kW(:);
    step_res.P_grid_to_bess_stored_kW = P_grid_to_bess_stored_kW(:);
    step_res.P_pv_to_bess_loss_kW = P_pv_to_bess_loss_kW(:);
    step_res.P_grid_to_bess_loss_kW = P_grid_to_bess_loss_kW(:);
    step_res.P_bess_discharge_before_conversion_kW = P_bess_discharge_before_conversion_kW(:);
    step_res.P_bess_to_load_kW = P_bess_to_load_kW(:);
    step_res.P_bess_to_load_conversion_loss_kW = P_bess_to_load_conversion_loss_kW(:);
    step_res.P_pv_to_load_direct_kW = P_pv_to_load_direct_kW(:);
    step_res.P_grid_to_load_kW = P_grid_to_load_kW(:);
    step_res.P_grid_import_total_kW = P_grid_import_total_kW(:);

    step_res.C_grid_to_bess_import_HUF = C_grid_to_bess_import_HUF(:);
    step_res.C_grid_to_bess_stored_import_equiv_HUF = C_grid_to_bess_stored_import_equiv_HUF(:);
    step_res.C_bess_stored_import_equiv_HUF = C_bess_stored_import_equiv_HUF(:);
    step_res.C_bess_discharge_before_conversion_import_equiv_HUF = C_bess_discharge_before_conversion_import_equiv_HUF(:);
    step_res.C_bess_to_load_import_equiv_HUF = C_bess_to_load_import_equiv_HUF(:);

    step_res.P_bess_actual_kW = P_bess_dc_actual_kW(:);
    step_res.P_bess_dc_actual_kW = P_bess_dc_actual_kW(:);
    step_res.P_pack_actual_kW = P_pack_actual_kW(:);
    step_res.P_inv_ac_kW = P_inv_ac_kW(:);
    step_res.P_pv_ac_kW = P_inv_ac_kW(:);
    step_res.P_pv_ac_base_kW = P_inv_ac_base_kW(:);
    step_res.P_spill_kW = P_clip_kW(:);
    step_res.P_curtailment_kW = P_clip_kW(:);
    step_res.P_bess_dc_req_kW = P_bess_dc_req_original_kW(:);
    step_res.P_bess_dc_req_limited_kW = P_bess_dc_req_limited_kW(:);

    step_res.P_loss_inv_kW = P_loss_inv_kW(:);
    step_res.P_loss_central_inv_kW = P_loss_inv_kW(:);
    step_res.P_loss_pcsb_inv_kW = zeros(N, 1);
    step_res.P_loss_dcdc_kW = P_loss_dcdc_W(:) / 1000;
    step_res.P_loss_bess_internal_kW = P_bess_internal_loss_kW(:);

    % ---------------------------------------------------------------------
    % Converter loss split for diagnostics
    % ---------------------------------------------------------------------
    step_res.P_loss_central_inv_dc_to_ac_kW = P_central_loss_to_ac_kW(:);
    step_res.P_loss_central_inv_ac_to_dc_kW = P_central_loss_grid_to_bess_kW(:);

    step_res.P_loss_dcdc_charge_kW = P_dcdc_charge_loss_kW(:);
    step_res.P_loss_dcdc_discharge_kW = P_dcdc_discharge_loss_kW(:);

    step_res.P_loss_pcsb_charge_kW = zeros(N, 1);
    step_res.P_loss_pcsb_discharge_kW = zeros(N, 1);

    step_res.P_loss_bess_internal_charge_kW = P_bess_internal_charge_loss_kW(:);
    step_res.P_loss_bess_internal_discharge_kW = P_bess_internal_discharge_loss_kW(:);
    step_res.eta_central_inv = eta_inv_vec(:);
    step_res.eta_central_inv_base = eta_inv_base_vec(:);
    step_res.eta_dcdc_req = eta_dcdc_req_vec(:);
    step_res.eta_dcdc_actual = eta_dcdc_actual_vec(:);

    step_res.SoC = pack_out.SOC(:);
    step_res.SoH = pack_out.SOH(:);
    step_res.SOC_end = pack_out.SOC(end);
    step_res.SOH_end = pack_out.SOH(end);
    step_res.T_cell_max = max(pack_out.T_cell);
end
