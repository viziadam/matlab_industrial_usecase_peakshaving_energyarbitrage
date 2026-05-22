function out = run_ac_dc_diagnostic_plots_from_saved_results(objectiveMode, candidateList)
% RUN_AC_DC_DIAGNOSTIC_PLOTS_FROM_SAVED_RESULTS
%
% Csak az AC/DC teljes idoszakos diagnosztikai osszehasonlito abrakat
% kesziti ujra a korabban elmentett eredmenyfajlokbol.
%
% Nem futtat szimulaciot, nem hivja az optimalizalot es nem modositja a
% candidate eredmenyeket.
%
% Pelda:
%   run_ac_dc_diagnostic_plots_from_saved_results("energy_only", 9)
%   run_ac_dc_diagnostic_plots_from_saved_results("combined", [9 12 15])

    if nargin < 1 || strlength(string(objectiveMode)) == 0
        objectiveMode = "energy_only";
    end

    if nargin < 2
        candidateList = [];
    end

    objectiveMode = lower(string(objectiveMode));

    if ~(objectiveMode == "peak_only" || objectiveMode == "energy_only" || objectiveMode == "combined")
        error('Invalid objectiveMode: %s', objectiveMode);
    end

    basePath = fileparts(mfilename('fullpath'));

    cfgBase = create_configurations(basePath);
    cfgBase.dispatch.objectiveMode = objectiveMode;
    cfgBase.paths.results = fullfile(cfgBase.paths.results, char(objectiveMode));

    dcPath = fullfile(cfgBase.paths.results, sprintf('results_dc_%s.mat', objectiveMode));
    acPath = fullfile(cfgBase.paths.results, sprintf('results_ac_%s.mat', objectiveMode));

    if ~exist(dcPath, 'file')
        error('Missing saved DC result file: %s', dcPath);
    end

    if ~exist(acPath, 'file')
        error('Missing saved AC result file: %s', acPath);
    end

    dcMetrics = load_canonical_candidate_metrics( ...
        cfgBase, ...
        objectiveMode, ...
        "dc", ...
        candidateList);

    acMetrics = load_canonical_candidate_metrics( ...
        cfgBase, ...
        objectiveMode, ...
        "ac", ...
        candidateList);

    Tdc = local_as_table(dcMetrics, "dcMetrics");
    Tac = local_as_table(acMetrics, "acMetrics");

    [Tdc, Tac, candidateListUsed] = local_align_dc_ac_tables(Tdc, Tac, candidateList);

    out = struct();
    out.objectiveMode = objectiveMode;
    out.candidateList = candidateListUsed;
    out.dcMetrics = Tdc;
    out.acMetrics = Tac;

    out.figures = struct();
    out.figures.lossComponents = local_plot_loss_components(Tdc, Tac);
    out.figures.energyPathEfficiency = local_plot_grid_and_bess_path_efficiency(Tdc, Tac);
    out.figures.pvToBessEfficiency = local_plot_pv_to_bess_efficiency(Tdc, Tac);
    out.figures.sohAndDegradation = local_plot_final_soh_and_degradation(Tdc, Tac, cfgBase);

    fprintf('\nAC/DC diagnostic plots regenerated from saved results only.\n');
    fprintf('No simulation was executed.\n');
end


% =========================================================================
% ADATOK ELOKESZITESE
% =========================================================================
function T = local_as_table(x, name)

    if istable(x)
        T = x;
        return;
    end

    if isstruct(x) && isfield(x, 'candidateMetrics')
        if istable(x.candidateMetrics)
            T = x.candidateMetrics;
            return;
        end
    end

    if isstruct(x)
        try
            T = struct2table(x);
            return;
        catch
            error('%s cannot be converted to table.', name);
        end
    end

    error('%s must be a table or a struct convertible to table.', name);
end


