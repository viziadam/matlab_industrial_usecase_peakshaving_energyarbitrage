function industrialCtx = prepare_industrial_simulation_context(data, cfg)
% PREPARE_INDUSTRIAL_SIMULATION_CONTEXT
%
% Candidate-ek előtt egyszer fut.
%
% Feladata:
%   - data.days -> day_cache
%   - feature-k
%   - reprezentáns/proxy napok
%   - validációs napok
%   - tarifa
%   - search_cfg
%   - detail_cfg
%
% Itt nincs candidate-specifikus BESS méret.

    fprintf('\n=== INDUSTRIAL SIMULATION CONTEXT PREPARATION ===\n');

    requiredCfgFields = {'contractSearch', 'detail', 'system', 'dc', 'pvA', 'pvB', 'pv'};

    for i = 1:numel(requiredCfgFields)
        if ~isfield(cfg, requiredCfgFields{i})
            error('Hiányzó cfg mező: cfg.%s', requiredCfgFields{i});
        end
    end

    requiredDetailFields = { ...
        'max_representative_plots', ...
        'max_overrun_days', ...
        'overrun_tolerance_kW'};

    for i = 1:numel(requiredDetailFields)
        if ~isfield(cfg.detail, requiredDetailFields{i})
            error('Hiányzó cfg.detail mező: cfg.detail.%s', requiredDetailFields{i});
        end
    end

    % =====================================================================
    % 1) Day cache
    % =====================================================================
    day_cache = build_industrial_day_cache_from_framework(data, cfg);

    % =====================================================================
    % 2) Features
    % =====================================================================
    features = build_daily_features_4y(day_cache);

    % =====================================================================
    % 3) Proxy representative days
    % =====================================================================
    rep_cfg_proxy = struct();
    rep_cfg_proxy.n_typical = cfg.contractSearch.proxy.n_typical;
    rep_cfg_proxy.n_extreme = cfg.contractSearch.proxy.n_extreme;

    rep_set_proxy = local_select_representative_days_pattern_based( ...
        features, ...
        day_cache, ...
        rep_cfg_proxy);

    % =====================================================================
    % 4) Validation days
    % =====================================================================
    rep_cfg_valid = struct();
    rep_cfg_valid.n_clusters = cfg.contractSearch.validation.n_clusters;
    rep_cfg_valid.n_validation_days_total = ...
        cfg.contractSearch.validation.n_validation_days_total;
    rep_cfg_valid.n_extreme_force = ...
        cfg.contractSearch.validation.n_extreme_force;

    rep_set_valid = local_select_validation_days_pattern_based( ...
        features, ...
        day_cache, ...
        rep_cfg_valid);

    % =====================================================================
    % 5) Tariff
    % =====================================================================
    tariff = create_hungarian_mv_tariff_structure();

    % =====================================================================
    % 6) Search cfg
    % =====================================================================
    search_cfg = struct();

    search_cfg.coarse_step_kW = cfg.contractSearch.coarse_step_kW;
    search_cfg.fine_step_kW = cfg.contractSearch.fine_step_kW;
    search_cfg.validation_offsets_kW = cfg.contractSearch.validation_offsets_kW;

    % =====================================================================
    % 7) Detail cfg
    % =====================================================================
    detail_cfg = struct();

    detail_cfg.day_indices = unique([ ...
        rep_set_valid.extreme_day_indices(:); ...
        rep_set_valid.validation_day_indices(:)], 'stable');

    detail_cfg.max_representative_plots = cfg.detail.max_representative_plots;
    detail_cfg.max_overrun_days = cfg.detail.max_overrun_days;
    detail_cfg.overrun_tolerance_kW = cfg.detail.overrun_tolerance_kW;

    % =====================================================================
    % 8) Context
    % =====================================================================
    industrialCtx = struct();

    industrialCtx.day_cache = day_cache;
    industrialCtx.features = features;

    industrialCtx.rep_set_proxy = rep_set_proxy;
    industrialCtx.rep_set_valid = rep_set_valid;

    industrialCtx.tariff = tariff;
    industrialCtx.search_cfg = search_cfg;
    industrialCtx.detail_cfg = detail_cfg;

    industrialCtx.info = struct();
    industrialCtx.info.nDays = numel(day_cache);
    industrialCtx.info.nT = numel(day_cache(1).P_load_actual);
    industrialCtx.info.dt_h = day_cache(1).dt_h;
    industrialCtx.info.coupling = string(cfg.system.bessCoupling);
    industrialCtx.info.P_PV_A_kW = cfg.pvA.P_dc_kWp;
    industrialCtx.info.P_PV_B_kW = cfg.pvB.P_dc_kWp;
    industrialCtx.info.P_PV_kW = cfg.pv.P_total_dc_kWp;
    industrialCtx.info.P_inv_kW = cfg.dc.P_inv_kW;

    fprintf('Industrial context ready.\n');
    fprintf('Days: %d\n', industrialCtx.info.nDays);
    fprintf('Proxy days: %d\n', numel(rep_set_proxy.all_day_indices));
    fprintf('Validation days: %d\n', numel(rep_set_valid.validation_day_indices));
