

% function [step_res, state_bess] = topology_dc_coupled( ...
%     P_bess_dc_req_kW, ...
%     P_pv_dc_kW, ...
%     P_load_kW, ...
%     Prices, ...
%     pars, ...
%     state_bess, ...
%     dt_h)
% % TOPOLOGY_DC_COUPLED
% %
% % DC-csatolt PV+BESS topologia.
% %
% % Jelkonvencio:
% %   P_bess_dc_req_kW > 0  -> BESS kisutes a DC busz fele
% %   P_bess_dc_req_kW < 0  -> BESS toltes
% %
% % Fontos:
% %   Ez a verzio nem csak nehany teljesitmenymezo, hanem a kozos
% %   metrikarendszerhez szukseges energiamezoket is visszaadja:
% %
% %       E_grid_import
% %       E_stored
% %       E_discharged
% %       P_curtailment_kW
% %       SoC
% %       SoH
% %
% % Igy a DC es AC topologia a contract-kereses es a full horizon
% % metrikak szempontjabol azonos interfeszt ad.
% 
%     P_bess_dc_req_kW = P_bess_dc_req_kW(:).';
%     P_pv_dc_kW = P_pv_dc_kW(:).';
%     P_load_kW = P_load_kW(:).';
% 
%     N = numel(P_load_kW);
% 
%     if numel(P_bess_dc_req_kW) ~= N
%         error('P_bess_dc_req_kW length differs from P_load_kW length.');
%     end
% 
%     if numel(P_pv_dc_kW) ~= N
%         error('P_pv_dc_kW length differs from P_load_kW length.');
%     end
% 
%     if numel(Prices.buy_huf(:)) ~= N
%         error('Prices.buy_huf length differs from P_load_kW length.');
%     end
% 
%     if numel(Prices.sell_huf(:)) ~= N
%         error('Prices.sell_huf length differs from P_load_kW length.');
%     end
% 
%     % =====================================================================
%     % 1) EMS DC bus request -> pack request through DC/DC converter
%     % =====================================================================
%     [P_pack_req_W, ~] = hw_dcdc_converter( ...
%         P_bess_dc_req_kW * 1000, ...
%         pars.P_chg_max * 1000, ...
%         pars.eta_c, ...
%         pars.eta_d);
% 
%     % =====================================================================
%     % 2) Battery pack model
%     % =====================================================================
%     pack_params = struct();
%     pack_params.T_vec = 25 * ones(1, N);
% 
%     [pack_out, state_bess] = bess_pack_model( ...
%         P_pack_req_W, ...
%         'run', ...
%         pack_params, ...
%         dt_h, ...
%         state_bess);
% 
%     P_pack_actual_W = ...
%         (pack_out.E_discharged - pack_out.E_stored) ./ dt_h;
% 
%     P_pack_actual_kW = P_pack_actual_W / 1000;
% 
%     % =====================================================================
%     % 3) Pack actual response -> DC bus actual BESS power
%     % =====================================================================
%     [P_bess_dc_actual_W, P_loss_dcdc_W] = hw_dcdc_converter( ...
%         P_pack_actual_W, ...
%         pars.P_chg_max * 1000, ...
%         1 / pars.eta_c, ...
%         1 / pars.eta_d);
% 
%     P_bess_dc_actual_kW = P_bess_dc_actual_W / 1000;
% 
%     % =====================================================================
%     % 4) DC bus balance and main inverter
%     % =====================================================================
%     P_bus_dc_actual_kW = P_pv_dc_kW + P_bess_dc_actual_kW;
% 
%     [P_inv_ac_kW, P_loss_inv_kW, P_clip_kW] = hw_dcac_inverter( ...
%         P_bus_dc_actual_kW, ...
%         pars.P_inv_limit_ac, ...
%         pars.inv_eta);
% 
%     % =====================================================================
%     % 5) AC bus / grid balance
%     % =====================================================================
%     P_grid_net_kW = P_load_kW - P_inv_ac_kW;
% 
%     P_grid_import_kW = max(P_grid_net_kW, 0);
%     P_grid_export_kW = max(-P_grid_net_kW, 0);
% 
%     % =====================================================================
%     % 6) No-BESS baseline
%     % =====================================================================
%     P_inv_ac_base_kW = min(P_pv_dc_kW .* pars.inv_eta, pars.P_inv_limit_ac);
%     P_grid_base_kW = P_load_kW - P_inv_ac_base_kW;
% 
%     P_grid_import_base_kW = max(P_grid_base_kW, 0);
%     P_grid_export_base_kW = max(-P_grid_base_kW, 0);
% 
%     P_clip_base_kW = max((P_pv_dc_kW .* pars.inv_eta) - pars.P_inv_limit_ac, 0);
% 
%     % =====================================================================
%     % 7) Output structure
%     % =====================================================================
%     step_res = struct();
% 
%     % ---------------------------------------------------------------------
%     % Energy vectors
%     % ---------------------------------------------------------------------
%     step_res.E_pv_dc = P_pv_dc_kW .* dt_h;
%     step_res.E_load = P_load_kW .* dt_h;
% 
%     step_res.E_grid_import = P_grid_import_kW .* dt_h;
%     step_res.E_grid_export = P_grid_export_kW .* dt_h;
% 
%     step_res.E_stored = pack_out.E_stored / 1000;
%     step_res.E_discharged = pack_out.E_discharged / 1000;
% 
%     step_res.E_bess_dc = P_bess_dc_actual_kW .* dt_h;
% 
%     step_res.E_loss_joule = pack_out.E_loss_joule / 1000;
%     step_res.E_loss_dcdc = (P_loss_dcdc_W / 1000) .* dt_h;
%     step_res.E_loss_inv = P_loss_inv_kW .* dt_h;
% 
%     step_res.E_clip_inv = P_clip_kW .* dt_h;
%     step_res.E_curtailment = step_res.E_clip_inv;
% 
%     % ---------------------------------------------------------------------
%     % Baseline vectors
%     % ---------------------------------------------------------------------
%     step_res.E_clip_base = P_clip_base_kW .* dt_h;
%     step_res.E_grid_import_base = P_grid_import_base_kW .* dt_h;
%     step_res.E_grid_export_base = P_grid_export_base_kW .* dt_h;
% 
%     % ---------------------------------------------------------------------
%     % Cost / revenue vectors from topology-local price only
%     % The main objective cost is calculated outside this topology function.
%     % ---------------------------------------------------------------------
%     step_res.Cost_import_HUF = ...
%         step_res.E_grid_import .* Prices.buy_huf(:).';
% 
%     step_res.Rev_export_HUF = ...
%         step_res.E_grid_export .* Prices.sell_huf(:).';
% 
%     step_res.Cost_import_base_HUF = ...
%         step_res.E_grid_import_base .* Prices.buy_huf(:).';
% 
%     % ---------------------------------------------------------------------
%     % Power vectors
%     % ---------------------------------------------------------------------
%     step_res.P_grid_net_kW = P_grid_net_kW(:);
%     step_res.P_grid_import_kW = P_grid_import_kW(:);
%     step_res.P_grid_export_kW = P_grid_export_kW(:);
% 
%     step_res.P_bess_actual_kW = P_bess_dc_actual_kW(:);
%     step_res.P_bess_dc_actual_kW = P_bess_dc_actual_kW(:);
%     step_res.P_pack_actual_kW = P_pack_actual_kW(:);
% 
%     step_res.P_inv_ac_kW = P_inv_ac_kW(:);
% 
%     % Kompatibilis nev: DC topologiaban ez a kozos inverter AC kimenete.
%     step_res.P_pv_ac_kW = P_inv_ac_kW(:);
% 
%     step_res.P_pv_ac_base_kW = P_inv_ac_base_kW(:);
% 
%     step_res.P_spill_kW = P_clip_kW(:);
%     step_res.P_curtailment_kW = P_clip_kW(:);
% 
%     % ---------------------------------------------------------------------
%     % State vectors
%     % ---------------------------------------------------------------------
%     step_res.SoC = pack_out.SOC(:);
%     step_res.SoH = pack_out.SOH(:);
% 
%     step_res.SOC_end = pack_out.SOC(end);
%     step_res.SOH_end = pack_out.SOH(end);
%     step_res.T_cell_max = max(pack_out.T_cell);
% end