function [Tdc, Tac, candidateListUsed] = local_align_dc_ac_tables(Tdc, Tac, candidateList)

    if isempty(candidateList)
        n = min(height(Tdc), height(Tac));
        Tdc = Tdc(1:n, :);
        Tac = Tac(1:n, :);

        if ismember('candidateIndex', Tdc.Properties.VariableNames)
            candidateListUsed = Tdc.candidateIndex(:).';
        else
            candidateListUsed = 1:n;
        end

        return;
    end

    candidateList = candidateList(:).';

    if ismember('candidateIndex', Tdc.Properties.VariableNames) && ...
       ismember('candidateIndex', Tac.Properties.VariableNames)

        idxDc = zeros(numel(candidateList), 1);
        idxAc = zeros(numel(candidateList), 1);

        for i = 1:numel(candidateList)
            kDc = find(Tdc.candidateIndex == candidateList(i), 1, 'first');
            kAc = find(Tac.candidateIndex == candidateList(i), 1, 'first');

            if isempty(kDc)
                error('Candidate %d is missing from DC metrics.', candidateList(i));
            end

            if isempty(kAc)
                error('Candidate %d is missing from AC metrics.', candidateList(i));
            end

            idxDc(i) = kDc;
            idxAc(i) = kAc;
        end

        Tdc = Tdc(idxDc, :);
        Tac = Tac(idxAc, :);
        candidateListUsed = candidateList;

    else
        n = min([height(Tdc), height(Tac), numel(candidateList)]);
        Tdc = Tdc(1:n, :);
        Tac = Tac(1:n, :);
        candidateListUsed = candidateList(1:n);
    end
end


% =========================================================================
% 1) KONKRET KONVERTERVESZTESEG-KOMPONENSEK
% =========================================================================
function fig = local_plot_loss_components(Tdc, Tac)

    n = height(Tdc);
    [x, xDc, xAc] = local_pair_positions(n);

    Ydc_kWh = local_loss_component_matrix(Tdc);
    Yac_kWh = local_loss_component_matrix(Tac);

    Y_MWh = local_interleave_rows(Ydc_kWh, Yac_kWh) / 1000;

    componentNames = { ...
        'Central inv. DC->AC', ...
        'Central inv. AC->DC', ...
        'DC/DC charge', ...
        'DC/DC discharge', ...
        'PCS charge', ...
        'PCS discharge', ...
        'BESS internal charge', ...
        'BESS internal discharge'};

    colors = [ ...
        0.0000 0.4470 0.7410; ...
        0.3010 0.7450 0.9330; ...
        0.4660 0.6740 0.1880; ...
        0.2000 0.5000 0.1000; ...
        0.9290 0.6940 0.1250; ...
        0.8500 0.3250 0.0980; ...
        0.4940 0.1840 0.5560; ...
        0.6350 0.0780 0.1840];

    totalLoss_MWh = sum(Y_MWh, 2);
    Y_pct = zeros(size(Y_MWh));

    for i = 1:size(Y_MWh, 1)
        if totalLoss_MWh(i) > 1e-12
            Y_pct(i, :) = 100 * Y_MWh(i, :) ./ totalLoss_MWh(i);
        end
    end

    fig = figure('Name', 'AC/DC loss components comparison');

    ax1 = subplot(2, 1, 1);
    b1 = bar(ax1, x, Y_MWh, 'stacked');
    local_apply_bar_colors(b1, colors);

    grid(ax1, 'on');
    ylabel(ax1, 'Veszteseg [MWh]');
    title(ax1, 'AC/DC konkret vesztesegkomponensek abszolut ertekben');

    xticks(ax1, x);
    xticklabels(ax1, local_dc_ac_ticklabels(n));
    local_add_bess_group_labels(ax1, xDc, xAc, Tdc);

    legend(ax1, componentNames, ...
        'Location', 'eastoutside', ...
        'Interpreter', 'none');

    local_label_stacked_values(ax1, x, Y_MWh, '%.1f');

    ax2 = subplot(2, 1, 2);
    b2 = bar(ax2, x, Y_pct, 'stacked');
    local_apply_bar_colors(b2, colors);

    grid(ax2, 'on');
    ylabel(ax2, 'Reszarany [%]');
    title(ax2, 'Vesztesegkomponensek aranya a teljes vesztesegen belul');
    ylim(ax2, [0 100]);

    xticks(ax2, x);
    xticklabels(ax2, local_dc_ac_ticklabels(n));
    local_add_bess_group_labels(ax2, xDc, xAc, Tdc);

    legend(ax2, componentNames, ...
        'Location', 'eastoutside', ...
        'Interpreter', 'none');

    local_label_stacked_values(ax2, x, Y_pct, '%.0f%%');
