function month_selection = select_representative_contract_month(day_cache)
% SELECT_REPRESENTATIVE_CONTRACT_MONTH
%
% Teljes, 30 napos honapok kozul valaszt reprezentans honapot.
%
% A modszer:
%   1) a day_cache abs_day mezoje alapjan 30 napos honapblokkokat kepez,
%   2) csak teljes 30 napos honapokat enged be,
%   3) minden honapra feature-vektort szamol,
%   4) a feature-eket standardizalja,
%   5) a standardizalt feature-ter median honapprofiljahoz legkozelebbi
%      honapot valasztja.
%
% Ez medoid jellegu valasztas: nem atlaghonapot general, hanem egy valodi,
% tenylegesen letezo honapot ad vissza.

    abs_days = [day_cache.abs_day];
    month_ids_all = arrayfun(@local_get_month_id_from_abs_day, abs_days);
    month_ids = unique(month_ids_all, 'stable');

    month_rows = struct( ...
        'month_id', {}, ...
        'day_indices', {}, ...
        'features', {});

    for i = 1:numel(month_ids)

        month_id = month_ids(i);
        day_indices = find(month_ids_all == month_id);

        if numel(day_indices) == 30

            row = struct();
            row.month_id = month_id;
            row.day_indices = day_indices;
            row.features = local_month_features(day_cache, day_indices);

            month_rows(end + 1) = row; %#ok<AGROW>
        end
    end

    if isempty(month_rows)
        error('Nincs teljes 30 napos honap a day_cache strukturaban.');
    end

    X = vertcat(month_rows.features);

    feature_names = local_month_feature_names();
    [Z, active_feature_mask] = local_standardize_month_features(X);

    target = median(Z, 1);
    score = sum((Z - target).^2, 2);

    [best_score, idx_best] = min(score);

    month_selection = struct();

    month_selection.month_id = month_rows(idx_best).month_id;
    month_selection.day_indices = month_rows(idx_best).day_indices;
    month_selection.score = best_score;

    month_selection.feature_matrix = X;
    month_selection.feature_names = feature_names;
    month_selection.active_feature_mask = active_feature_mask;

    month_selection.all_month_ids = [month_rows.month_id];
    month_selection.all_scores = score(:).';
end


function feature_row = local_month_features(day_cache, day_indices)
% LOCAL_MONTH_FEATURES
%
% Egy teljes honap jellemzoi.
%
% A feature-ek ugy vannak valasztva, hogy a contract-kereses szempontjabol
% lenyeges tenyezoket fedjek le:
%   - energiaigeny,
%   - PV-termeles,
%   - BESS nelkuli halozati energia,
%   - napi csucsok,
%   - arszint,
%   - napi aringadozas.

    load_energy_kWh = 0;
    pv_energy_kWh = 0;
    grid_no_bess_energy_kWh = 0;

    no_bess_peaks = zeros(numel(day_indices), 1);
    load_peaks = zeros(numel(day_indices), 1);
    price_mean_days = zeros(numel(day_indices), 1);
    price_spread_days = zeros(numel(day_indices), 1);

    for kk = 1:numel(day_indices)

        dc = day_cache(day_indices(kk));

        P_load = dc.P_load_actual(:);
        P_pv = dc.P_pv_dc_actual(:);
        P_grid_no_bess = dc.P_grid_no_bess_day(:);
        buy_price = dc.Prices_today.buy_huf(:);

        load_energy_kWh = load_energy_kWh + sum(P_load) * dc.dt_h;
        pv_energy_kWh = pv_energy_kWh + sum(P_pv) * dc.dt_h;
        grid_no_bess_energy_kWh = grid_no_bess_energy_kWh + ...
            sum(P_grid_no_bess) * dc.dt_h;

        no_bess_peaks(kk) = dc.no_bess_peak;
        load_peaks(kk) = max(P_load);

        price_mean_days(kk) = mean(buy_price);
        price_spread_days(kk) = max(buy_price) - min(buy_price);
    end

    feature_row = [ ...
        load_energy_kWh, ...
        pv_energy_kWh, ...
        grid_no_bess_energy_kWh, ...
        max(load_peaks), ...
        max(no_bess_peaks), ...
        prctile(no_bess_peaks, 95), ...
        mean(no_bess_peaks), ...
        mean(price_mean_days), ...
        mean(price_spread_days)];
end


function feature_names = local_month_feature_names()

    feature_names = { ...
        'load_energy_kWh', ...
        'pv_energy_kWh', ...
        'grid_no_bess_energy_kWh', ...
        'max_load_peak_kW', ...
        'max_no_bess_peak_kW', ...
        'p95_no_bess_daily_peak_kW', ...
        'mean_no_bess_daily_peak_kW', ...
        'mean_buy_price_huf_per_kWh', ...
        'mean_daily_price_spread_huf_per_kWh'};
end


function [Z, active_feature_mask] = local_standardize_month_features(X)
% LOCAL_STANDARDIZE_MONTH_FEATURES
%
% Standardizalas csak a valtozo feature-oszlopokra.
%
% Ha egy feature minden honapban azonos, akkor nem segit a honapok
% megkulonbozteteseben. Ezert azt nem hasznaljuk a tavolsagszamitasban.

    mu = mean(X, 1);
    sigma = std(X, 0, 1);

    active_feature_mask = sigma > 1e-12;

    if ~any(active_feature_mask)
        error('A havi feature-matrix egyetlen valtozo oszlopot sem tartalmaz.');
    end

    X_active = X(:, active_feature_mask);
    mu_active = mu(active_feature_mask);
    sigma_active = sigma(active_feature_mask);

    Z = (X_active - mu_active) ./ sigma_active;
end


function month_id = local_get_month_id_from_abs_day(abs_day)
% LOCAL_GET_MONTH_ID_FROM_ABS_DAY
%
% A jelenlegi szimulacios keret 30 napos honapokkal dolgozik.

    month_id = floor((abs_day - 1) / 30) + 1;
end