end

function day_cache = build_industrial_day_cache_from_framework(data, cfg)
% BUILD_INDUSTRIAL_DAY_CACHE_FROM_FRAMEWORK
%
% data.days -> day_cache átalakítás.
%
% Kötelező bemeneti mezők:
%   data.days(d).P_load_kW
%   data.days(d).P_pv_A_dc_kW
%   data.days(d).P_pv_B_dc_kW
%   data.days(d).Price.buy_huf
%   data.days(d).dt_h
%
% Nincs fallback, nincs automatikus becslés.

    if ~isfield(data, 'days')
        error('Hiányzó adatmező: data.days');
    end

    if numel(data.days) < 2
        error('Legalább 2 nap adat szükséges a 48 órás előretekintés miatt.');
    end

    if ~isfield(cfg, 'dc') || ~isfield(cfg.dc, 'inv_eta')
        error('Hiányzó cfg mező: cfg.dc.inv_eta');
    end

    inv_eta = cfg.dc.inv_eta;

    nDaysAvailable = numel(data.days) - 1;

    day_cache = repmat(struct(), 1, nDaysAvailable);

    requiredDayFields = { ...
        'P_load_kW', ...
        'P_pv_A_dc_kW', ...
        'P_pv_B_dc_kW', ...
        'Price', ...
        'dt_h'};

    for d = 1:numel(data.days)

        for f = 1:numel(requiredDayFields)

            fieldName = requiredDayFields{f};

            if ~isfield(data.days(d), fieldName)
                error('Hiányzó data.days(%d).%s mező.', d, fieldName);
            end
        end

        if ~isfield(data.days(d).Price, 'buy_huf')
            error('Hiányzó data.days(%d).Price.buy_huf mező.', d);
        end
    end

    for d = 1:nDaysAvailable

        today = data.days(d);
        tomorrow = data.days(d + 1);

        dt_h = today.dt_h;

        P_load_today = today.P_load_kW(:).';
        P_load_tomorrow = tomorrow.P_load_kW(:).';

        P_pv_dc_today = ...
            today.P_pv_A_dc_kW(:).' + today.P_pv_B_dc_kW(:).';

        P_pv_dc_tomorrow = ...
            tomorrow.P_pv_A_dc_kW(:).' + tomorrow.P_pv_B_dc_kW(:).';

        Prices_today = today.Price;
        Prices_tomorrow = tomorrow.Price;

        Prices_today.buy_huf = Prices_today.buy_huf(:).';
        Prices_tomorrow.buy_huf = Prices_tomorrow.buy_huf(:).';

        nT = numel(P_load_today);

        if numel(P_pv_dc_today) ~= nT
            error('A PV és load vektor hossza eltér a(z) %d. napon.', d);
        end

        if numel(Prices_today.buy_huf) ~= nT
            error('Az ár és load vektor hossza eltér a(z) %d. napon.', d);
        end

        if numel(P_load_tomorrow) ~= nT
            error('A mai és holnapi load vektor hossza eltér a(z) %d. napon.', d);
        end

        if numel(P_pv_dc_tomorrow) ~= nT
            error('A mai és holnapi PV vektor hossza eltér a(z) %d. napon.', d);
        end

        if numel(Prices_tomorrow.buy_huf) ~= nT
            error('A mai és holnapi árvektor hossza eltér a(z) %d. napon.', d);
        end

        P_load_48h = [P_load_today, P_load_tomorrow];
        P_pv_48h = [P_pv_dc_today, P_pv_dc_tomorrow];

        Prices_48h = struct();
        Prices_48h.buy_huf = [Prices_today.buy_huf, Prices_tomorrow.buy_huf];

        P_grid_no_bess_day = max(P_load_today - P_pv_dc_today * inv_eta, 0);

        day_cache(d).abs_day = d;
        day_cache(d).dt_h = dt_h;

        day_cache(d).P_pv_dc_actual = P_pv_dc_today;
        day_cache(d).P_load_actual = P_load_today;
        day_cache(d).Prices_today = Prices_today;

        day_cache(d).P_load_48h = P_load_48h;
        day_cache(d).P_pv_48h = P_pv_48h;
        day_cache(d).Prices_48h = Prices_48h;

        day_cache(d).P_grid_no_bess_day = P_grid_no_bess_day;
        day_cache(d).no_bess_peak = max(P_grid_no_bess_day);
    end