end


function Y = local_loss_component_matrix(T)

    Y = [ ...
        local_required_col(T, 'centralInvDcToAcLoss_kWh'), ...
        local_required_col(T, 'centralInvAcToDcLoss_kWh'), ...
        local_required_col(T, 'dcdcChargeLoss_kWh'), ...
        local_required_col(T, 'dcdcDischargeLoss_kWh'), ...
        local_required_col(T, 'pcsbChargeLoss_kWh'), ...
        local_required_col(T, 'pcsbDischargeLoss_kWh'), ...
        local_required_col(T, 'bessInternalChargeLoss_kWh'), ...
        local_required_col(T, 'bessInternalDischargeLoss_kWh')];

    Y = max(Y, 0);
end


% =========================================================================
% 2) GRID -> BESS ES BESS -> LOAD HATASFOKOK
% =========================================================================
function fig = local_plot_grid_and_bess_path_efficiency(Tdc, Tac)

    n = height(Tdc);
    [x, xDc, xAc] = local_pair_positions(n);

    gridToBess_dc = local_required_col(Tdc, 'gridToBess_kWh') / 1000;
    gridToBess_ac = local_required_col(Tac, 'gridToBess_kWh') / 1000;

    gridStored_dc = local_required_col(Tdc, 'gridToBessStored_kWh') / 1000;
    gridStored_ac = local_required_col(Tac, 'gridToBessStored_kWh') / 1000;

    gridLoss_dc = max(gridToBess_dc - gridStored_dc, 0);
    gridLoss_ac = max(gridToBess_ac - gridStored_ac, 0);

    gridEff_dc = local_eff_percent(gridStored_dc, gridToBess_dc);
    gridEff_ac = local_eff_percent(gridStored_ac, gridToBess_ac);

    bessBefore_dc = local_required_col(Tdc, 'bessDischargeBeforeConversion_kWh') / 1000;
    bessBefore_ac = local_required_col(Tac, 'bessDischargeBeforeConversion_kWh') / 1000;

    bessToLoad_dc = local_required_col(Tdc, 'bessToLoad_kWh') / 1000;
    bessToLoad_ac = local_required_col(Tac, 'bessToLoad_kWh') / 1000;

    bessLoss_dc = max(bessBefore_dc - bessToLoad_dc, 0);
    bessLoss_ac = max(bessBefore_ac - bessToLoad_ac, 0);

    bessEff_dc = local_eff_percent(bessToLoad_dc, bessBefore_dc);
    bessEff_ac = local_eff_percent(bessToLoad_ac, bessBefore_ac);

    totalEff_dc = gridEff_dc .* bessEff_dc / 100;
    totalEff_ac = gridEff_ac .* bessEff_ac / 100;

    fig = figure('Name', 'AC/DC BESS energy path efficiency comparison');

    ax1 = subplot(3, 1, 1);

    Y1 = local_interleave_rows( ...
        [gridStored_dc, gridLoss_dc], ...
        [gridStored_ac, gridLoss_ac]);

    local_stacked_energy_bar_with_efficiency( ...
        ax1, ...
        x, ...
        Y1, ...
        gridEff_dc, ...
        gridEff_ac, ...
        'Grid -> BESS toltes: importalt energia, eltárolt energia es hatasfok', ...
        {'Tenylegesen eltárolt energia', 'Toltesi veszteseg'}, ...
        true);

    xticks(ax1, x);
    xticklabels(ax1, local_dc_ac_ticklabels(n));
    local_add_bess_group_labels(ax1, xDc, xAc, Tdc);

    ax2 = subplot(3, 1, 2);

    Y2 = local_interleave_rows( ...
        [bessToLoad_dc, bessLoss_dc], ...
        [bessToLoad_ac, bessLoss_ac]);

    local_stacked_energy_bar_with_efficiency( ...
        ax2, ...
        x, ...
        Y2, ...
        bessEff_dc, ...
        bessEff_ac, ...
        'BESS kisutes: konverzio elotti energia, fogyasztora juto energia es hatasfok', ...
        {'Fogyasztora juto BESS energia', 'Kisutesi ut veszteseg'}, ...
        true);

    xticks(ax2, x);
    xticklabels(ax2, local_dc_ac_ticklabels(n));
    local_add_bess_group_labels(ax2, xDc, xAc, Tdc);

    ax3 = subplot(3, 1, 3);

    totalEff = local_interleave_vectors(totalEff_dc, totalEff_ac);

    bar(ax3, x, totalEff, 0.65);
    grid(ax3, 'on');

    ylabel(ax3, 'Osszesitett hatasfok [%]');
    title(ax3, 'Osszesitett energiaut-hatasfok: toltesi hatasfok x kisutesi hatasfok');

    ylim(ax3, [80 100]);

    xticks(ax3, x);
    xticklabels(ax3, local_dc_ac_ticklabels(n));
    local_add_bess_group_labels(ax3, xDc, xAc, Tdc);

    local_label_simple_bars(ax3, x, totalEff, '%.1f%%');

    yline(ax3, 100, '--', '100 % referencia', ...
        'LabelHorizontalAlignment', 'left');
