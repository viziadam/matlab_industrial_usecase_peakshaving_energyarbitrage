% function P_bess_dc_req = ems_realtime_decision_dc(P_pv_dc, P_load_actual, plan, pars)
% % EMS_REALTIME_DECISION_DC
% % A MILP tervből végrehajtható BESS DC teljesítményparancsot képez.
% %
% % Bemenet:
% %   P_pv_dc      : tényleges PV DC teljesítményprofil [kW]
% %   P_load_actual: tényleges terhelési profil [kW]
% %   plan         : MILP terv
% %   pars         : BESS paraméterek
% %
% % Kimenet:
% %   P_bess_dc_req [kW]
% %       pozitív  -> kisütés a DC sín felé
% %       negatív  -> töltés
% 
%     %#ok<INUSD>
%     N = length(P_pv_dc);
%     P_bess_dc_req = zeros(1, N);
% 
%     if ~isfield(plan, 'P_ch_plan') || ~isfield(plan, 'P_dis_plan')
%         if isfield(plan, 'trade_buy_mask') && isfield(plan, 'trade_sell_mask')
%             P_bess_dc_req(plan.trade_buy_mask)  = -pars.P_chg_max * pars.inv_eta;
%             P_bess_dc_req(plan.trade_sell_mask) =  pars.P_dis_max / max(pars.inv_eta, eps);
%         end
%         return;
%     end
% 
%     P_ch_ac  = plan.P_ch_plan(:).';
%     P_dis_ac = plan.P_dis_plan(:).';
% 
%     % AC oldali terv -> DC oldali BESS kérés
%     P_bess_dc_req = (P_dis_ac ./ max(pars.inv_eta, eps)) - (P_ch_ac .* pars.inv_eta);
% 
%     % Fizikai korlátok
%     P_bess_dc_req = min(P_bess_dc_req,  pars.P_dis_max);
%     P_bess_dc_req = max(P_bess_dc_req, -pars.P_chg_max);
% 
%     % Numerikus zaj nullázása
%     P_bess_dc_req(abs(P_bess_dc_req) < 1e-6) = 0;
% end