end


function [P_pv_dc_today, P_pv_dc_tomorrow] = local_get_pv_dc_vectors( ...
    today, tomorrow, cfg)

    if isfield(today, 'P_pv_A_dc_kW') && isfield(today, 'P_pv_B_dc_kW')

        P_pv_dc_today = ...
            today.P_pv_A_dc_kW(:).' + today.P_pv_B_dc_kW(:).';

        P_pv_dc_tomorrow = ...
            tomorrow.P_pv_A_dc_kW(:).' + tomorrow.P_pv_B_dc_kW(:).';

        return;
    end

    if isfield(today, 'P_pv_dc_kW')

        P_pv_dc_today = today.P_pv_dc_kW(:).';
        P_pv_dc_tomorrow = tomorrow.P_pv_dc_kW(:).';

        return;
    end

    if isfield(today, 'P_pv_base_kW')

        P_pv_total_kW = cfg.pv.P_total_dc_kWp;

        P_pv_dc_today = today.P_pv_base_kW(:).' * P_pv_total_kW;
        P_pv_dc_tomorrow = tomorrow.P_pv_base_kW(:).' * P_pv_total_kW;

        return;
    end

    error(['Nem található PV mező a data.days struktúrában. ', ...
           'Szükséges: P_pv_A_dc_kW/P_pv_B_dc_kW vagy P_pv_dc_kW vagy P_pv_base_kW.']);
end


function Prices = local_get_price_struct(dayStruct)

    Prices = struct();

    if isfield(dayStruct, 'Prices_today')
        Prices = dayStruct.Prices_today;
        Prices.buy_huf = Prices.buy_huf(:).';
        return;
    end

    if isfield(dayStruct, 'Price')
        Prices = dayStruct.Price;
        Prices.buy_huf = Prices.buy_huf(:).';
        return;
    end

    if isfield(dayStruct, 'buy_huf')
        Prices.buy_huf = dayStruct.buy_huf(:).';
        return;
    end

    if isfield(dayStruct, 'energy_price_huf_per_kWh')
        Prices.buy_huf = dayStruct.energy_price_huf_per_kWh(:).';
        return;
    end

    error(['Nem található napi energiaár mező. ', ...
           'Szükséges például: buy_huf vagy energy_price_huf_per_kWh.']);
end


function eta = local_get_inv_eta(cfg)

    if isfield(cfg, 'dc') && isfield(cfg.dc, 'inv_eta')
        eta = cfg.dc.inv_eta;
    elseif isfield(cfg, 'inverter') && isfield(cfg.inverter, 'etaMax')
        eta = cfg.inverter.etaMax;
    else
        eta = 0.97;
    end
end

