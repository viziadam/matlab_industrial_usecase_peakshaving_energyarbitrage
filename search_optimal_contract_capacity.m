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

    isHybrid = local_is_hybrid(search_cfg);

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
        pars, ...
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
        pars, ...
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

    history = struct('contract_kW', {}, 'total_cost_huf', {}, 'stage', {});
    evaluated_contracts = [];
    evaluated_costs = [];

    function J = eval_cached(contract_kW, stage_name)

        contract_kW = 10 * round(contract_kW / 10);

        idx = find(abs(evaluated_contracts - contract_kW) < 1e-9, 1, 'first');

        if ~isempty(idx)
            J = evaluated_costs(idx);

            if verbose
                fprintf('  Cache: %.0f kW -> %.2f HUF\n', contract_kW, J);
            end

            return;
        end

        if verbose
            fprintf('  Evaluate: %.0f kW ... ', contract_kW);
        end

        t0 = tic;
        out = cost_fun(contract_kW);
        J = out.total_cost_period_huf;
        runtime_s = toc(t0);

        if verbose
            fprintf('%.2f HUF | %.2f s\n', J, runtime_s);
        end

        evaluated_contracts(end + 1) = contract_kW; %#ok<AGROW>
        evaluated_costs(end + 1) = J; %#ok<AGROW>

        row = struct();
        row.contract_kW = contract_kW;
        row.total_cost_huf = J;
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
