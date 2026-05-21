function [step_res, state_bess] = topology_dc_coupled(P_bess_dc_req_kW, P_pv_dc_kW, P_load_kW, Prices, pars, state_bess, dt_h)
% TOPOLOGY_DC_COUPLED
% DC-csatolt PV+BESS topologia load-dependent central_inv es dcdc modellel.

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
    step_res.P_loss_bess_internal_kW = (pack_out.E_loss_joule(:) / 1000) ./ dt_h;
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
