function search_result = search_optimal_contract_capacity( ...
    day_cache, rep_set_proxy, rep_set_valid, pars, tariff, search_cfg)
% SEARCH_OPTIMAL_CONTRACT_CAPACITY
%
% Lekotott teljesitmeny optimalizalasa reprezentans honap alapjan.
% DC/AC esetben a megszokott havi evaluator fut, hybrid esetben pedig a
% hybrid AC+DC BESS evaluator.

    %#ok<INUSD>

    contract_min_kW = search_cfg.contract_min_kW;
    contract_max_kW = search_cfg.contract_max_kW;
    final_interval_kW = search_cfg.final_interval_kW;
    fine_step_kW = search_cfg.fine_step_kW;
    verbose = search_cfg.verbose;

    month_selection = select_representative_contract_month(day_cache);
    month_day_indices = month_selection.day_indices;

    manual_extra_abs_days = 2156:2160;

    extra_day_indices = find(ismember([day_cache.abs_day], manual_extra_abs_days));

    month_day_indices = unique([ ...
        month_day_indices(:); ...
        extra_day_indices(:)], 'stable');

    isHybrid = local_is_hybrid(search_cfg);

    pars_search = pars;

    if isHybrid
        pars_search.dc.E_cap_nom_original = pars.dc.E_cap_nom;
        pars_search.ac.E_cap_nom_original = pars.ac.E_cap_nom;

        pars_search.dc.E_cap_nom = pars.dc.E_cap_nom * search_cfg.E_cap_factor;
        pars_search.ac.E_cap_nom = pars.ac.E_cap_nom * search_cfg.E_cap_factor;
    
        pars_search.dc.C_chg_abs_max = pars_search.dc.P_chg_max / max(pars_search.dc.E_cap_nom, eps);
        pars_search.dc.C_dis_abs_max = pars_search.dc.C_chg_abs_max;

        pars_search.ac.C_chg_abs_max = pars_search.ac.P_chg_max / max(pars_search.ac.E_cap_nom, eps);
        pars_search.ac.C_dis_abs_max = pars_search.ac.C_chg_abs_max;
    else
        pars_search.E_cap_nom_original = pars.E_cap_nom;

        pars_search.E_cap_nom = pars.E_cap_nom * search_cfg.E_cap_factor;

        pars_search.C_chg_abs_max = pars_search.P_chg_max / max(pars_search.E_cap_nom, eps);
        pars_search.C_dis_abs_max = pars_search.C_chg_abs_max;
    end

    if verbose
        fprintf('\n=== CONTRACT SEARCH ON REPRESENTATIVE MONTH ===\n');
        fprintf('Coupling: %s\n', upper(string(search_cfg.system.bessCoupling)));
        fprintf('Search range: [%.0f, %.0f] kW\n', contract_min_kW, contract_max_kW);
        fprintf('Representative month id: %d\n', month_selection.month_id);
        fprintf('Representative month days: %d ... %d\n', ...
            day_cache(month_day_indices(1)).abs_day, ...
            day_cache(month_day_indices(end)).abs_day);
        fprintf('Representative month score: %.6f\n', month_selection.score);
    end

    cost_fun = @(contract_candidate_kW) local_simulate_month_for_contract( ...
        isHybrid, ...
        day_cache, ...
        month_day_indices, ...
        pars_search, ...
        tariff, ...
        contract_candidate_kW, ...
        search_cfg, ...
        false);

    search_log = local_contract_search_interval_halving( ...
        [contract_min_kW, contract_max_kW], ...
        final_interval_kW, ...
        fine_step_kW, ...
        cost_fun, ...
        verbose);

    best_contract_kW = search_log.best_contract_kW;

    if verbose
        fprintf('\n=== CONTRACT SEARCH FINISHED ===\n');
        fprintf('Best P_contract: %.0f kW\n', best_contract_kW);
        fprintf('Best representative-month cost: %.2f HUF\n', search_log.best_cost_huf);
    end

    t_detail = tic;

    best_detail = local_simulate_month_for_contract( ...
        isHybrid, ...
        day_cache, ...
        month_day_indices, ...
        pars_search, ...
        tariff, ...
        best_contract_kW, ...
        search_cfg, ...
        true);

    best_detail.runtime_s = toc(t_detail);

    search_result = struct();
    search_result.best_contract_kW = best_contract_kW;
    search_result.proxy_history = search_log;
    search_result.validation_results = best_detail;
    search_result.best_validation_result = best_detail;
    search_result.contract_bounds_kW = [contract_min_kW, contract_max_kW];
    search_result.start_guess_kW = ...
        10 * round(((contract_min_kW + contract_max_kW) / 2) / 10);
    search_result.representative_month = month_selection;
    search_result.representative_month_day_indices = month_day_indices;
end


function result = local_simulate_month_for_contract( ...
    isHybrid, day_cache, month_day_indices, pars, tariff, contract_kW, search_cfg, store_detail)

    if isHybrid
        result = simulate_contract_month_for_capacity_hybrid( ...
            day_cache, ...
            month_day_indices, ...
            pars, ...
            tariff, ...
            contract_kW, ...
            search_cfg, ...
            store_detail);
    else
        result = simulate_contract_month_for_capacity( ...
            day_cache, ...
            month_day_indices, ...
            pars, ...
            tariff, ...
            contract_kW, ...
            search_cfg, ...
            store_detail);
    end
end


