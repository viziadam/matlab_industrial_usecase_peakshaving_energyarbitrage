function month_selection = select_representative_contract_month(day_cache)
% SELECT_REPRESENTATIVE_CONTRACT_MONTH
%
% Contract search-hoz hasznalt reprezentans/stressz honap valasztasa.
%
% Ez a verzio nem atlagos honapot valaszt, hanem olyan teljes 30 napos
% honapot, amelynek a havi legnagyobb no-BESS grid peak erteke kozel van
% a havi maximum peak-ek 90. percentilisehez.
%
% Cel:
%   - ne egy atlagos honap alapjan legyen P_contract valasztas,
%   - de ne is a teljesen extrem outlier honap dominaljon,
%   - hanem egy magas terhelesu, robusztus stressz honap legyen az alap.
%
% Hasznalt peak:
%   day_cache(i).no_bess_peak
%
% Ez a BESS nelkuli napi halozati importcsucs, tehat contract sizing
% szempontbol jobb, mint a sima load peak.

    target_percentile = 100;
    month_days = 30;

    abs_days = [day_cache.abs_day];
    month_ids_all = arrayfun(@local_get_month_id_from_abs_day, abs_days);
    month_ids = unique(month_ids_all, 'stable');

    month_rows = struct( ...
        'month_id', {}, ...
        'day_indices', {}, ...
        'max_no_bess_peak_kW', {}, ...
        'p90_no_bess_peak_kW', {}, ...
        'p95_no_bess_peak_kW', {}, ...
        'mean_no_bess_peak_kW', {}, ...
        'grid_no_bess_energy_kWh', {}, ...
        'score', {});

    % =====================================================================
    % 1) Teljes 30 napos honapok osszegyujtese
    % =====================================================================
    for i = 1:numel(month_ids)

        month_id = month_ids(i);
        day_indices = find(month_ids_all == month_id);

        if numel(day_indices) ~= month_days
            continue;
        end

        row = local_build_month_peak_row(day_cache, month_id, day_indices);
        month_rows(end + 1) = row; %#ok<AGROW>
    end

    if isempty(month_rows)
        error('Nincs teljes 30 napos honap a day_cache strukturaban.');
    end

    % =====================================================================
    % 2) Cel peak meghatarozasa
    % =====================================================================
    monthly_max_peaks = [month_rows.max_no_bess_peak_kW];

    target_peak_kW = prctile(monthly_max_peaks, target_percentile);

    % =====================================================================
    % 3) A target peakhez legkozelebbi honap valasztasa
    % =====================================================================
    for i = 1:numel(month_rows)

        peak_error = abs(month_rows(i).max_no_bess_peak_kW - target_peak_kW);

        % Masodlagos szempont:
        % ha ket honap max peakje hasonloan kozel van a targethez,
        % akkor az legyen jobb, amelyiknek a napi peak eloszlasa is magasabb.
        %
        % Ez elkeruli, hogy egyetlen tuskeszeru nap miatt valasszunk honapot.
        robustness_bonus = 0.05 * month_rows(i).p90_no_bess_peak_kW;

        month_rows(i).score = peak_error - robustness_bonus;
    end

    [best_score, idx_best] = min([month_rows.score]);

    selected = month_rows(idx_best);

    % =====================================================================
    % 4) Kimenet
    % =====================================================================
    month_selection = struct();

    month_selection.selection_mode = 'monthly_max_peak_near_p90';
    month_selection.target_percentile = target_percentile;
    month_selection.target_peak_kW = target_peak_kW;

    month_selection.month_id = selected.month_id;
    month_selection.day_indices = selected.day_indices;
    month_selection.score = best_score;

    month_selection.selected_max_no_bess_peak_kW = selected.max_no_bess_peak_kW;
    month_selection.selected_p90_no_bess_peak_kW = selected.p90_no_bess_peak_kW;
    month_selection.selected_p95_no_bess_peak_kW = selected.p95_no_bess_peak_kW;
    month_selection.selected_mean_no_bess_peak_kW = selected.mean_no_bess_peak_kW;
    month_selection.selected_grid_no_bess_energy_kWh = selected.grid_no_bess_energy_kWh;

    month_selection.all_month_ids = [month_rows.month_id];
    month_selection.all_month_max_no_bess_peak_kW = [month_rows.max_no_bess_peak_kW];
    month_selection.all_month_p90_no_bess_peak_kW = [month_rows.p90_no_bess_peak_kW];
    month_selection.all_month_p95_no_bess_peak_kW = [month_rows.p95_no_bess_peak_kW];
    month_selection.all_scores = [month_rows.score];

    fprintf('\n--- Representative contract month selected ---\n');
    fprintf('Selection mode: monthly max no-BESS peak near P%d\n', target_percentile);
    fprintf('Target peak: %.2f kW\n', target_peak_kW);
    fprintf('Selected month id: %d\n', month_selection.month_id);
    fprintf('Selected days: %d ... %d\n', ...
        day_cache(month_selection.day_indices(1)).abs_day, ...
        day_cache(month_selection.day_indices(end)).abs_day);
    fprintf('Selected max no-BESS peak: %.2f kW\n', ...
        month_selection.selected_max_no_bess_peak_kW);
    fprintf('Selected p90 no-BESS daily peak: %.2f kW\n', ...
        month_selection.selected_p90_no_bess_peak_kW);
    fprintf('Selected p95 no-BESS daily peak: %.2f kW\n', ...
        month_selection.selected_p95_no_bess_peak_kW);
    fprintf('----------------------------------------------\n');
end


function row = local_build_month_peak_row(day_cache, month_id, day_indices)
% LOCAL_BUILD_MONTH_PEAK_ROW
%
% Egy teljes honap contract-sizing szempontu peak jellemzoit szamolja.

    no_bess_peaks = zeros(numel(day_indices), 1);
    grid_no_bess_energy_kWh = 0;

    for kk = 1:numel(day_indices)

        day_idx = day_indices(kk);
        dc = day_cache(day_idx);

        no_bess_peaks(kk) = dc.no_bess_peak;

        grid_no_bess_energy_kWh = grid_no_bess_energy_kWh + ...
            sum(dc.P_grid_no_bess_day(:)) * dc.dt_h;
    end

    row = struct();

    row.month_id = month_id;
    row.day_indices = day_indices;

    row.max_no_bess_peak_kW = max(no_bess_peaks);
    row.p90_no_bess_peak_kW = prctile(no_bess_peaks, 90);
    row.p95_no_bess_peak_kW = prctile(no_bess_peaks, 95);
    row.mean_no_bess_peak_kW = mean(no_bess_peaks);

    row.grid_no_bess_energy_kWh = grid_no_bess_energy_kWh;

    row.score = NaN;
end


function month_id = local_get_month_id_from_abs_day(abs_day)
% LOCAL_GET_MONTH_ID_FROM_ABS_DAY
%
% A jelenlegi szimulacios keret 30 napos honapokkal dolgozik.

    month_id = floor((abs_day - 1) / 30) + 1;
end