function overview = plot_industrial_case_overview(cfg, industrialCtx)
% PLOT_INDUSTRIAL_CASE_OVERVIEW
%
% Ipari pelda bemutatasahoz keszit egy osszefoglalo abrat.
%
% Az abra egy figure-ben tartalmazza:
%   1) atlagos napi load profilt,
%   2) napi maximalis teljesitmenycsucsokat,
%   3) havi PV energiatermelest.
%
% Bemenet:
%   cfg           - create_configurations kimenete
%   industrialCtx - prepare_industrial_simulation_context kimenete
%
% A fuggveny a day_cache struktura mentett napi adatait hasznalja.

    if nargin < 2
        error('Missing input: cfg and industrialCtx are required.');
    end

    if ~isfield(cfg, 'paths') || ~isfield(cfg.paths, 'results')
        error('Missing cfg.paths.results.');
    end

    if ~isfield(industrialCtx, 'day_cache')
        error('Missing industrialCtx.day_cache.');
    end

    day_cache = industrialCtx.day_cache;
    nDays = numel(day_cache);

    if nDays < 1
        error('industrialCtx.day_cache is empty.');
    end

    requiredDayFields = { ...
        'abs_day', ...
        'dt_h', ...
        'P_load_actual', ...
        'P_pv_dc_actual', ...
        'P_grid_no_bess_day', ...
        'no_bess_peak'};

    for d = 1:nDays
        for k = 1:numel(requiredDayFields)
            if ~isfield(day_cache(d), requiredDayFields{k})
                error('Missing day_cache(%d).%s.', d, requiredDayFields{k});
            end
        end
    end

    nT = numel(day_cache(1).P_load_actual);
    dt_h = day_cache(1).dt_h;
    t_h = (0:nT-1).' * dt_h;

    loadMat = NaN(nT, nDays);
    pvMat = NaN(nT, nDays);
    gridNoBessMat = NaN(nT, nDays);

    absDays = NaN(nDays, 1);
    dailyLoadPeak = NaN(nDays, 1);
    dailyGridNoBessPeak = NaN(nDays, 1);
    dailyPvEnergy = NaN(nDays, 1);
    dailyLoadEnergy = NaN(nDays, 1);

    for d = 1:nDays

        if numel(day_cache(d).P_load_actual) ~= nT
            error('Inconsistent P_load_actual length at day %d.', d);
        end

        if numel(day_cache(d).P_pv_dc_actual) ~= nT
            error('Inconsistent P_pv_dc_actual length at day %d.', d);
        end

        if numel(day_cache(d).P_grid_no_bess_day) ~= nT
            error('Inconsistent P_grid_no_bess_day length at day %d.', d);
        end

        Pload = day_cache(d).P_load_actual(:);
        Ppv = day_cache(d).P_pv_dc_actual(:);
        PgridNoBess = day_cache(d).P_grid_no_bess_day(:);

        loadMat(:, d) = Pload;
        pvMat(:, d) = Ppv;
        gridNoBessMat(:, d) = PgridNoBess;

        absDays(d) = day_cache(d).abs_day;
        dailyLoadPeak(d) = max(Pload);
        dailyGridNoBessPeak(d) = day_cache(d).no_bess_peak;
        dailyPvEnergy(d) = sum(Ppv) * dt_h;
        dailyLoadEnergy(d) = sum(Pload) * dt_h;
    end

    meanLoadProfile = mean(loadMat, 2, 'omitnan');
    p10LoadProfile = prctile(loadMat, 10, 2);
    p90LoadProfile = prctile(loadMat, 90, 2);

    monthIndex = floor((absDays - 1) / 30) + 1;
    nMonths = max(monthIndex);

    monthlyPvEnergy = accumarray(monthIndex, dailyPvEnergy, [nMonths, 1], @sum, NaN);
    monthlyLoadEnergy = accumarray(monthIndex, dailyLoadEnergy, [nMonths, 1], @sum, NaN);
    monthlyPeak = accumarray(monthIndex, dailyGridNoBessPeak, [nMonths, 1], @max, NaN);

    outFolder = fullfile(cfg.paths.results, 'industrial_case_overview');

    if ~exist(outFolder, 'dir')
        mkdir(outFolder);
    end

    fig = figure('Name', 'Industrial case overview', 'Position', [100, 80, 1350, 950]);

    % =====================================================================
    % 1) Average daily load profile
    % =====================================================================
    subplot(3,1,1);
    hold on;
    grid on;

    fill([t_h; flipud(t_h)], ...
         [p10LoadProfile; flipud(p90LoadProfile)], ...
         [0.85 0.85 0.85], ...
         'EdgeColor', 'none', ...
         'DisplayName', '10-90% tartomany');

    plot(t_h, meanLoadProfile, 'k-', ...
        'LineWidth', 1.8, ...
        'DisplayName', 'Atlagos napi load');

    xlabel('Ido [h]');
    ylabel('Teljesitmeny [kW]');
    title('Atlagos napi fogyasztasi profil');
    xlim([0 24]);
    legend('Location', 'best');

    % =====================================================================
    % 2) Daily maximum peaks
    % =====================================================================
    subplot(3,1,2);
    hold on;
    grid on;

    plot(absDays, dailyGridNoBessPeak, 'b-', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'Napi max. halozati import BESS nelkul');

    plot(absDays, dailyLoadPeak, 'k:', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'Napi max. fogyasztas');

    yline(prctile(dailyGridNoBessPeak, 90), 'r--', ...
        'LineWidth', 1.2, ...
        'DisplayName', '90. percentilis');

    xlabel('Nap index');
    ylabel('Teljesitmeny [kW]');
    title('Napi maximalis teljesitmenycsucsok');
    legend('Location', 'best');

    % =====================================================================
    % 3) Monthly PV and load energy
    % =====================================================================
    subplot(3,1,3);
    hold on;
    grid on;

    bar(1:nMonths, [monthlyPvEnergy(:), monthlyLoadEnergy(:)] / 1000, 'grouped');

    yyaxis right;
    plot(1:nMonths, monthlyPeak, 'k-o', ...
        'LineWidth', 1.2, ...
        'MarkerSize', 3, ...
        'DisplayName', 'Havi max. import peak');
    ylabel('Havi peak [kW]');

    yyaxis left;
    ylabel('Energia [MWh/month]');
    xlabel('Honap index');
    title('Havi PV energia, fogyasztasi energia es havi peak');
    legend({'PV energia', 'Fogyasztasi energia', 'Havi max. import peak'}, ...
        'Location', 'best');

    savefig(fig, fullfile(outFolder, 'industrial_case_overview.fig'));

    try
        exportgraphics(fig, fullfile(outFolder, 'industrial_case_overview.png'), 'Resolution', 150);
    catch
        saveas(fig, fullfile(outFolder, 'industrial_case_overview.png'));
    end

    overview = struct();
    overview.figure = fig;
    overview.outputFolder = outFolder;
    overview.absDays = absDays;
    overview.t_h = t_h;
    overview.meanLoadProfile = meanLoadProfile;
    overview.p10LoadProfile = p10LoadProfile;
    overview.p90LoadProfile = p90LoadProfile;
    overview.dailyLoadPeak = dailyLoadPeak;
    overview.dailyGridNoBessPeak = dailyGridNoBessPeak;
    overview.dailyPvEnergy = dailyPvEnergy;
    overview.dailyLoadEnergy = dailyLoadEnergy;
    overview.monthlyPvEnergy = monthlyPvEnergy;
    overview.monthlyLoadEnergy = monthlyLoadEnergy;
    overview.monthlyPeak = monthlyPeak;

    save(fullfile(outFolder, 'industrial_case_overview_data.mat'), ...
        'overview', ...
        '-v7.3');

    fprintf('\nIndustrial case overview saved:\n%s\n', outFolder);
end