function isHybrid = local_is_hybrid(search_cfg)

    isHybrid = false;

    if isfield(search_cfg, 'system') && ...
       isfield(search_cfg.system, 'bessCoupling')
        isHybrid = lower(string(search_cfg.system.bessCoupling)) == "hybrid";
    end
end


function search_log = local_contract_search_interval_halving( ...
    bounds_kW, final_interval_kW, fine_step_kW, cost_fun, verbose)
% LOCAL_CONTRACT_SEARCH_INTERVAL_HALVING
% Egyszeru intervallumfelezes cache-elt koltsegkiertekelessel.

    history = struct( ...
    'contract_kW', {}, ...
    'total_cost_huf', {}, ...
    'energy_import_cost_huf', {}, ...
    'overrun_cost_huf', {}, ...
    'contract_cost_huf', {}, ...
    'stage', {});

    evaluated_contracts = [];
    evaluated_costs = [];
    evaluated_energy_import_costs = [];
    evaluated_overrun_costs = [];
    evaluated_contract_costs = [];

    function J = eval_cached(contract_kW, stage_name)

        contract_kW = 10 * round(contract_kW / 10);

        idx = find(abs(evaluated_contracts - contract_kW) < 1e-9, 1, 'first');

        if ~isempty(idx)
            J = evaluated_costs(idx);

            J_E = evaluated_energy_import_costs(idx);
            J_O = evaluated_overrun_costs(idx);
            J_T = evaluated_contract_costs(idx);

            if verbose
                fprintf(['  Cache: %.0f kW -> %.2f HUF ', ...
                    '| E: %.2f HUF | O: %.2f HUF | T: %.2f HUF\n'], ...
                    contract_kW, J, J_E, J_O, J_T);
            end

            return;
        end

        if verbose
            fprintf('  Evaluate: %.0f kW ... ', contract_kW);
        end

        t0 = tic;
        out = cost_fun(contract_kW);
        runtime_s = toc(t0);

        J = out.total_cost_period_huf;

        % -----------------------------------------------------------------
        % Actual topology-based cost components
        % -----------------------------------------------------------------
        % E: imported energy cost
        % O: overrun cost
        % T: contracted power cost
        % These values come from the monthly simulation result, not from the
        % internal MILP objective.
        % -----------------------------------------------------------------

        if isfield(out, 'energy_cost_period_huf')
            J_E = out.energy_cost_period_huf;
        else
            J_E = NaN;
        end

        if isfield(out, 'overrun_cost_period_huf')
            J_O = out.overrun_cost_period_huf;
        else
            J_O = NaN;
        end

        if isfield(out, 'contract_cost_period_huf')
            J_T = out.contract_cost_period_huf;
        else
            J_T = NaN;
        end

        if verbose
            fprintf(['%.2f HUF | E: %.2f HUF | O: %.2f HUF | T: %.2f HUF ', ...
                '| %.2f s\n'], ...
                J, J_E, J_O, J_T, runtime_s);
        end

        evaluated_contracts(end + 1) = contract_kW; %#ok<AGROW>
        evaluated_costs(end + 1) = J; %#ok<AGROW>
        evaluated_energy_import_costs(end + 1) = J_E; %#ok<AGROW>
        evaluated_overrun_costs(end + 1) = J_O; %#ok<AGROW>
        evaluated_contract_costs(end + 1) = J_T; %#ok<AGROW>

        row = struct();
        row.contract_kW = contract_kW;
        row.total_cost_huf = J;
        row.energy_import_cost_huf = J_E;
        row.overrun_cost_huf = J_O;
        row.contract_cost_huf = J_T;
        row.stage = char(stage_name);

        history(end + 1) = row; %#ok<AGROW>
    end

    L = 10 * round(bounds_kW(1) / 10);
    R = 10 * round(bounds_kW(2) / 10);

    while (R - L) > final_interval_kW

        M  = 10 * round(((L + R) / 2) / 10);
        ML = 10 * round(((L + M) / 2) / 10);
        MR = 10 * round(((M + R) / 2) / 10);

        points = unique([ML, M, MR]);

        if numel(points) < 3
            break;
        end

        if verbose
            fprintf('\nInterval: [%.0f, %.0f] kW | points: %.0f, %.0f, %.0f kW\n', ...
                L, R, ML, M, MR);
        end

        J_ML = eval_cached(ML, 'halving');
        J_M  = eval_cached(M,  'halving');
        J_MR = eval_cached(MR, 'halving');

        if J_ML <= J_M && J_ML <= J_MR
            R = M;
        elseif J_MR <= J_M && J_MR < J_ML
            L = M;
        else
            L = ML;
            R = MR;
        end

        L = 10 * round(L / 10);
        R = 10 * round(R / 10);

        if R <= L
            break;
        end
    end

    fine_candidates = unique(10 * round((L:fine_step_kW:R) / 10));

    if isempty(fine_candidates)
        fine_candidates = unique([L R]);
    end

    if verbose
        fprintf('\n--- Fine evaluation ---\n');
        fprintf('Candidates: ');
        fprintf('%.0f ', fine_candidates);
        fprintf('[kW]\n');
    end

    best_contract_kW = fine_candidates(1);
    best_cost_huf = inf;

    for contract_kW = fine_candidates
        J = eval_cached(contract_kW, 'fine');

        if J < best_cost_huf
            best_cost_huf = J;
            best_contract_kW = contract_kW;
        end
    end

    search_log = struct();
    search_log.history = history;
    search_log.best_contract_kW = best_contract_kW;
    search_log.best_cost_huf = best_cost_huf;
    search_log.final_interval_kW = [L, R];
end