end


% =========================================================================
% 3) PV -> BESS HATASFOK ABRA
% =========================================================================
function fig = local_plot_pv_to_bess_efficiency(Tdc, Tac)

    n = height(Tdc);
    [x, xDc, xAc] = local_pair_positions(n);

    pvToBess_dc = local_required_col(Tdc, 'pvToBess_kWh') / 1000;
    pvToBess_ac = local_required_col(Tac, 'pvToBess_kWh') / 1000;

    pvStored_dc = local_required_col(Tdc, 'pvToBessStored_kWh') / 1000;
    pvStored_ac = local_required_col(Tac, 'pvToBessStored_kWh') / 1000;

    pvLoss_dc = max(pvToBess_dc - pvStored_dc, 0);
    pvLoss_ac = max(pvToBess_ac - pvStored_ac, 0);

    pvEff_dc = local_eff_percent(pvStored_dc, pvToBess_dc);
    pvEff_ac = local_eff_percent(pvStored_ac, pvToBess_ac);

    fig = figure('Name', 'AC/DC PV to BESS energy path efficiency comparison');

    ax = axes();

    Y = local_interleave_rows( ...
        [pvStored_dc, pvLoss_dc], ...
        [pvStored_ac, pvLoss_ac]);

    local_stacked_energy_bar_with_efficiency( ...
        ax, ...
        x, ...
        Y, ...
        pvEff_dc, ...
        pvEff_ac, ...
        'PV -> BESS: PV energia, tenylegesen eltárolt energia es hatasfok', ...
        {'Tenylegesen eltárolt PV energia', 'PV -> BESS veszteseg'}, ...
        true);

    xticks(ax, x);
    xticklabels(ax, local_dc_ac_ticklabels(n));
    local_add_bess_group_labels(ax, xDc, xAc, Tdc);
end