function features = build_daily_features_4y(day_cache)

    nDays = numel(day_cache);
    X = zeros(nDays, 10);

    for i = 1:nDays
        dc = day_cache(i);

        P_load = dc.P_load_actual(:);
        P_pv   = dc.P_pv_dc_actual(:) * 0.97;
        P_grid = dc.P_grid_no_bess_day(:);
        p_buy  = dc.Prices_today.buy_huf(:);

        N = numel(P_load);
        time_h = (0:N-1)' * dc.dt_h;

        evening_mask = time_h >= 16 & time_h < 22;
        morning_mask = time_h >= 6 & time_h < 10;

        load_energy = sum(P_load) * dc.dt_h;
        load_peak   = max(P_load);
        load_mean   = mean(P_load);

        pv_energy = sum(P_pv) * dc.dt_h;
        pv_peak   = max(P_pv);

        grid_energy = sum(P_grid) * dc.dt_h;
        grid_peak   = max(P_grid);
        evening_grid_peak = max(P_grid(evening_mask));
        morning_grid_peak = max(P_grid(morning_mask));

        price_mean = mean(p_buy);
        price_spread = max(p_buy) - min(p_buy);

        X(i,:) = [ ...
            load_energy, ...
            load_peak, ...
            load_mean, ...
            pv_energy, ...
            pv_peak, ...
            grid_energy, ...
            grid_peak, ...
            evening_grid_peak, ...
            price_mean, ...
            price_spread ];
    end

    features = struct();
    features.raw = X;
    features.z   = local_zscore(X);
end


% =========================================================================
% 7 NAPOS SÚLYOZOTT PROXY HALMAZ
% =========================================================================
function rep_set = local_select_representative_days_pattern_based(features, day_cache, cfg)

    X = features.z;

    n_typical = cfg.n_typical;
    n_extreme = cfg.n_extreme;

    [cluster_id, centers] = local_kmeans_basic(X, n_typical, 50);

    typical_day_indices = zeros(1, n_typical);
    cluster_weights = zeros(1, n_typical);

    for k = 1:n_typical
        idx_k = find(cluster_id == k);
        cluster_weights(k) = numel(idx_k);

        if isempty(idx_k)
            typical_day_indices(k) = 1;
            continue;
        end

        Xk = X(idx_k,:);
        ck = centers(k,:);
        d2 = sum((Xk - ck).^2, 2);
        [~, imin] = min(d2);
        typical_day_indices(k) = idx_k(imin);
    end

    no_bess_peak = arrayfun(@(d) d.no_bess_peak, day_cache);
    [~, idx_sorted_peak] = sort(no_bess_peak, 'descend');

    extreme_day_indices = [];
    for j = 1:numel(idx_sorted_peak)
        cand = idx_sorted_peak(j);
        if ~ismember(cand, typical_day_indices)
            extreme_day_indices(end+1) = cand; %#ok<AGROW>
        end
        if numel(extreme_day_indices) >= n_extreme
            break;
        end
    end

    all_day_indices = [typical_day_indices, extreme_day_indices];

    extreme_weight_each = max(1, round(0.5 * mean(cluster_weights)));

    weights = [cluster_weights, repmat(extreme_weight_each, 1, numel(extreme_day_indices))];
    weights = weights / sum(weights);

    rep_set = struct();
    rep_set.cluster_id = cluster_id;
    rep_set.centers = centers;
    rep_set.typical_day_indices = typical_day_indices;
    rep_set.extreme_day_indices = extreme_day_indices;
    rep_set.all_day_indices = all_day_indices;
    rep_set.weights = weights;
end


