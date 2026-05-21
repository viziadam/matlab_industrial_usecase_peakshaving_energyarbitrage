% function P_bess_ac_req_kW = ems_realtime_decision_ac( ...
%     P_pv_dc, P_load_actual, plan, pars)
% % EMS_REALTIME_DECISION_AC
% %
% % AC-csatolt BESS realtime parancs.
% %
% % Jelkonvenció:
% %   pozitív  -> kisütés az AC buszra
% %   negatív  -> töltés az AC buszról
% 
%     %#ok<INUSD>
% 
%     requiredPlanFields = {'P_ch_plan', 'P_dis_plan'};
% 
%     for i = 1:numel(requiredPlanFields)
%         if ~isfield(plan, requiredPlanFields{i})
%             error('Hiányzó plan mező az AC realtime döntéshez: plan.%s', ...
%                 requiredPlanFields{i});
%         end
%     end
% 
%     requiredParsFields = {'P_chg_max', 'P_dis_max'};
% 
%     for i = 1:numel(requiredParsFields)
%         if ~isfield(pars, requiredParsFields{i})
%             error('Hiányzó pars mező az AC realtime döntéshez: pars.%s', ...
%                 requiredParsFields{i});
%         end
%     end
% 
%     P_ch_ac  = plan.P_ch_plan(:).';
%     P_dis_ac = plan.P_dis_plan(:).';
% 
%     if numel(P_ch_ac) ~= numel(P_dis_ac)
%         error('A plan.P_ch_plan és plan.P_dis_plan hossza eltér AC realtime döntésnél.');
%     end
% 
%     P_bess_ac_req_kW = P_dis_ac - P_ch_ac;
% 
%     P_bess_ac_req_kW = min(P_bess_ac_req_kW,  pars.P_dis_max);
%     P_bess_ac_req_kW = max(P_bess_ac_req_kW, -pars.P_chg_max);
% 
%     P_bess_ac_req_kW(abs(P_bess_ac_req_kW) < 1e-6) = 0;
% end

function P_bess_ac_req_kW = ems_realtime_decision_ac( ...
    P_pv_dc, P_load_actual, plan, pars)
% EMS_REALTIME_DECISION_AC
%
% AC-csatolt BESS realtime parancs.
%
% Jelkonvenció:
%   pozitív  -> BESS kisütés az AC buszra
%   negatív  -> BESS töltés az AC buszról

    %#ok<INUSD>

    requiredPlanFields = {'P_ch_plan', 'P_dis_plan'};

    for i = 1:numel(requiredPlanFields)
        if ~isfield(plan, requiredPlanFields{i})
            error('Hiányzó plan mező az AC realtime döntéshez: plan.%s', ...
                requiredPlanFields{i});
        end
    end

    requiredParsFields = {'P_chg_max', 'P_dis_max', 'pcs_eta_nom'};

    for i = 1:numel(requiredParsFields)
        if ~isfield(pars, requiredParsFields{i})
            error('Hiányzó pars mező az AC realtime döntéshez: pars.%s', ...
                requiredParsFields{i});
        end
    end

    P_pv_dc = P_pv_dc(:).';
    N = numel(P_pv_dc);

    P_ch_ac  = plan.P_ch_plan(:).';
    P_dis_ac = plan.P_dis_plan(:).';

    if numel(P_ch_ac) ~= N || numel(P_dis_ac) ~= N
        error('A plan.P_ch_plan vagy plan.P_dis_plan hossza eltér AC realtime döntésnél.');
    end

    P_bess_ac_req_kW = P_dis_ac - P_ch_ac;

    etaPcsNom = max(pars.pcs_eta_nom, eps);

    P_chg_max_ac = pars.P_chg_max / etaPcsNom;
    P_dis_max_ac = pars.P_dis_max * etaPcsNom;

    P_bess_ac_req_kW = min(P_bess_ac_req_kW,  P_dis_max_ac);
    P_bess_ac_req_kW = max(P_bess_ac_req_kW, -P_chg_max_ac);

    P_bess_ac_req_kW(abs(P_bess_ac_req_kW) < 1e-6) = 0;
end