% =========================================================================
% 4) FINAL SOH ES KORRIGALT DEGRADACIOS KOLTSEG
% =========================================================================
function fig = local_plot_final_soh_and_degradation(Tdc, Tac, cfg)

    n = height(Tdc);
    [x, xDc, xAc] = local_pair_positions(n);

    finalSoH_dc = local_required_col(Tdc, 'finalSoH');
    finalSoH_ac = local_required_col(Tac, 'finalSoH');

    finalSoH_pct = 100 * local_interleave_vectors(finalSoH_dc, finalSoH_ac);

    capexDc_HUF = local_bess_capex_huf(Tdc, cfg);
    capexAc_HUF = local_bess_capex_huf(Tac, cfg);

    degCostDc_HUF = max(0, (1 - finalSoH_dc) ./ 0.2) .* capexDc_HUF;
    degCostAc_HUF = max(0, (1 - finalSoH_ac) ./ 0.2) .* capexAc_HUF;

    degCost_MHUF = local_interleave_vectors(degCostDc_HUF, degCostAc_HUF) / 1e6;

    fig = figure('Name', 'AC/DC final SoH and corrected degradation cost');

    ax1 = subplot(2, 1, 1);
    bar(ax1, x, finalSoH_pct, 0.65);
    grid(ax1, 'on');

    ylabel(ax1, 'Final SoH [%]');
    title(ax1, 'FinalSoH a teljes szimulalt idoszak vegen');

    yMin = max(80, floor(min(finalSoH_pct) - 1));
    ylim(ax1, [yMin 100]);

    xticks(ax1, x);
    xticklabels(ax1, local_dc_ac_ticklabels(n));
    local_add_bess_group_labels(ax1, xDc, xAc, Tdc);

    local_label_simple_bars(ax1, x, finalSoH_pct, '%.2f%%');

    ax2 = subplot(2, 1, 2);
    bar(ax2, x, degCost_MHUF, 0.65);
    grid(ax2, 'on');

    ylabel(ax2, 'Degradacios koltseg [M HUF]');
    title(ax2, 'Korrigalt BESS degradacios koltseg: (1 - finalSoH) / 0.2 * BESS CAPEX');

    xticks(ax2, x);
    xticklabels(ax2, local_dc_ac_ticklabels(n));
    local_add_bess_group_labels(ax2, xDc, xAc, Tdc);

    local_label_simple_bars(ax2, x, degCost_MHUF, '%.1f');
end


% =========================================================================
% STACKED ENERGY BAR + HATASFOKGORBE
% =========================================================================
function local_stacked_energy_bar_with_efficiency( ...
    ax, ...
    x, ...
    Y, ...
    effDc, ...
    effAc, ...
    plotTitle, ...
    legendText, ...
    showLabels)

    energyColors = [ ...
        0.0000 0.4470 0.7410; ...
        0.8500 0.1000 0.1000];

    yyaxis(ax, 'left');

    b = bar(ax, x, Y, 'stacked');
    local_apply_bar_colors(b, energyColors);

    ylabel(ax, 'Energia [MWh]');
    grid(ax, 'on');
    title(ax, plotTitle);

    if showLabels
        local_label_stacked_values(ax, x, Y, '%.1f');
    end

    yyaxis(ax, 'right');

    eff = local_interleave_vectors(effDc, effAc);

    hold(ax, 'on');
    p = plot(ax, x, eff, '-o', 'LineWidth', 1.2);
    hold(ax, 'off');

    ylabel(ax, 'Hatasfok [%]');
    ylim(ax, [80 100]);

    for i = 1:numel(x)
        if ~isnan(eff(i))
            text(ax, x(i), eff(i), sprintf('%.1f %%', eff(i)), ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'bottom', ...
                'FontSize', 8);
        end
    end

    legend(ax, [b(:); p], [legendText, {'Hatasfok'}], ...
        'Location', 'eastoutside', ...
        'Interpreter', 'none');

    yyaxis(ax, 'left');
end


% =========================================================================
% SEGEDFUGGVENYEK
% =========================================================================
function v = local_required_col(T, colName)

    if ~ismember(colName, T.Properties.VariableNames)
        error(['Missing candidateMetrics column: %s\n', ...
               'If this is a new loss-split metric, rerun the simulation after adding it to cfg.output.scalarMetrics.'], ...
               colName);
    end

    v = T.(colName);
    v = v(:);

    if ~isnumeric(v)
        error('Column %s must be numeric.', colName);
    end
end


