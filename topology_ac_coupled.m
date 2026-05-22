function [step_res, state_bess] = topology_ac_coupled( ...
    P_bess_ac_req_kW, ...
    P_pv_dc_kW, ...
    P_load_kW, ...
    Prices, ...
    pars, ...
    state_bess, ...
    dt_h)
% TOPOLOGY_AC_COUPLED
%
% AC-csatolt PV+BESS topologia.
%
% PV:
%   PV DC -> kozponti PV inverter -> AC busz
%
% BESS:
%   AC busz <-> BESS PCS <-> BESS pack
%
% Jelkonvencio:
%   P_bess_ac_req_kW > 0  -> BESS kisutes az AC buszra
%   P_bess_ac_req_kW < 0  -> BESS toltes az AC buszrol
%
% A fizikai mukodesi logika valtozatlan marad. A fajl explicit,
% topologia-szintu energiaaramlasi mezoket is visszaad, hogy a
% kiertekeles es a diagnosztika ugyanazokat a szimulacios eredmenyeket
% hasznalja.

    requiredParsFields = { ...
        'P_inv_limit_ac', ...
        'P_chg_max', ...
        'P_dis_max', ...
        'central_inv_eta_nom', ...
        'central_inv_eff_load_points', ...
        'central_inv_eff_eta_points', ...
        'pcs_eta_nom', ...
        'pcs_eff_load_points', ...
        'pcs_eff_eta_points'};

    for i = 1:numel(requiredParsFields)
        if ~isfield(pars, requiredParsFields{i})
            error('Hianyzo pars mezo az AC topology-ban: pars.%s', ...
                requiredParsFields{i});
        end
    end

    if ~isfield(Prices, 'buy_huf')
        error('Hianyzo Prices.buy_huf az AC topology-ban.');
    end

    if ~isfield(Prices, 'sell_huf')
        error('Hianyzo Prices.sell_huf az AC topology-ban.');
    end

    P_bess_ac_req_kW = P_bess_ac_req_kW(:).';
    P_pv_dc_kW = P_pv_dc_kW(:).';
    P_load_kW = P_load_kW(:).';

    N = numel(P_load_kW);

    if numel(P_bess_ac_req_kW) ~= N
        error('P_bess_ac_req_kW hossza elter a load hossztol.');
    end

    if numel(P_pv_dc_kW) ~= N
        error('P_pv_dc_kW hossza elter a load hossztol.');
    end

    if numel(Prices.buy_huf(:)) ~= N
        error('Prices.buy_huf hossza elter a load hossztol.');
    end

    if numel(Prices.sell_huf(:)) ~= N
        error('Prices.sell_huf hossza elter a load hossztol.');
    end

    % =====================================================================
    % 1) Kozponti PV inverter
    % =====================================================================
    [P_pv_ac_kW, P_loss_pv_inv_kW, P_clip_pv_kW, eta_pv_inv_vec] = ...
        hw_dcac_inverter( ...
            P_pv_dc_kW, ...
            pars.P_inv_limit_ac, ...
            pars.central_inv_eta_nom, ...
            pars.central_inv_eff_load_points, ...
            pars.central_inv_eff_eta_points);

    % =====================================================================
    % 2) BESS PCS AC oldali korlatok
    % =====================================================================
    etaPcsNom = max(pars.pcs_eta_nom, eps);

    P_pcs_dis_limit_ac_kW = pars.P_dis_max * etaPcsNom;
    P_pcs_ch_limit_ac_kW  = pars.P_chg_max / etaPcsNom;

    % =====================================================================
    % 3) AC BESS keres -> PCS -> pack oldali keres
    % =====================================================================
    [ ...
        P_bess_ac_req_limited_kW, ...
        P_pack_req_kW, ...
        P_loss_pcs_req_kW, ...
        P_clip_pcs_req_kW, ...
        eta_pcs_req_vec] = hw_bess_pcs_inverter( ...
            P_bess_ac_req_kW, ...
            P_pcs_dis_limit_ac_kW, ...
            P_pcs_ch_limit_ac_kW, ...
            pars.pcs_eta_nom, ...
            pars.pcs_eff_load_points, ...
            pars.pcs_eff_eta_points);

    % =====================================================================
    % 4) BESS pack modell
    % =====================================================================
    pack_params = struct();
    pack_params.T_vec = 25 * ones(1, N);

    if isfield(pars, 'T_vec')
        pack_params.T_vec = pars.T_vec(:).';
    end

    [pack_out, state_bess] = bess_pack_model( ...
        P_pack_req_kW * 1000, ...
        'run', ...
        pack_params, ...
        dt_h, ...
        state_bess);

    P_pack_actual_W = ...
        (pack_out.E_discharged - pack_out.E_stored) ./ dt_h;

    P_pack_actual_kW = P_pack_actual_W / 1000;

    % =====================================================================
    % 5) Pack tenyleges valasz -> BESS PCS -> AC busz
    % =====================================================================
    [ ...
        P_bess_ac_actual_kW, ...
        P_loss_bess_pcs_kW, ...
        P_clip_pcs_actual_kW, ...
        eta_pcs_actual_vec] = hw_bess_pcs_from_pack( ...
            P_pack_actual_kW, ...
            P_pcs_dis_limit_ac_kW, ...
            P_pcs_ch_limit_ac_kW, ...
            pars.pcs_eta_nom, ...
            pars.pcs_eff_load_points, ...
            pars.pcs_eff_eta_points);

    % =====================================================================
    % 6) AC busz merleg
    % =====================================================================
    P_grid_final_kW = P_load_kW - P_pv_ac_kW - P_bess_ac_actual_kW;
    P_grid_base_kW = P_load_kW - P_pv_ac_kW;

    P_grid_net_kW    = P_grid_final_kW;
    P_grid_import_kW = max(P_grid_net_kW, 0);
    P_grid_export_kW = max(-P_grid_net_kW, 0);

    P_bess_actual_kW = P_bess_ac_actual_kW;

    % AC topology-ban a tenyleges spill a PV inverter clipping.
    % Az export nem spill, hanem P_grid_export_kW.
    P_spill_kW = P_clip_pv_kW;

    % =====================================================================
    % Explicit topology-level canonical energy-flow attribution
    % =====================================================================
    P_bess_charge_ac_bus_kW = max(-P_bess_ac_actual_kW, 0);
    P_bess_discharge_ac_bus_kW = max(P_bess_ac_actual_kW, 0);

    P_bess_charge_pack_kW = max(-P_pack_actual_kW, 0);
    P_bess_discharge_pack_kW = max(P_pack_actual_kW, 0);

    % AC bus load attribution: PV first, then BESS, then grid.
    P_pv_to_load_direct_kW = min(P_pv_ac_kW, P_load_kW);
    remainingLoadAfterPv_kW = max(P_load_kW - P_pv_to_load_direct_kW, 0);

    P_bess_to_load_kW = min(P_bess_discharge_ac_bus_kW, remainingLoadAfterPv_kW);
    remainingLoadAfterBess_kW = max(P_load_kW - P_pv_to_load_direct_kW - P_bess_to_load_kW, 0);

    P_grid_to_load_kW = remainingLoadAfterBess_kW;

    % Charge direction.
    % PV -> BESS: PV DC -> central inverter -> AC bus -> PCS -> pack.
    % Grid -> BESS: grid AC -> PCS -> pack.
    P_pv_remaining_after_load_kW = max(P_pv_ac_kW - P_pv_to_load_direct_kW, 0);

    P_pv_to_bess_after_central_kW = min( ...
        P_pv_remaining_after_load_kW, ...
        P_bess_charge_ac_bus_kW);

    P_grid_to_bess_kW = max( ...
        P_bess_charge_ac_bus_kW - P_pv_to_bess_after_central_kW, ...
        0);

    pvAcDen = max(P_pv_ac_kW, eps);
    pvToBessCentralShare = P_pv_to_bess_after_central_kW ./ pvAcDen;
    pvToBessCentralShare(P_pv_ac_kW <= 1e-9) = 0;

    P_pv_to_bess_central_loss_kW = P_loss_pv_inv_kW .* pvToBessCentralShare;

    P_pv_to_bess_kW = ...
        P_pv_to_bess_after_central_kW + P_pv_to_bess_central_loss_kW;

    chargeDen = max(P_bess_charge_ac_bus_kW, eps);
    pvChargeShare = P_pv_to_bess_after_central_kW ./ chargeDen;
    gridChargeShare = P_grid_to_bess_kW ./ chargeDen;

    noChargeMask = P_bess_charge_ac_bus_kW <= 1e-9;
    pvChargeShare(noChargeMask) = 0;
    gridChargeShare(noChargeMask) = 0;

    P_pcs_charge_loss_kW = zeros(1, N);
    chargeMask = P_bess_charge_ac_bus_kW > 1e-9;
    P_pcs_charge_loss_kW(chargeMask) = P_loss_bess_pcs_kW(chargeMask);

    P_pv_to_bess_loss_kW = ...
        P_pv_to_bess_central_loss_kW + ...
        pvChargeShare .* P_pcs_charge_loss_kW;

    P_grid_to_bess_loss_kW = gridChargeShare .* P_pcs_charge_loss_kW;

    P_pv_to_bess_stored_kW = pvChargeShare .* P_bess_charge_pack_kW;
    P_grid_to_bess_stored_kW = gridChargeShare .* P_bess_charge_pack_kW;

    % Discharge direction.
    P_bess_discharge_before_conversion_kW = P_bess_discharge_pack_kW;

    P_pcs_discharge_loss_kW = zeros(1, N);
    dischargeMask = P_bess_discharge_ac_bus_kW > 1e-9;
    P_pcs_discharge_loss_kW(dischargeMask) = P_loss_bess_pcs_kW(dischargeMask);

    bessAcDen = max(P_bess_discharge_ac_bus_kW, eps);
    bessToLoadShare = P_bess_to_load_kW ./ bessAcDen;
    bessToLoadShare(P_bess_discharge_ac_bus_kW <= 1e-9) = 0;

    P_bess_to_load_conversion_loss_kW = ...
        bessToLoadShare .* P_pcs_discharge_loss_kW;

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

    % =====================================================================
    % 7) Output structure
    % =====================================================================
    step_res = struct();

    step_res.E_pv_dc = P_pv_dc_kW .* dt_h;
    step_res.E_load = P_load_kW .* dt_h;

    step_res.E_grid_import = P_grid_import_kW .* dt_h;
    step_res.E_grid_export = P_grid_export_kW .* dt_h;

    step_res.Cost_import_HUF = ...
        step_res.E_grid_import .* Prices.buy_huf(:).';

    step_res.Rev_export_HUF = ...
        step_res.E_grid_export .* Prices.sell_huf(:).';

    step_res.E_stored = pack_out.E_stored / 1000;
    step_res.E_discharged = pack_out.E_discharged / 1000;

    % Kompatibilis mezok
    step_res.E_bess_dc = P_pack_actual_kW .* dt_h;
    step_res.E_bess_ac = P_bess_ac_actual_kW .* dt_h;

    step_res.E_loss_joule = pack_out.E_loss_joule / 1000;

    % AC-csatolt esetben nincs BESS DC/DC konverter.
    step_res.E_loss_dcdc = zeros(1, N);

    % Inverter/PCS konverzios veszteseg:
    %   PV inverter + BESS PCS.
    step_res.E_loss_inv = ...
        (P_loss_pv_inv_kW + P_loss_bess_pcs_kW) .* dt_h;

    step_res.E_loss_central_inv = P_loss_pv_inv_kW .* dt_h;
    step_res.E_loss_pcsb_inv = P_loss_bess_pcs_kW .* dt_h;

    step_res.E_clip_inv = ...
        (P_clip_pv_kW + P_clip_pcs_req_kW + P_clip_pcs_actual_kW) .* dt_h;

    step_res.P_curtailment_kW = P_spill_kW;
    step_res.E_curtailment = P_spill_kW .* dt_h;

    step_res.E_clip_base = P_clip_pv_kW .* dt_h;

    step_res.E_grid_import_base = max(P_grid_base_kW, 0) .* dt_h;

    step_res.Cost_import_base_HUF = ...
        step_res.E_grid_import_base .* Prices.buy_huf(:).';

    step_res.SoC = pack_out.SOC(:);
    step_res.SoH = pack_out.SOH(:);
    step_res.SOC_end = pack_out.SOC(end);
    step_res.SOH_end = pack_out.SOH(end);

    step_res.T_cell_max = max(pack_out.T_cell);

    % Unified actual power fields for plotting / diagnostics
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

    step_res.P_pv_ac_kW = P_pv_ac_kW(:);
    step_res.P_pv_ac_base_kW = P_pv_ac_kW(:);

    step_res.P_bess_actual_kW = P_bess_actual_kW(:);
    step_res.P_bess_ac_actual_kW = P_bess_ac_actual_kW(:);
    step_res.P_pack_actual_kW = P_pack_actual_kW(:);
    step_res.P_pack_req_kW = P_pack_req_kW(:);

    step_res.P_bess_ac_req_kW = P_bess_ac_req_kW(:);
    step_res.P_bess_ac_req_limited_kW = P_bess_ac_req_limited_kW(:);

    step_res.P_spill_kW = P_spill_kW(:);
    step_res.P_loss_pv_inv_kW = P_loss_pv_inv_kW(:);
    step_res.P_loss_bess_pcs_kW = P_loss_bess_pcs_kW(:);
    step_res.P_clip_pv_kW = P_clip_pv_kW(:);
    step_res.P_clip_bess_pcs_kW = (P_clip_pcs_req_kW(:) + P_clip_pcs_actual_kW(:));

    step_res.P_loss_inv_kW = (P_loss_pv_inv_kW(:) + P_loss_bess_pcs_kW(:));
    step_res.P_loss_central_inv_kW = P_loss_pv_inv_kW(:);
    step_res.P_loss_pcsb_inv_kW = P_loss_bess_pcs_kW(:);
    step_res.P_loss_dcdc_kW = zeros(N, 1);
    step_res.P_loss_bess_internal_kW = (pack_out.E_loss_joule(:) / 1000) ./ dt_h;

    step_res.eta_pv_inv = eta_pv_inv_vec(:);
    step_res.eta_bess_pcs = eta_pcs_actual_vec(:);
    step_res.eta_bess_pcs_req = eta_pcs_req_vec(:);
end
