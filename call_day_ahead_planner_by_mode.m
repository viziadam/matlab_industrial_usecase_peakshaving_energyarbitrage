function plan_full = call_day_ahead_planner_by_mode( ...
    P_load_48h, ...
    P_pv_48h, ...
    Prices_48h, ...
    pars, ...
    tariff, ...
    dt_h, ...
    contract_state, ...
    target_step_min, ...
    dispatch_cfg)
% CALL_DAY_AHEAD_PLANNER_BY_MODE
%
% Kozponti planner-dispatcher.
%
% Topology szerint valaszt:
%   "dc", "ac", "hybrid"
%
% Objective mode szerint valaszt:
%   "peak_only", "energy_only", "combined"
%
% A hybrid AC+DC BESS uzem jelenleg csak combined modban engedelyezett.

    coupling = lower(string(dispatch_cfg.bessCoupling));
    objectiveMode = lower(string(dispatch_cfg.objectiveMode));

    switch coupling

        case "dc"

            switch objectiveMode

                case "peak_only"
                    plan_full = ems_day_ahead_planner_milp_peak_dc( ...
                        P_load_48h, P_pv_48h, Prices_48h, pars, tariff, ...
                        dt_h, contract_state, target_step_min);

                case "energy_only"
                    plan_full = ems_day_ahead_planner_milp_energy_dc( ...
                        P_load_48h, P_pv_48h, Prices_48h, pars, tariff, ...
                        dt_h, contract_state, target_step_min, dispatch_cfg);

                case "combined"
                    plan_full = ems_day_ahead_planner_milp_contract( ...
                        P_load_48h, P_pv_48h, Prices_48h, pars, tariff, ...
                        dt_h, contract_state, target_step_min);

                otherwise
                    error('Unknown dispatch objectiveMode for DC planner: %s', objectiveMode);
            end

        case "ac"

            switch objectiveMode

                case "peak_only"
                    plan_full = ems_day_ahead_planner_milp_peak_ac( ...
                        P_load_48h, P_pv_48h, Prices_48h, pars, tariff, ...
                        dt_h, contract_state, target_step_min);

                case "energy_only"
                    plan_full = ems_day_ahead_planner_milp_energy_ac( ...
                        P_load_48h, P_pv_48h, Prices_48h, pars, tariff, ...
                        dt_h, contract_state, target_step_min, dispatch_cfg);

                case "combined"
                    plan_full = ems_day_ahead_planner_milp_contract_ac( ...
                        P_load_48h, P_pv_48h, Prices_48h, pars, tariff, ...
                        dt_h, contract_state, target_step_min);

                otherwise
                    error('Unknown dispatch objectiveMode for AC planner: %s', objectiveMode);
            end

        case "hybrid"

            if objectiveMode ~= "combined"
                error('Hybrid AC+DC BESS planner is currently implemented only for combined mode.');
            end

            plan_full = ems_day_ahead_planner_milp_contract_hybrid( ...
                P_load_48h, P_pv_48h, Prices_48h, pars, tariff, ...
                dt_h, contract_state, target_step_min);

        otherwise

            error('Unknown bessCoupling mode: %s. Use "dc", "ac" or "hybrid".', coupling);
    end
end
