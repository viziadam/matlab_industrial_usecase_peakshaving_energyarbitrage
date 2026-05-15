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
% AC-csatolt PV+BESS topológia.
%
% PV:
%   PV DC -> PV inverter -> AC busz
%
% BESS:
%   BESS pack -> BESS PCS/inverter -> AC busz
%
% Jelkonvenció:
%   P_bess_ac_req_kW > 0  -> BESS kisütés
%   P_bess_ac_req_kW < 0  -> BESS töltés

    requiredParsFields = { ...
        'P_inv_limit_ac', ...
        'inv_eta', ...
        'P_chg_max', ...
        'P_dis_max'};

    for i = 1:numel(requiredParsFields)
        if ~isfield(pars, requiredParsFields{i})
            error('Hiányzó pars mező az AC topology-ban: pars.%s', ...
                requiredParsFields{i});
        end
    end

    if ~isfield(Prices, 'buy_huf')
        error('Hiányzó Prices.buy_huf az AC topology-ban.');
    end

    if ~isfield(Prices, 'sell_huf')
        error('Hiányzó Prices.sell_huf az AC topology-ban.');
    end

    P_bess_ac_req_kW = P_bess_ac_req_kW(:).';
    P_pv_dc_kW = P_pv_dc_kW(:).';
    P_load_kW = P_load_kW(:).';

    N = numel(P_load_kW);

    if numel(P_bess_ac_req_kW) ~= N
        error('P_bess_ac_req_kW hossza eltér a load hossztól.');
    end

    if numel(P_pv_dc_kW) ~= N
        error('P_pv_dc_kW hossza eltér a load hossztól.');
    end

    if numel(Prices.buy_huf(:)) ~= N
        error('Prices.buy_huf hossza eltér a load hossztól.');
    end

    if numel(Prices.sell_huf(:)) ~= N
        error('Prices.sell_huf hossza eltér a load hossztól.');
    end

    % =====================================================================
    % 1) PV inverter
    % =====================================================================
    [P_pv_ac_kW, P_loss_pv_inv_kW, P_clip_pv_kW] = hw_dcac_inverter( ...
        P_pv_dc_kW, ...
        pars.P_inv_limit_ac, ...
        pars.inv_eta);

    % =====================================================================
    % 2) AC BESS kérés -> pack oldali kérés
    % =====================================================================
    P_bess_ac_req_kW = min(P_bess_ac_req_kW,  pars.P_dis_max);
    P_bess_ac_req_kW = max(P_bess_ac_req_kW, -pars.P_chg_max);

    P_pack_req_kW = zeros(1, N);

    mask_dis = P_bess_ac_req_kW > 0;
    mask_ch  = P_bess_ac_req_kW < 0;

    P_pack_req_kW(mask_dis) = ...
        P_bess_ac_req_kW(mask_dis) ./ pars.inv_eta;

    P_pack_req_kW(mask_ch) = ...
        P_bess_ac_req_kW(mask_ch) .* pars.inv_eta;

    P_pack_req_kW = min(P_pack_req_kW,  pars.P_dis_max);
    P_pack_req_kW = max(P_pack_req_kW, -pars.P_chg_max);

    % =====================================================================
    % 3) BESS pack modell
    % =====================================================================
    pack_params = struct();
    pack_params.T_vec = 25 * ones(1, N);

    if isfield(pars, 'T_vec')
        pack_params.T_vec = pars.T_vec;
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
    % 4) BESS PCS / inverter pack -> AC busz
    % =====================================================================
    [P_bess_ac_actual_kW, P_loss_bess_inv_kW, P_clip_bess_inv_kW] = ...
        hw_dcac_inverter( ...
            P_pack_actual_kW, ...
            pars.P_dis_max, ...
            pars.inv_eta);

    % =====================================================================
    % 5) AC busz mérleg
    % =====================================================================
    P_grid_final_kW = P_load_kW - P_pv_ac_kW - P_bess_ac_actual_kW;

    P_grid_base_kW = P_load_kW - P_pv_ac_kW;

    % =====================================================================
    % 6) Metrikak osszegzese
    % =====================================================================
    P_grid_net_kW    = P_grid_final_kW;
    P_grid_import_kW = max(P_grid_net_kW, 0);
    P_grid_export_kW = max(-P_grid_net_kW, 0);

    P_bess_actual_kW = P_bess_ac_actual_kW;

    % AC topology-ban a tényleges "spill" csak a PV inverter clipping.
    % Ha export van, azt külön P_grid_export_kW mezőként mentjük, nem spillként.
    P_spill_kW = P_clip_pv_kW;

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

    % Kompatibilis mezők
    step_res.E_bess_dc = P_pack_actual_kW .* dt_h;
    step_res.E_bess_ac = P_bess_ac_actual_kW .* dt_h;

    step_res.E_loss_joule = pack_out.E_loss_joule / 1000;
    step_res.E_loss_dcdc = zeros(1, N);

    step_res.E_loss_inv = ...
        (P_loss_pv_inv_kW + P_loss_bess_inv_kW) .* dt_h;

    step_res.E_clip_inv = ...
        (P_clip_pv_kW + P_clip_bess_inv_kW) .* dt_h;

    step_res.P_curtailment_kW = P_spill_kW;

    step_res.E_clip_base = P_clip_pv_kW .* dt_h;

    step_res.E_grid_import_base = max(P_grid_base_kW, 0) .* dt_h;

    step_res.Cost_import_base_HUF = ...
        step_res.E_grid_import_base .* Prices.buy_huf(:).';

    step_res.SoC = pack_out.SOC(:);
    step_res.SoH = pack_out.SOH(:);
    step_res.SOC_end = pack_out.SOC(end);
    step_res.SOH_end = pack_out.SOH(end);

    step_res.T_cell_max = max(pack_out.T_cell);

    % Egységes actual teljesítménymezők plothoz / diagnosztikához
    step_res.P_grid_net_kW = P_grid_net_kW(:);
    step_res.P_grid_import_kW = P_grid_import_kW(:);
    step_res.P_grid_export_kW = P_grid_export_kW(:);

    step_res.P_pv_ac_kW = P_pv_ac_kW(:);

    step_res.P_bess_actual_kW = P_bess_actual_kW(:);
    step_res.P_bess_ac_actual_kW = P_bess_ac_actual_kW(:);
    step_res.P_pack_actual_kW = P_pack_actual_kW(:);

    step_res.P_spill_kW = P_spill_kW(:);
    
end