function capex_HUF = local_bess_capex_huf(T, cfg)

    E_BESS_kWh = local_required_col(T, 'E_BESS_kWh');
    P_BESS_kW = local_required_col(T, 'P_BESS_kW');

    if ~isfield(cfg, 'cost') || ~isfield(cfg.cost, 'bess_huf_per_kWh')
        error('Missing cfg.cost.bess_huf_per_kWh.');
    end

    if isfield(cfg.cost, 'bess_power_huf_per_kW')
        bessPowerCost_HUF_per_kW = cfg.cost.bess_power_huf_per_kW;
    else
        bessPowerCost_HUF_per_kW = 0;
    end

    capex_HUF = ...
        E_BESS_kWh .* cfg.cost.bess_huf_per_kWh + ...
        P_BESS_kW .* bessPowerCost_HUF_per_kW;
end


function [x, xDc, xAc] = local_pair_positions(n)

    groupGap = 1.25;

    xDc = zeros(n, 1);
    xAc = zeros(n, 1);

    for i = 1:n
        base = (i - 1) * (2 + groupGap);
        xDc(i) = base + 1;
        xAc(i) = base + 2;
    end

    x = zeros(2 * n, 1);
    x(1:2:end) = xDc;
    x(2:2:end) = xAc;
end


function labels = local_dc_ac_ticklabels(n)

    labels = strings(2 * n, 1);

    for i = 1:n
        labels(2*i - 1) = "DC";
        labels(2*i) = "AC";
    end
end


function local_add_bess_group_labels(ax, xDc, xAc, T)

    yyaxis(ax, 'left');

    if ~ismember('E_BESS_kWh', T.Properties.VariableNames)
        return;
    end

    E = T.E_BESS_kWh(:);

    yl = ylim(ax);
    yText = yl(1) - 0.13 * (yl(2) - yl(1));

    for i = 1:numel(E)
        txt = sprintf('BESS %.0f kWh', E(i));

        text(ax, mean([xDc(i), xAc(i)]), yText, txt, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top', ...
            'Rotation', 0, ...
            'Clipping', 'off', ...
            'FontSize', 8);
    end
end


function local_apply_bar_colors(barHandles, colors)

    for k = 1:numel(barHandles)
        barHandles(k).FaceColor = colors(k, :);
    end
end


function local_label_stacked_values(ax, x, Y, fmt)

    yyaxis(ax, 'left');

    totals = sum(Y, 2);
    maxTotal = max(totals);

    if maxTotal <= 0
        return;
    end

    minVisible = 0.035 * maxTotal;

    for i = 1:size(Y, 1)

        yBase = 0;

        for j = 1:size(Y, 2)

            val = Y(i, j);

            if val > minVisible
                yMid = yBase + val / 2;

                text(ax, x(i), yMid, sprintf(fmt, val), ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', ...
                    'FontSize', 8);
            end

            yBase = yBase + val;
        end
    end
end


function local_label_simple_bars(ax, x, y, fmt)

    yl = ylim(ax);
    dy = 0.015 * (yl(2) - yl(1));

    for i = 1:numel(x)

        if isnan(y(i))
            continue;
        end

        text(ax, x(i), y(i) + dy, sprintf(fmt, y(i)), ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', ...
            'FontSize', 8);
    end
end


function Y = local_interleave_rows(Ydc, Yac)

    if size(Ydc, 1) ~= size(Yac, 1)
        error('DC and AC row count differs.');
    end

    n = size(Ydc, 1);
    m = size(Ydc, 2);

    Y = zeros(2 * n, m);

    Y(1:2:end, :) = Ydc;
    Y(2:2:end, :) = Yac;
end


function y = local_interleave_vectors(vdc, vac)

    if numel(vdc) ~= numel(vac)
        error('DC and AC vector length differs.');
    end

    n = numel(vdc);
    y = zeros(2 * n, 1);

    y(1:2:end) = vdc(:);
    y(2:2:end) = vac(:);
end


function eff = local_eff_percent(numerator, denominator)

    numerator = numerator(:);
    denominator = denominator(:);

    eff = NaN(size(numerator));

    valid = denominator > 1e-12;
    eff(valid) = 100 * numerator(valid) ./ denominator(valid);

    eff = min(max(eff, 0), 100);
end