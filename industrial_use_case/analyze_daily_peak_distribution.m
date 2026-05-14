function stats = analyze_daily_peak_distribution(daily_peak_no_bess, P_bess_max)
% ANALYZE_DAILY_PEAK_DISTRIBUTION
% A no-BESS napi peak eloszlásából képez keresési statisztikákat.
%
% Bemenet:
%   daily_peak_no_bess : napi peak-ek [kW]
%   P_bess_max         : BESS max kisütési teljesítmény [kW]
%
% Kimenet:
%   stats struct mezői:
%       min, p50, p75, p80, p85, p90, p95, p97, p99, max, mean, std
%       search_low_kW
%       search_high_kW
%       initial_guess_kW

    x = daily_peak_no_bess(:);

    if isempty(x)
        error('analyze_daily_peak_distribution: empty input vector');
    end

    stats = struct();
    stats.min  = min(x);
    stats.p50  = prctile(x, 50);
    stats.p75  = prctile(x, 75);
    stats.p80  = prctile(x, 80);
    stats.p85  = prctile(x, 85);
    stats.p90  = prctile(x, 90);
    stats.p95  = prctile(x, 95);
    stats.p97  = prctile(x, 97);
    stats.p99  = prctile(x, 99);
    stats.max  = max(x);
    stats.mean = mean(x);
    stats.std  = std(x);

    % Konzervatív, de már nem túl tág keresési intervallum
    search_low  = max(stats.p80, stats.p90 - 0.20 * P_bess_max);
    search_high = stats.p97;

    stats.search_low_kW  = 10 * floor(search_low  / 10);
    stats.search_high_kW = 10 * ceil(search_high / 10);

    if stats.search_high_kW <= stats.search_low_kW
        stats.search_high_kW = stats.search_low_kW + 20;
    end

    stats.initial_guess_kW = 10 * round(stats.p90 / 10);
end