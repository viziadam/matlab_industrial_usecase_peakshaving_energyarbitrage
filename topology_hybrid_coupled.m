function [step_res, state_hybrid] = topology_hybrid_coupled( ...
    req, ...
    P_pv_dc_kW, ...
    P_load_kW, ...
    Prices, ...
    pars, ...
    state_hybrid, ...
    dt_h)
% TOPOLOGY_HYBRID_COUPLED
%
% Hybrid PV+BESS topologia ket kulon energiatároloval:
%   - DC BESS: pack <-> DC/DC <-> kozos DC busz
%   - AC BESS: pack <-> PCSB <-> AC busz
%
% A PV es a DC BESS kozos central_inv konverteren keresztul kapcsolodik
% az AC buszhoz. Az AC BESS kulon PCSB-n keresztul kapcsolodik.
%
% A fizikai mukodesi logika valtozatlan marad. A fajl explicit,
% topologia-szintu energiaaramlasi mezoket is visszaad az egyseges
% kiertekeleshez.

    P_pv_dc_kW = P_pv_dc_kW(:).';
    P_load_kW = P_load_kW(:).';

    N = numel(P_load_kW);

    if ~isfield(req, 'P_bess_dc_req_kW') || ~isfield(req, 'P_bess_ac_req_kW')
        error('Hybrid topology requires req.P_bess_dc_req_kW and req.P_bess_ac_req_kW.');
    end

    P_bess_dc_req_kW = req.P_bess_dc_req_kW(:).';
    P_bess_ac_req_kW = req.P_bess_ac_req_kW(:).';

    if numel(P_pv_dc_kW) ~= N || numel(P_bess_dc_req_kW) ~= N || numel(P_bess_ac_req_kW) ~= N
        error('Hybrid topology input vector length mismatch.');
    end

    if ~isfield(state_hybrid, 'dc') || ~isfield(state_hybrid, 'ac')
        error('state_hybrid must contain .dc and .ac BESS states.');
    end

    % =====================================================================
    % 1) DC BESS request -> DC/DC -> DC pack request
    % =====================================================================
    [P_pack_req_dc_W, ~, eta_dcdc_req_vec] = hw_dcdc_converter( ...
        P_bess_dc_req_kW * 1000, ...
        pars.dc.P_chg_max * 1000, ...
        pars.dcdc_eta_nom, ...
        pars.dcdc_eff_load_points, ...
        pars.dcdc_eff_eta_points);

    pack_params_dc = struct();
    pack_params_dc.T_vec = 25 * ones(1, N);

    [pack_out_dc, state_hybrid.dc] = bess_pack_model( ...
        P_pack_req_dc_W, ...
        'run', ...
        pack_params_dc, ...
        dt_h, ...
        state_hybrid.dc);

    P_pack_actual_dc_W = ...
        (pack_out_dc.E_discharged - pack_out_dc.E_stored) ./ dt_h;

    eta_dcdc_from_pack = hw_efficiency_from_loading( ...
        P_pack_actual_dc_W ./ 1000, ...
        pars.dc.P_chg_max, ...
        pars.dcdc_eff_load_points, ...
        pars.dcdc_eff_eta_points);

    eta_dcdc_from_pack = max(eta_dcdc_from_pack, eps);

    P_bess_dc_actual_W = zeros(1, N);
    P_loss_dcdc_W = zeros(1, N);

    mask_chg_dc = P_pack_actual_dc_W < 0;
    mask_dis_dc = P_pack_actual_dc_W > 0;

    P_bess_dc_actual_W(mask_chg_dc) = ...
        P_pack_actual_dc_W(mask_chg_dc) ./ eta_dcdc_from_pack(mask_chg_dc);

    P_bess_dc_actual_W(mask_dis_dc) = ...
        P_pack_actual_dc_W(mask_dis_dc) .* eta_dcdc_from_pack(mask_dis_dc);

    P_loss_dcdc_W(mask_chg_dc | mask_dis_dc) = abs( ...
        P_bess_dc_actual_W(mask_chg_dc | mask_dis_dc) - ...
        P_pack_actual_dc_W(mask_chg_dc | mask_dis_dc));

    P_bess_dc_actual_kW = P_bess_dc_actual_W ./ 1000;
    P_pack_actual_dc_kW = P_pack_actual_dc_W ./ 1000;

    % =====================================================================
    % 2) Central inverter: PV DC + DC BESS DC bus -> AC bus
    % =====================================================================
    P_bus_dc_actual_kW = P_pv_dc_kW + P_bess_dc_actual_kW;

    [P_central_ac_kW, P_loss_central_inv_kW, P_clip_central_kW, eta_central_vec] = ...
        hw_dcac_inverter( ...
            P_bus_dc_actual_kW, ...
            pars.P_inv_limit_ac, ...
            pars.central_inv_eta_nom, ...
            pars.central_inv_eff_load_points, ...
            pars.central_inv_eff_eta_points);

    [P_pv_ac_base_kW, P_loss_pv_base_kW, P_clip_base_kW, eta_central_base_vec] = ...
        hw_dcac_inverter( ...
            P_pv_dc_kW, ...
            pars.P_inv_limit_ac, ...
            pars.central_inv_eta_nom, ...
            pars.central_inv_eff_load_points, ...
            pars.central_inv_eff_eta_points);

    % =====================================================================
    % 3) AC BESS request -> PCSB -> AC pack request
    % =====================================================================
    etaPcsNom = max(pars.pcs_eta_nom, eps);
    P_pcs_dis_limit_ac_kW = pars.ac.P_dis_max * etaPcsNom;
    P_pcs_ch_limit_ac_kW  = pars.ac.P_chg_max / etaPcsNom;

    [ ...
        P_bess_ac_req_limited_kW, ...
        P_pack_req_ac_kW, ...
        P_loss_pcs_req_kW, ...
        P_clip_pcs_req_kW, ...
        eta_pcs_req_vec] = hw_bess_pcs_inverter( ...
            P_bess_ac_req_kW, ...
            P_pcs_dis_limit_ac_kW, ...
            P_pcs_ch_limit_ac_kW, ...
            pars.pcs_eta_nom, ...
            pars.pcs_eff_load_points, ...
            pars.pcs_eff_eta_points);

    pack_params_ac = struct();
    pack_params_ac.T_vec = 25 * ones(1, N);

    [pack_out_ac, state_hybrid.ac] = bess_pack_model( ...
        P_pack_req_ac_kW * 1000, ...
        'run', ...
        pack_params_ac, ...
        dt_h, ...
        state_hybrid.ac);

    P_pack_actual_ac_W = ...
        (pack_out_ac.E_discharged - pack_out_ac.E_stored) ./ dt_h;

    P_pack_actual_ac_kW = P_pack_actual_ac_W ./ 1000;

    [ ...
        P_bess_ac_actual_kW, ...
        P_loss_pcs_actual_kW, ...
        P_clip_pcs_actual_kW, ...
        eta_pcs_actual_vec] = hw_bess_pcs_from_pack( ...
            P_pack_actual_ac_kW, ...
            P_pcs_dis_limit_ac_kW, ...
            P_pcs_ch_limit_ac_kW, ...
            pars.pcs_eta_nom, ...
            pars.pcs_eff_load_points, ...
            pars.pcs_eff_eta_points);

    % =====================================================================
    % 4) AC bus / grid balance
    % =====================================================================
    P_grid_net_kW = P_load_kW - P_central_ac_kW - P_bess_ac_actual_kW;
    P_grid_import_kW = max(P_grid_net_kW, 0);
    P_grid_export_kW = max(-P_grid_net_kW, 0);

    P_grid_base_kW = P_load_kW - P_pv_ac_base_kW;

    % =====================================================================
    % 5) Explicit canonical energy-flow attribution
    % =====================================================================
    P_dcdc_loss_kW = P_loss_dcdc_W ./ 1000;

    P_dc_charge_bus_kW = max(-P_bess_dc_actual_kW, 0);
    P_dc_discharge_bus_kW = max(P_bess_dc_actual_kW, 0);
    P_dc_charge_pack_kW = max(-P_pack_actual_dc_kW, 0);
    P_dc_discharge_pack_kW = max(P_pack_actual_dc_kW, 0);

    P_ac_charge_bus_kW = max(-P_bess_ac_actual_kW, 0);
    P_ac_discharge_bus_kW = max(P_bess_ac_actual_kW, 0);
    P_ac_charge_pack_kW = max(-P_pack_actual_ac_kW, 0);
    P_ac_discharge_pack_kW = max(P_pack_actual_ac_kW, 0);

    % AC bus load attribution: central AC first, AC-BESS second, grid third.
    P_central_ac_positive_kW = max(P_central_ac_kW, 0);
    P_ac_bess_to_load_kW = min(P_ac_discharge_bus_kW, max(P_load_kW - min(P_central_ac_positive_kW, P_load_kW), 0));
    P_central_to_load_kW = min(P_central_ac_positive_kW, P_load_kW);
    P_dc_bess_to_load_kW = zeros(1, N);

    % Split central inverter AC output between PV and DC-BESS discharge.
    P_pv_to_central_dc_kW = max(P_pv_dc_kW - P_dc_charge_bus_kW, 0);
    P_dc_bess_to_central_kW = P_dc_discharge_bus_kW;
    P_central_source_den = max(P_pv_to_central_dc_kW + P_dc_bess_to_central_kW, eps);
    pvCentralShare = P_pv_to_central_dc_kW ./ P_central_source_den;
    dcBessCentralShare = P_dc_bess_to_central_kW ./ P_central_source_den;
    noCentralSource = (P_pv_to_central_dc_kW + P_dc_bess_to_central_kW) <= 1e-9;
    pvCentralShare(noCentralSource) = 0;
    dcBessCentralShare(noCentralSource) = 0;

    P_pv_to_load_direct_kW = P_central_to_load_kW .* pvCentralShare;
    P_dc_bess_to_load_kW = P_central_to_load_kW .* dcBessCentralShare;
    P_bess_to_load_kW = P_dc_bess_to_load_kW + P_ac_bess_to_load_kW;
    P_grid_to_load_kW = max(P_load_kW - P_pv_to_load_direct_kW - P_bess_to_load_kW, 0);

    % DC-BESS charge source split.
    P_pv_to_bess_dc_kW = zeros(1, N);
    P_grid_to_bess_dc_after_central_kW = zeros(1, N);
    P_grid_to_bess_dc_kW = zeros(1, N);
    dcChargeMask = P_dc_charge_bus_kW > 1e-9;

    P_pv_to_bess_dc_kW(dcChargeMask) = min(P_pv_dc_kW(dcChargeMask), P_dc_charge_bus_kW(dcChargeMask));
    P_grid_to_bess_dc_after_central_kW(dcChargeMask) = max(P_dc_charge_bus_kW(dcChargeMask) - P_pv_to_bess_dc_kW(dcChargeMask), 0);
    dcGridChargeMask = P_grid_to_bess_dc_after_central_kW > 1e-9;
    P_grid_to_bess_dc_kW(dcGridChargeMask) = max(-P_central_ac_kW(dcGridChargeMask), P_grid_to_bess_dc_after_central_kW(dcGridChargeMask));

    dcChargeDen = max(P_dc_charge_bus_kW, eps);
    pvDcChargeShare = P_pv_to_bess_dc_kW ./ dcChargeDen;
    gridDcChargeShare = P_grid_to_bess_dc_after_central_kW ./ dcChargeDen;
    pvDcChargeShare(~dcChargeMask) = 0;
    gridDcChargeShare(~dcChargeMask) = 0;

    P_dcdc_charge_loss_kW = zeros(1, N);
    P_dcdc_charge_loss_kW(dcChargeMask) = P_dcdc_loss_kW(dcChargeMask);

    P_pv_to_bess_dc_loss_kW = pvDcChargeShare .* P_dcdc_charge_loss_kW;
    P_grid_to_bess_dc_loss_kW = max(P_grid_to_bess_dc_kW - P_grid_to_bess_dc_after_central_kW, 0) + gridDcChargeShare .* P_dcdc_charge_loss_kW;
    P_pv_to_bess_dc_stored_kW = pvDcChargeShare .* P_dc_charge_pack_kW;
    P_grid_to_bess_dc_stored_kW = gridDcChargeShare .* P_dc_charge_pack_kW;

    % AC-BESS charge source split.
    P_pv_ac_remaining_after_load_kW = max((P_central_ac_positive_kW .* pvCentralShare) - P_pv_to_load_direct_kW, 0);
    P_pv_to_bess_ac_after_central_kW = min(P_pv_ac_remaining_after_load_kW, P_ac_charge_bus_kW);
    P_grid_to_bess_ac_kW = max(P_ac_charge_bus_kW - P_pv_to_bess_ac_after_central_kW, 0);

    P_pv_to_bess_ac_central_loss_kW = P_loss_central_inv_kW .* (P_pv_to_bess_ac_after_central_kW ./ max(P_central_ac_positive_kW, eps));
    P_pv_to_bess_ac_central_loss_kW(P_central_ac_positive_kW <= 1e-9) = 0;
    P_pv_to_bess_ac_kW = P_pv_to_bess_ac_after_central_kW + P_pv_to_bess_ac_central_loss_kW;

    acChargeDen = max(P_ac_charge_bus_kW, eps);
    pvAcChargeShare = P_pv_to_bess_ac_after_central_kW ./ acChargeDen;
    gridAcChargeShare = P_grid_to_bess_ac_kW ./ acChargeDen;
    noAcCharge = P_ac_charge_bus_kW <= 1e-9;
    pvAcChargeShare(noAcCharge) = 0;
    gridAcChargeShare(noAcCharge) = 0;

    P_pcs_charge_loss_kW = zeros(1, N);
    P_pcs_charge_loss_kW(P_ac_charge_bus_kW > 1e-9) = P_loss_pcs_actual_kW(P_ac_charge_bus_kW > 1e-9);

    P_pv_to_bess_ac_loss_kW = P_pv_to_bess_ac_central_loss_kW + pvAcChargeShare .* P_pcs_charge_loss_kW;
    P_grid_to_bess_ac_loss_kW = gridAcChargeShare .* P_pcs_charge_loss_kW;
    P_pv_to_bess_ac_stored_kW = pvAcChargeShare .* P_ac_charge_pack_kW;
    P_grid_to_bess_ac_stored_kW = gridAcChargeShare .* P_ac_charge_pack_kW;

    P_pv_to_bess_kW = P_pv_to_bess_dc_kW + P_pv_to_bess_ac_kW;
    P_grid_to_bess_kW = P_grid_to_bess_dc_kW + P_grid_to_bess_ac_kW;
    P_pv_to_bess_stored_kW = P_pv_to_bess_dc_stored_kW + P_pv_to_bess_ac_stored_kW;
    P_grid_to_bess_stored_kW = P_grid_to_bess_dc_stored_kW + P_grid_to_bess_ac_stored_kW;
    P_pv_to_bess_loss_kW = P_pv_to_bess_dc_loss_kW + P_pv_to_bess_ac_loss_kW;
    P_grid_to_bess_loss_kW = P_grid_to_bess_dc_loss_kW + P_grid_to_bess_ac_loss_kW;

    P_bess_discharge_before_conversion_kW = P_dc_discharge_pack_kW + P_ac_discharge_pack_kW;

    P_dcdc_discharge_loss_kW = zeros(1, N);
    P_dcdc_discharge_loss_kW(P_dc_discharge_bus_kW > 1e-9) = P_dcdc_loss_kW(P_dc_discharge_bus_kW > 1e-9);
    P_central_loss_dc_bess_to_load_kW = P_loss_central_inv_kW .* dcBessCentralShare;

    dcBessAcDen = max(P_central_ac_positive_kW .* dcBessCentralShare, eps);
    dcBessToLoadShare = P_dc_bess_to_load_kW ./ dcBessAcDen;
    dcBessToLoadShare((P_central_ac_positive_kW .* dcBessCentralShare) <= 1e-9) = 0;

    P_pcs_discharge_loss_kW = zeros(1, N);
    P_pcs_discharge_loss_kW(P_ac_discharge_bus_kW > 1e-9) = P_loss_pcs_actual_kW(P_ac_discharge_bus_kW > 1e-9);
    acBessToLoadShare = P_ac_bess_to_load_kW ./ max(P_ac_discharge_bus_kW, eps);
    acBessToLoadShare(P_ac_discharge_bus_kW <= 1e-9) = 0;

    P_bess_to_load_conversion_loss_kW = ...
        dcBessToLoadShare .* (P_dcdc_discharge_loss_kW + P_central_loss_dc_bess_to_load_kW) + ...
        acBessToLoadShare .* P_pcs_discharge_loss_kW;

    P_grid_import_total_kW = P_grid_import_kW;

    buy_huf = Prices.buy_huf(:).';
    C_grid_to_bess_import_HUF = P_grid_to_bess_kW .* dt_h .* buy_huf;
    C_grid_to_bess_stored_import_equiv_HUF = P_grid_to_bess_stored_kW .* dt_h .* buy_huf;
    C_bess_stored_import_equiv_HUF = (P_dc_charge_pack_kW + P_ac_charge_pack_kW) .* dt_h .* buy_huf;
    C_bess_discharge_before_conversion_import_equiv_HUF = P_bess_discharge_before_conversion_kW .* dt_h .* buy_huf;
    C_bess_to_load_import_equiv_HUF = P_bess_to_load_kW .* dt_h .* buy_huf;

    % =====================================================================
    % 6) Output
    % =====================================================================
    step_res = struct();

    step_res.E_pv_dc = P_pv_dc_kW .* dt_h;
    step_res.E_load = P_load_kW .* dt_h;
    step_res.E_grid_import = P_grid_import_kW .* dt_h;
    step_res.E_grid_export = P_grid_export_kW .* dt_h;

    step_res.Cost_import_HUF = step_res.E_grid_import .* Prices.buy_huf(:).';
    step_res.Rev_export_HUF = step_res.E_grid_export .* Prices.sell_huf(:).';

    step_res.E_stored_dc = pack_out_dc.E_stored / 1000;
    step_res.E_discharged_dc = pack_out_dc.E_discharged / 1000;
    step_res.E_stored_ac = pack_out_ac.E_stored / 1000;
    step_res.E_discharged_ac = pack_out_ac.E_discharged / 1000;

    step_res.E_stored = step_res.E_stored_dc + step_res.E_stored_ac;
    step_res.E_discharged = step_res.E_discharged_dc + step_res.E_discharged_ac;

    step_res.E_loss_joule_dc = pack_out_dc.E_loss_joule / 1000;
    step_res.E_loss_joule_ac = pack_out_ac.E_loss_joule / 1000;
    step_res.E_loss_joule = step_res.E_loss_joule_dc + step_res.E_loss_joule_ac;

    step_res.E_loss_dcdc = (P_loss_dcdc_W ./ 1000) .* dt_h;
    step_res.E_loss_central_inv = P_loss_central_inv_kW .* dt_h;
    step_res.E_loss_pcsb_inv = P_loss_pcs_actual_kW .* dt_h;
    step_res.E_loss_inv = step_res.E_loss_central_inv + step_res.E_loss_pcsb_inv;

    step_res.E_clip_inv = (P_clip_central_kW + P_clip_pcs_req_kW + P_clip_pcs_actual_kW) .* dt_h;
    step_res.E_curtailment = P_clip_central_kW .* dt_h;
    step_res.P_curtailment_kW = P_clip_central_kW(:);

    step_res.E_clip_base = P_clip_base_kW .* dt_h;
    step_res.E_grid_import_base = max(P_grid_base_kW, 0) .* dt_h;
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

    step_res.P_grid_to_bess_dc_kW = P_grid_to_bess_dc_kW(:);
    step_res.P_grid_to_bess_ac_kW = P_grid_to_bess_ac_kW(:);
    step_res.P_pv_to_bess_dc_kW = P_pv_to_bess_dc_kW(:);
    step_res.P_pv_to_bess_ac_kW = P_pv_to_bess_ac_kW(:);
    step_res.P_bess_dc_to_load_kW = P_dc_bess_to_load_kW(:);
    step_res.P_bess_ac_to_load_kW = P_ac_bess_to_load_kW(:);

    step_res.C_grid_to_bess_import_HUF = C_grid_to_bess_import_HUF(:);
    step_res.C_grid_to_bess_stored_import_equiv_HUF = C_grid_to_bess_stored_import_equiv_HUF(:);
    step_res.C_bess_stored_import_equiv_HUF = C_bess_stored_import_equiv_HUF(:);
    step_res.C_bess_discharge_before_conversion_import_equiv_HUF = C_bess_discharge_before_conversion_import_equiv_HUF(:);
    step_res.C_bess_to_load_import_equiv_HUF = C_bess_to_load_import_equiv_HUF(:);

    step_res.P_inv_ac_kW = P_central_ac_kW(:);
    step_res.P_pv_ac_kW = P_central_ac_kW(:);
    step_res.P_pv_ac_base_kW = P_pv_ac_base_kW(:);

    step_res.P_bess_actual_kW = (max(P_bess_dc_actual_kW, 0) + max(P_bess_ac_actual_kW, 0) - max(-P_bess_dc_actual_kW, 0) - max(-P_bess_ac_actual_kW, 0)).';
    step_res.P_bess_dc_actual_kW = P_bess_dc_actual_kW(:);
    step_res.P_bess_ac_actual_kW = P_bess_ac_actual_kW(:);
    step_res.P_pack_actual_dc_kW = P_pack_actual_dc_kW(:);
    step_res.P_pack_actual_ac_kW = P_pack_actual_ac_kW(:);

    step_res.P_loss_inv_kW = (P_loss_central_inv_kW + P_loss_pcs_actual_kW).';
    step_res.P_loss_central_inv_kW = P_loss_central_inv_kW(:);
    step_res.P_loss_pcsb_inv_kW = P_loss_pcs_actual_kW(:);
    step_res.P_loss_dcdc_kW = P_loss_dcdc_W(:) ./ 1000;
    step_res.P_loss_bess_internal_dc_kW = (pack_out_dc.E_loss_joule(:) / 1000) ./ dt_h;
    step_res.P_loss_bess_internal_ac_kW = (pack_out_ac.E_loss_joule(:) / 1000) ./ dt_h;
    step_res.P_loss_bess_internal_kW = step_res.P_loss_bess_internal_dc_kW + step_res.P_loss_bess_internal_ac_kW;

    step_res.SoC_dc = pack_out_dc.SOC(:);
    step_res.SoC_ac = pack_out_ac.SOC(:);
    step_res.SoH_dc = pack_out_dc.SOH(:);
    step_res.SoH_ac = pack_out_ac.SOH(:);

    step_res.SoC = ((step_res.SoC_dc .* pars.dc.E_cap_nom) + (step_res.SoC_ac .* pars.ac.E_cap_nom)) ./ ...
        max(pars.dc.E_cap_nom + pars.ac.E_cap_nom, eps);
    step_res.SoH = min(step_res.SoH_dc, step_res.SoH_ac);

    step_res.SOC_end = step_res.SoC(end);
    step_res.SOC_end_dc = step_res.SoC_dc(end);
    step_res.SOC_end_ac = step_res.SoC_ac(end);
    step_res.SOH_end = step_res.SoH(end);
    step_res.SOH_end_dc = step_res.SoH_dc(end);
    step_res.SOH_end_ac = step_res.SoH_ac(end);

    step_res.T_cell_max = max([pack_out_dc.T_cell(:); pack_out_ac.T_cell(:)]);

    step_res.eta_central_inv = eta_central_vec(:);
    step_res.eta_central_inv_base = eta_central_base_vec(:);
    step_res.eta_dcdc_req = eta_dcdc_req_vec(:);
    step_res.eta_dcdc_actual = eta_dcdc_from_pack(:);
    step_res.eta_bess_pcs_req = eta_pcs_req_vec(:);
    step_res.eta_bess_pcs = eta_pcs_actual_vec(:);
end