function [step_res, state_bess] = topology_dc_coupled( ...
    P_bess_dc_req_kW, ...
    P_pv_dc_kW, ...
    P_load_kW, ...
    Prices, ...
    pars, ...
    state_bess, ...
    dt_h)
% TOPOLOGY_DC_COUPLED
%
% DC-csatolt PV+BESS topologia.
%
% Jelkonvencio:
%   P_bess_dc_req_kW > 0  -> BESS kisutes a DC busz fele
%   P_bess_dc_req_kW < 0  -> BESS toltes
%
% Fontos:
%   Ez a verzio a kozos DC/AC inverter korlatat mar a BESS parancs
%   vegrehajtasa elott figyelembe veszi. Igy az akkumulator nem tud olyan
%   energiaval toltodni vagy olyan teljesitmennyel kisutni, amelyet a
%   kozos inverter fizikailag nem tudna atvinni.
%
% Visszaadott mezok:
%   A korabbi interfeszt megtartja:
%       E_grid_import
%       E_stored
%       E_discharged
%       P_curtailment_kW
%       SoC
%       SoH
%       P_grid_import_kW
%       P_grid_export_kW
%       P_bess_actual_kW
%       P_bess_dc_actual_kW
%       P_inv_ac_kW
%       P_pv_ac_kW
%       P_pv_ac_base_kW
%       P_spill_kW
%
%   Plusz diagnosztikai mezok:
%       P_bess_dc_req_kW
%       P_bess_dc_req_limited_kW

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

    % =====================================================================
    % 0) Kozos DC/AC inverter korlatanak ervenyesitese a BESS parancson
    % =====================================================================
    %
    % A kozos DC busz teljesitmenye:
    %
    %   P_bus_dc = P_pv_dc + P_bess_dc
    %
    % Pozitiv irany:
    %   DC busz -> AC oldal
    %   P_bus_dc * inv_eta <= P_inv_limit_ac
    %
    % Negativ irany:
    %   AC oldal -> DC busz
    %   abs(P_bus_dc / inv_eta) <= P_inv_limit_ac
    %
    % A korlatot meg a DC/DC es BESS pack modell elott alkalmazzuk, hogy
    % az akku SoC-ja ne valtozzon fizikailag lehetetlen inverteraramlas miatt.

    P_bess_dc_req_original_kW = P_bess_dc_req_kW;
    P_bess_dc_req_limited_kW = P_bess_dc_req_kW;

    eta_inv = max(pars.inv_eta, eps);

    for t = 1:N

        % -----------------------------------------------------------------
        % BESS kisutes: BESS -> DC busz -> inverter -> AC oldal
        % -----------------------------------------------------------------
        if P_bess_dc_req_limited_kW(t) > 0

            % A PV mar foglalhat inverterkapacitast.
            % Ha PV egyedul is teliti az invertert, akkor a BESS nem tud
            % ugyanabban az idolepesben tovabbi AC oldali teljesitmenyt adni.
            P_dis_available_by_inv_kW = ...
                pars.P_inv_limit_ac / eta_inv - P_pv_dc_kW(t);

            P_dis_available_by_inv_kW = max(P_dis_available_by_inv_kW, 0);

            P_bess_dc_req_limited_kW(t) = min( ...
                P_bess_dc_req_limited_kW(t), ...
                P_dis_available_by_inv_kW);
        end

        % -----------------------------------------------------------------
        % BESS toltes: PV DC es/vagy halozati AC energia -> BESS
        % -----------------------------------------------------------------
        if P_bess_dc_req_limited_kW(t) < 0

            % A BESS tolteset reszben a PV DC energia is fedezheti.
            % Ha a toltesi igeny nagyobb, mint a PV DC teljesitmeny,
            % akkor a hianyzo resz a halozat felol, rectifier iranyban
            % csak az inverter AC teljesitmenykorlataig potolhato.
            %
            % Minimalis megengedett busz teljesitmeny:
            %   P_bus_dc >= -P_inv_limit_ac * eta_inv
            %
            % Ebből:
            %   P_bess_dc >= -P_inv_limit_ac * eta_inv - P_pv_dc

            P_ch_available_by_inv_kW = ...
                pars.P_inv_limit_ac * eta_inv + P_pv_dc_kW(t);

            P_bess_dc_req_limited_kW(t) = max( ...
                P_bess_dc_req_limited_kW(t), ...
               -P_ch_available_by_inv_kW);
        end
    end

    P_bess_dc_req_kW = P_bess_dc_req_limited_kW;

    % =====================================================================
    % 1) EMS DC bus request -> pack request through DC/DC converter
    % =====================================================================
    [P_pack_req_W, P_loss_dcdc_req_W] = hw_dcdc_converter( ...
        P_bess_dc_req_kW * 1000, ...
        pars.P_chg_max * 1000, ...
        pars.eta_c, ...
        pars.eta_d);

    % =====================================================================
    % 2) Battery pack model
    % =====================================================================
    pack_params = struct();
    pack_params.T_vec = 25 * ones(1, N);

    if isfield(pars, 'T_vec')
        pack_params.T_vec = pars.T_vec(:).';
    end

    [pack_out, state_bess] = bess_pack_model( ...
        P_pack_req_W, ...
        'run', ...
        pack_params, ...
        dt_h, ...
        state_bess);

    % A pack_out energiamezok Wh-ban vannak kezelve a meglévő kódban.
    % Pozitiv P_pack_actual_W: kisutes
    % Negativ P_pack_actual_W: toltes
    P_pack_actual_W = ...
        (pack_out.E_discharged - pack_out.E_stored) ./ dt_h;

    P_pack_actual_kW = P_pack_actual_W / 1000;

    % =====================================================================
    % 3) Pack actual response -> DC bus actual BESS power
    % =====================================================================
    %
    % A korabbi megoldas masodszor is meghivta a hw_dcdc_convertert
    % inverz hatasfokokkal. Ez kisutesi iranyban ujra korlatozhatta a pack
    % oldali teljesitmenyt. Itt explicit visszaszamitast hasznalunk:
    %
    % Toltes:
    %   P_pack = P_dc_bus * eta_c
    %   P_dc_bus = P_pack / eta_c
    %
    % Kisutes:
    %   P_pack = P_dc_bus / eta_d
    %   P_dc_bus = P_pack * eta_d

    P_bess_dc_actual_W = zeros(1, N);
    P_loss_dcdc_W = zeros(1, N);

    mask_chg = P_pack_actual_W < 0;
    mask_dis = P_pack_actual_W > 0;

    P_bess_dc_actual_W(mask_chg) = ...
        P_pack_actual_W(mask_chg) ./ max(pars.eta_c, eps);

    P_bess_dc_actual_W(mask_dis) = ...
        P_pack_actual_W(mask_dis) .* pars.eta_d;

    P_loss_dcdc_W(mask_chg | mask_dis) = abs( ...
        P_bess_dc_actual_W(mask_chg | mask_dis) - ...
        P_pack_actual_W(mask_chg | mask_dis));

    P_bess_dc_actual_kW = P_bess_dc_actual_W / 1000;

    % =====================================================================
    % 4) DC bus balance and main inverter
    % =====================================================================
    P_bus_dc_actual_kW = P_pv_dc_kW + P_bess_dc_actual_kW;

    [P_inv_ac_kW, P_loss_inv_kW, P_clip_kW] = hw_dcac_inverter( ...
        P_bus_dc_actual_kW, ...
        pars.P_inv_limit_ac, ...
        pars.inv_eta);

    % =====================================================================
    % 5) AC bus / grid balance
    % =====================================================================
    P_grid_net_kW = P_load_kW - P_inv_ac_kW;

    P_grid_import_kW = max(P_grid_net_kW, 0);
    P_grid_export_kW = max(-P_grid_net_kW, 0);

    % =====================================================================
    % 6) No-BESS baseline
    % =====================================================================
    P_inv_ac_base_kW = min(P_pv_dc_kW .* pars.inv_eta, pars.P_inv_limit_ac);
    P_grid_base_kW = P_load_kW - P_inv_ac_base_kW;

    P_grid_import_base_kW = max(P_grid_base_kW, 0);
    P_grid_export_base_kW = max(-P_grid_base_kW, 0);

    P_clip_base_kW = max((P_pv_dc_kW .* pars.inv_eta) - pars.P_inv_limit_ac, 0);

    % =====================================================================
    % 7) Output structure
    % =====================================================================
    step_res = struct();

    % ---------------------------------------------------------------------
    % Energy vectors
    % ---------------------------------------------------------------------
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

    step_res.E_clip_inv = P_clip_kW .* dt_h;
    step_res.E_curtailment = step_res.E_clip_inv;

    % ---------------------------------------------------------------------
    % Baseline vectors
    % ---------------------------------------------------------------------
    step_res.E_clip_base = P_clip_base_kW .* dt_h;
    step_res.E_grid_import_base = P_grid_import_base_kW .* dt_h;
    step_res.E_grid_export_base = P_grid_export_base_kW .* dt_h;

    % ---------------------------------------------------------------------
    % Cost / revenue vectors from topology-local price only
    % The main objective cost is calculated outside this topology function.
    % ---------------------------------------------------------------------
    step_res.Cost_import_HUF = ...
        step_res.E_grid_import .* Prices.buy_huf(:).';

    step_res.Rev_export_HUF = ...
        step_res.E_grid_export .* Prices.sell_huf(:).';

    step_res.Cost_import_base_HUF = ...
        step_res.E_grid_import_base .* Prices.buy_huf(:).';

    % ---------------------------------------------------------------------
    % Power vectors
    % ---------------------------------------------------------------------
    step_res.P_grid_net_kW = P_grid_net_kW(:);
    step_res.P_grid_import_kW = P_grid_import_kW(:);
    step_res.P_grid_export_kW = P_grid_export_kW(:);

    step_res.P_bess_actual_kW = P_bess_dc_actual_kW(:);
    step_res.P_bess_dc_actual_kW = P_bess_dc_actual_kW(:);
    step_res.P_pack_actual_kW = P_pack_actual_kW(:);

    step_res.P_inv_ac_kW = P_inv_ac_kW(:);

    % Kompatibilis nev: DC topologiaban ez a kozos inverter AC kimenete.
    step_res.P_pv_ac_kW = P_inv_ac_kW(:);

    % Baseline PV-only AC teljesitmeny, BESS nelkul.
    step_res.P_pv_ac_base_kW = P_inv_ac_base_kW(:);

    step_res.P_spill_kW = P_clip_kW(:);
    step_res.P_curtailment_kW = P_clip_kW(:);

    % Diagnosztikai mezok a fizikai clamp ellenorzesere.
    step_res.P_bess_dc_req_kW = P_bess_dc_req_original_kW(:);
    step_res.P_bess_dc_req_limited_kW = P_bess_dc_req_limited_kW(:);

    % ---------------------------------------------------------------------
    % State vectors
    % ---------------------------------------------------------------------
    step_res.SoC = pack_out.SOC(:);
    step_res.SoH = pack_out.SOH(:);

    step_res.SOC_end = pack_out.SOC(end);
    step_res.SOH_end = pack_out.SOH(end);
    step_res.T_cell_max = max(pack_out.T_cell);
end