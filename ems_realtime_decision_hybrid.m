function req = ems_realtime_decision_hybrid(P_pv_dc, P_load_actual, plan, pars)
% EMS_REALTIME_DECISION_HYBRID
%
% Hybrid AC+DC BESS realtime parancs a hybrid MILP tervbol.
%
% Kimenet:
%   req.P_bess_dc_req_kW > 0  -> DC BESS kisutes a DC busz fele
%   req.P_bess_dc_req_kW < 0  -> DC BESS toltes
%   req.P_bess_ac_req_kW > 0  -> AC BESS kisutes az AC buszra
%   req.P_bess_ac_req_kW < 0  -> AC BESS toltes az AC buszrol

    %#ok<INUSD>

    P_pv_dc = P_pv_dc(:).';
    N = numel(P_pv_dc);

    requiredPlanFields = { ...
        'P_ch_dc_plan', ...
        'P_dis_dc_plan', ...
        'P_ch_ac_plan', ...
        'P_dis_ac_plan'};

    for i = 1:numel(requiredPlanFields)
        if ~isfield(plan, requiredPlanFields{i})
            error('Hianyzo plan mezo a hybrid realtime donteshez: plan.%s', requiredPlanFields{i});
        end
    end

    requiredParsFields = {'dc', 'ac'};

    for i = 1:numel(requiredParsFields)
        if ~isfield(pars, requiredParsFields{i})
            error('Hianyzo pars mezo a hybrid realtime donteshez: pars.%s', requiredParsFields{i});
        end
    end

    P_ch_dc = local_row_vector_to_length(plan.P_ch_dc_plan, N, 'plan.P_ch_dc_plan');
    P_dis_dc = local_row_vector_to_length(plan.P_dis_dc_plan, N, 'plan.P_dis_dc_plan');
    P_ch_ac = local_row_vector_to_length(plan.P_ch_ac_plan, N, 'plan.P_ch_ac_plan');
    P_dis_ac = local_row_vector_to_length(plan.P_dis_ac_plan, N, 'plan.P_dis_ac_plan');

    P_bess_dc_req_kW = P_dis_dc - P_ch_dc;
    P_bess_ac_req_kW = P_dis_ac - P_ch_ac;

    P_bess_dc_req_kW = min(P_bess_dc_req_kW,  pars.dc.P_dis_max);
    P_bess_dc_req_kW = max(P_bess_dc_req_kW, -pars.dc.P_chg_max);

    etaPcsNom = max(pars.pcs_eta_nom, eps);
    P_chg_max_ac = pars.ac.P_chg_max / etaPcsNom;
    P_dis_max_ac = pars.ac.P_dis_max * etaPcsNom;

    P_bess_ac_req_kW = min(P_bess_ac_req_kW,  P_dis_max_ac);
    P_bess_ac_req_kW = max(P_bess_ac_req_kW, -P_chg_max_ac);

    P_bess_dc_req_kW(abs(P_bess_dc_req_kW) < 1e-6) = 0;
    P_bess_ac_req_kW(abs(P_bess_ac_req_kW) < 1e-6) = 0;

    req = struct();
    req.P_bess_dc_req_kW = P_bess_dc_req_kW;
    req.P_bess_ac_req_kW = P_bess_ac_req_kW;
end


function v = local_row_vector_to_length(x, N, name)

    v = x(:).';

    if numel(v) ~= N
        error('%s length differs from realtime horizon length. Expected %d, got %d.', ...
            name, N, numel(v));
    end
end