% =========================================================================
% 20 NAPOS VALIDÁCIÓS HALMAZ
% =========================================================================
function rep_set = local_select_validation_days_pattern_based(features, day_cache, cfg)

    X = features.z;
    nDays = size(X,1);

    n_clusters = cfg.n_clusters;
    n_total = cfg.n_validation_days_total;
    n_extreme_force = cfg.n_extreme_force;

    [cluster_id, centers] = local_kmeans_basic(X, n_clusters, 50);

    cluster_sizes = zeros(1, n_clusters);
    for k = 1:n_clusters
        cluster_sizes(k) = sum(cluster_id == k);
    end
    cluster_frac = cluster_sizes / sum(cluster_sizes);

    raw_counts = cluster_frac * n_total;
    base_counts = floor(raw_counts);
    remainder = n_total - sum(base_counts);

    frac_part = raw_counts - base_counts;
    [~, idx_frac] = sort(frac_part, 'descend');

    cluster_sample_counts = base_counts;
    for j = 1:remainder
        cluster_sample_counts(idx_frac(j)) = cluster_sample_counts(idx_frac(j)) + 1;
    end

    for k = 1:n_clusters
        if cluster_sizes(k) > 0 && cluster_sample_counts(k) == 0
            cluster_sample_counts(k) = 1;
        end
    end

    while sum(cluster_sample_counts) > n_total
        eligible = find(cluster_sample_counts > 1);
        if isempty(eligible), break; end
        [~, imax] = max(cluster_sample_counts(eligible));
        cluster_sample_counts(eligible(imax)) = cluster_sample_counts(eligible(imax)) - 1;
    end

    no_bess_peak = arrayfun(@(d) d.no_bess_peak, day_cache);
    [~, idx_sorted_peak] = sort(no_bess_peak, 'descend');

    extreme_day_indices = unique(idx_sorted_peak(1:min(n_extreme_force, nDays)));

    validation_days = extreme_day_indices(:).';

    for k = 1:n_clusters
        idx_k = find(cluster_id == k);
        if isempty(idx_k)
            continue;
        end

        need_k = cluster_sample_counts(k);

        already_k = idx_k(ismember(idx_k, validation_days));
        n_already = numel(already_k);
        n_to_add = max(0, need_k - n_already);

        if n_to_add == 0
            continue;
        end

        Xk = X(idx_k,:);
        ck = centers(k,:);
        d2 = sum((Xk - ck).^2, 2);
        [~, order] = sort(d2, 'ascend');
        cand = idx_k(order);

        cand = cand(~ismember(cand, validation_days));
        cand = cand(1:min(n_to_add, numel(cand)));

        validation_days = [validation_days, cand(:).']; %#ok<AGROW>
    end

    if numel(validation_days) < n_total
        remaining = setdiff(1:nDays, validation_days, 'stable');
        n_missing = n_total - numel(validation_days);
        validation_days = [validation_days, remaining(1:min(n_missing, numel(remaining)))];
    end

    if numel(validation_days) > n_total
        [~, ord] = sort(no_bess_peak(validation_days), 'descend');
        validation_days = validation_days(ord);
        validation_days = validation_days(1:n_total);
    end

    validation_days = unique(validation_days, 'stable');

    if numel(validation_days) < n_total
        remaining = setdiff(1:nDays, validation_days, 'stable');
        n_missing = n_total - numel(validation_days);
        validation_days = [validation_days, remaining(1:min(n_missing, numel(remaining)))];
    end

    rep_set = struct();
    rep_set.cluster_id = cluster_id;
    rep_set.centers = centers;
    rep_set.cluster_sizes = cluster_sizes;
    rep_set.cluster_sample_counts = cluster_sample_counts;
    rep_set.extreme_day_indices = extreme_day_indices;
    rep_set.validation_day_indices = sort(validation_days(:).');
end

% =========================================================================
% SEGÉD NORMALIZÁLÁS ÉS KMEANS
% =========================================================================
function Z = local_zscore(X)

    mu = mean(X, 1);
    sig = std(X, 0, 1);

    if any(sig < 1e-12)
        zeroVarCols = find(sig < 1e-12);
        error('Nulla vagy közel nulla szórású feature oszlop(ok): %s', ...
            mat2str(zeroVarCols));
    end

    Z = (X - mu) ./ sig;
end


function [idx, centers] = local_kmeans_basic(X, K, maxIter)

    if nargin < 3
        error('local_kmeans_basic: hiányzó maxIter bemenet.');
    end

    [N, D] = size(X);

    if K <= 0 || K > N
        error('Érvénytelen klaszterszám. K = %d, N = %d.', K, N);
    end

    if maxIter <= 0
        error('maxIter legyen pozitív.');
    end

    rng(42);

    perm = randperm(N, K);
    centers = X(perm, :);

    idx = ones(N, 1);

    for it = 1:maxIter

        dist = zeros(N, K);

        for k = 1:K
            diff = X - centers(k, :);
            dist(:, k) = sum(diff.^2, 2);
        end

        [~, idx_new] = min(dist, [], 2);

        if all(idx_new == idx) && it > 1
            break;
        end

        idx = idx_new;

        new_centers = zeros(K, D);

        for k = 1:K

            members = X(idx == k, :);

            if isempty(members)
                error('Üres klaszter keletkezett a k-means során. K = %d, iteráció = %d.', ...
                    K, it);
            end

            new_centers(k, :) = mean(members, 1);
        end

        if max(abs(new_centers(:) - centers(:))) < 1e-8
            centers = new_centers;
            break;
        end

        centers = new_centers;
    end
end