function P_bess_dc_req = ems_realtime_decision_dc(P_pv_dc, P_load_actual, plan, pars)
% EMS_REALTIME_DECISION_DC
%
% A DC-csatolt MILP tervbol vegrehajthato BESS DC oldali
% teljesitmenyparancsot kepez.
%
% Jelkonvencio:
%   P_bess_dc_req > 0  -> BESS kisutes a DC busz fele
%   P_bess_dc_req < 0  -> BESS toltes
%
% Fontos:
%   Az uj DC MILP-ben a plan.P_ch_plan es plan.P_dis_plan mar DC busz
%   oldali BESS teljesitmenyek:
%
%       P_ch_plan  = inverteren atjovo grid->BESS DC oldali resz
%                    + PV->BESS DC oldali resz
%
%       P_dis_plan = BESS->load DC busz oldali igeny
%
%   Ezert itt alapertelmezesben NINCS ujabb AC/DC atszamitas.
%
% Kompatibilitas:
%   Ha regi, AC oldali tervet kellene futtatni, akkor a plan strukturaban
%   add meg:
%
%       plan.P_bess_plan_reference_side = "ac_bus";
%
%   Ekkor a fuggveny a regi AC -> DC atszamitas szerint dolgozik.

    % =====================================================================
    % 0) Bemenetek rendezese es ellenorzese
    % =====================================================================

    requiredParsFields = { ...
        'P_chg_max', ...
        'P_dis_max', ...
        'inv_eta', ...
        'P_inv_limit_ac'};

    for k = 1:numel(requiredParsFields)
        if ~isfield(pars, requiredParsFields{k})
            error('Hianyzo pars mezo az ems_realtime_decision_dc-ben: pars.%s', ...
                requiredParsFields{k});
        end
    end

    P_pv_dc = P_pv_dc(:).';
    P_load_actual = P_load_actual(:).';

    N = numel(P_pv_dc);

    if numel(P_load_actual) ~= N
        error('P_load_actual length differs from P_pv_dc length.');
    end

    eta_inv = max(pars.inv_eta, eps);

    P_bess_dc_req = zeros(1, N);

    % =====================================================================
    % 1) BESS parancs kepzese a MILP tervbol
    % =====================================================================

    if isfield(plan, 'P_ch_plan') && isfield(plan, 'P_dis_plan')

        P_ch_plan = local_row_vector_to_length( ...
            plan.P_ch_plan, ...
            N, ...
            'plan.P_ch_plan');

        P_dis_plan = local_row_vector_to_length( ...
            plan.P_dis_plan, ...
            N, ...
            'plan.P_dis_plan');

        planReferenceSide = local_get_plan_reference_side(plan);

        switch planReferenceSide

            case "dc_bus"
                % ---------------------------------------------------------
                % UJ DC MILP logika:
                % P_ch_plan es P_dis_plan mar DC busz oldali teljesitmenyek.
                % Ezert kozvetlenul kepezheto a BESS DC parancs:
                %
                %   pozitív  = kisutes
                %   negativ  = toltes
                % ---------------------------------------------------------
                P_bess_dc_req = P_dis_plan - P_ch_plan;

            case "ac_bus"
                % ---------------------------------------------------------
                % REGI kompatibilitasi logika:
                % P_ch_plan es P_dis_plan AC oldali teljesitmenyek.
                % Ilyenkor kell AC -> DC atszamitas.
                % ---------------------------------------------------------
                P_bess_dc_req = ...
                    (P_dis_plan ./ eta_inv) - ...
                    (P_ch_plan .* eta_inv);

            otherwise
                error('Ismeretlen P_bess_plan_reference_side: %s', planReferenceSide);
        end

    elseif isfield(plan, 'trade_buy_mask') && isfield(plan, 'trade_sell_mask')

        % -----------------------------------------------------------------
        % Fallback regi binaris jelzesekhez.
        % Itt mar DC oldali parancsot adunk, mert ez a fuggveny DC
        % topologiat vezerel.
        % -----------------------------------------------------------------
        trade_buy_mask = logical(local_row_vector_to_length( ...
            plan.trade_buy_mask, ...
            N, ...
            'plan.trade_buy_mask'));

        trade_sell_mask = logical(local_row_vector_to_length( ...
            plan.trade_sell_mask, ...
            N, ...
            'plan.trade_sell_mask'));

        P_bess_dc_req(trade_buy_mask)  = -pars.P_chg_max;
        P_bess_dc_req(trade_sell_mask) =  pars.P_dis_max;

    else

        % Nincs ertelmezheto BESS terv.
        P_bess_dc_req = zeros(1, N);
    end

    % =====================================================================
    % 2) BESS sajat teljesitmenykorlatai
    % =====================================================================
    %
    % Ezek DC busz oldali BESS korlatok.
    % A P_bess_dc_req pozitiv iranyban kisutes, negativ iranyban toltes.

    P_bess_dc_req = min(P_bess_dc_req,  pars.P_dis_max);
    P_bess_dc_req = max(P_bess_dc_req, -pars.P_chg_max);

    % =====================================================================
    % 3) Kozos DC/AC inverter korlatanak figyelembevetele
    % =====================================================================
    %
    % DC csatolasnal a PV es a BESS kozos DC buszon vannak, majd ugyanazon
    % kozos DC/AC inverteren keresztul kapcsolodnak az AC oldalhoz.
    %
    % A topologia fuggvenyben is erdemes ezt ervenyesiteni, de itt is
    % korlatozzuk a parancsot, hogy a realtime request mar fizikailag
    % ertelmezheto legyen.
    %
    % Pozitiv irany:
    %   P_bus_dc = P_pv_dc + P_bess_dc
    %   P_bus_dc * eta_inv <= P_inv_limit_ac
    %
    % Negativ irany:
    %   P_bus_dc >= -P_inv_limit_ac * eta_inv
    %
    % Tehat:
    %   kisuteskor:
    %       P_bess_dc <= P_inv_limit_ac / eta_inv - P_pv_dc
    %
    %   tolteskor:
    %       P_bess_dc >= -P_inv_limit_ac * eta_inv - P_pv_dc

    P_pv_dc_for_limit = max(P_pv_dc, 0);

    for t = 1:N

        if P_bess_dc_req(t) > 0

            P_dis_available_by_inv = ...
                pars.P_inv_limit_ac / eta_inv - P_pv_dc_for_limit(t);

            P_dis_available_by_inv = max(P_dis_available_by_inv, 0);

            P_bess_dc_req(t) = min( ...
                P_bess_dc_req(t), ...
                P_dis_available_by_inv);
        end

        if P_bess_dc_req(t) < 0

            P_ch_available_by_inv = ...
                pars.P_inv_limit_ac * eta_inv + P_pv_dc_for_limit(t);

            P_bess_dc_req(t) = max( ...
                P_bess_dc_req(t), ...
               -P_ch_available_by_inv);
        end
    end

    % =====================================================================
    % 4) Numerikus zaj nullazasa
    % =====================================================================

    P_bess_dc_req(abs(P_bess_dc_req) < 1e-6) = 0;
end


function referenceSide = local_get_plan_reference_side(plan)
% LOCAL_GET_PLAN_REFERENCE_SIDE
%
% Alapertelmezes:
%   "dc_bus"
%
% Ez az uj DC MILP-hez illeszkedik.
%
% Opcionális kompatibilitás:
%   plan.P_bess_plan_reference_side = "ac_bus"
%   plan.P_bess_plan_reference_side = "dc_bus"

    referenceSide = "dc_bus";

    if isfield(plan, 'P_bess_plan_reference_side')
        referenceSide = lower(string(plan.P_bess_plan_reference_side));
    elseif isfield(plan, 'powerReferenceSide')
        referenceSide = lower(string(plan.powerReferenceSide));
    elseif isfield(plan, 'P_ch_plan_side')
        referenceSide = lower(string(plan.P_ch_plan_side));
    elseif isfield(plan, 'P_ch_plan_is_dc_bus')
        if logical(plan.P_ch_plan_is_dc_bus)
            referenceSide = "dc_bus";
        else
            referenceSide = "ac_bus";
        end
    end

    if referenceSide == "dc" || ...
       referenceSide == "dc_side" || ...
       referenceSide == "dc-bus" || ...
       referenceSide == "bess_dc"

        referenceSide = "dc_bus";
    end

    if referenceSide == "ac" || ...
       referenceSide == "ac_side" || ...
       referenceSide == "ac-bus"

        referenceSide = "ac_bus";
    end
end


function v = local_row_vector_to_length(x, N, name)
% LOCAL_ROW_VECTOR_TO_LENGTH
%
% A bemeneti vektort sorvektorra alakitja es ellenorzi a hosszat.
% Nem vagja, nem tolti ki, mert az elfedne a planner/execution hibakat.

    v = x(:).';

    if numel(v) ~= N
        error('%s length differs from realtime horizon length. Expected %d, got %d.', ...
            name, N, numel(v));
    end
end