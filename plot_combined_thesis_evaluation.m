function figs = plot_combined_thesis_evaluation(T, cfg, outputFolder)
% PLOT_COMBINED_THESIS_EVALUATION
%
% Combined mukodesi mod dolgozati kiertekelesi abraival foglalkozik.
% Nem valaszt legjobb jeloltet, hanem a teljes BESS/PV merethalot mutatja
% AC es DC csatolasra.
%
% Backward compatible mukodes:
%   - a fo teljesitmeny- es gazdasagi abrak regi results fajlokbol is
%     elkeszulnek;
%   - az energiaaramlasi / veszteseg abrak csak akkor keszulnek el, ha az
%     uj metrikamentes utan mar szerepelnek az ehhez szukseges oszlopok.
%
% Abrak:
%   1) Combined fo mutatok a teljes BESS/PV griden
%   2) Energiaaramlasok a teljes BESS/PV griden, ha vannak hozza oszlopok
%   3) Vesztesegkomponensek a teljes BESS/PV griden, ha vannak hozza oszlopok
%   4) Megtakaritas, BESS eves SoH CAPEX/OPEX es idoszaki NPV
%   5) AC/DC topologiai kulonbsegek a teljes BESS/PV griden

    requiredMainColumns = { ...
        'coupling', ...
        'BESS_PV_ratio', ...
        'bestContract_kW', ...
        'contractReductionVsNoBess_pct', ...
        'energySavingVsNoBess_HUF_per_year', ...
        'performanceSavingVsNoBess_HUF_per_year', ...
        'netAnnualSavingVsNoBess_HUF_per_year', ...
        'bessAnnualCapexOpex_HUF', ...
        'bessOpexAnnual_HUF'};

    local_require_columns(T, requiredMainColumns, true);

    T = T(logical(T.wasSimulated) & ~logical(T.hasError), :);
    T = T(isfinite(T.BESS_PV_ratio), :);
    T = local_add_present_value_columns(T, cfg);

    flowColumns = { ...
        'pvToLoad_kWh', ...
        'gridToLoad_kWh', ...
        'bessToLoad_kWh', ...
        'pvToBess_kWh'};

    lossColumns = { ...
        'inverterLoss_kWh', ...
        'dcdcLoss_kWh', ...
        'bessInternalLoss_kWh', ...
        'clippedEnergy_kWh'};

    topologyColumns = { ...
        'pvToBess_kWh', ...
        'gridToBess_kWh', ...
        'bessToLoad_kWh', ...
        'inverterLoss_kWh', ...
        'dcdcLoss_kWh', ...
        'bessInternalLoss_kWh', ...
        'combinedPeriodNPV_HUF'};

    figs = struct();
    figs.keyMetrics = local_plot_key_metrics(T, outputFolder);
    figs.energyFlows = [];
    figs.losses = [];
    figs.economics = local_plot_economics_and_npv(T, outputFolder);
    figs.topologyComparison = [];

    if local_has_columns(T, flowColumns)
        figs.energyFlows = local_plot_energy_flows(T, outputFolder);
    else
        local_print_skip_message('Energiaáramlási ábra', flowColumns);
    end

    if local_has_columns(T, lossColumns)
        figs.losses = local_plot_losses(T, outputFolder);
    else
        local_print_skip_message('Veszteségkomponens ábra', lossColumns);
    end

    if local_has_columns(T, topologyColumns)
        figs.topologyComparison = local_plot_topology_comparison(T, outputFolder);
    else
        local_print_skip_message('AC/DC topológiai összehasonlító ábra', topologyColumns);
    end
end


function T = local_add_present_value_columns(T, cfg)

    simYears = cfg.analysis.simYears;
    discountRate = cfg.cost.discount_rate;

    annualDiscountFactor = 0;

    for y = 1:simYears
        annualDiscountFactor = annualDiscountFactor + 1 / (1 + discountRate)^y;
    end

    T.bessSohCapexAnnual_HUF = ...
        T.bessAnnualCapexOpex_HUF - T.bessOpexAnnual_HUF;

    T.combinedAnnualNetSaving_HUF = ...
        T.energySavingVsNoBess_HUF_per_year + ...
        T.performanceSavingVsNoBess_HUF_per_year - ...
        T.bessAnnualCapexOpex_HUF;

    T.combinedPeriodNPV_HUF = ...
        T.combinedAnnualNetSaving_HUF .* annualDiscountFactor;
end


function fig = local_plot_key_metrics(T, outputFolder)

    fig = figure('Name', 'Combined fő mutatók - teljes BESS/PV grid', ...
        'Position', [100, 60, 1350, 950]);

    metrics = { ...
        'bestContract_kW', 'Optimális lekötött teljesítmény [kW]'; ...
        'contractReductionVsNoBess_pct', 'Lekötött teljesítmény csökkenése [%]'; ...
        'energySavingVsNoBess_HUF_per_year', 'Energiaköltség megtakarítás [Ft/év]'; ...
        'netAnnualSavingVsNoBess_HUF_per_year', 'Nettó éves eredmény [Ft/év]'};

    for k = 1:size(metrics, 1)

        subplot(size(metrics, 1), 1, k);
        hold on;
        grid on;

        local_plot_metric_by_coupling(T, metrics{k, 1});
        ylabel(metrics{k, 2});

        if k == 1
            title('Kombinált üzem fő mutatói');
        end

        if k == size(metrics, 1)
            xlabel('BESS/PV arány [-]');
        end

        legend('Location', 'best');
    end

    local_save_figure(fig, outputFolder, 'thesis_combined_key_metrics_ac_dc');
end


function local_plot_metric_by_coupling(T, metricName)

    couplings = ["dc", "ac"];

    for i = 1:numel(couplings)

        c = couplings(i);
        sub = local_sorted_coupling_table(T, c);

        plot(sub.BESS_PV_ratio, sub.(metricName), '-o', ...
            'LineWidth', 1.5, ...
            'MarkerSize', 4, ...
            'DisplayName', upper(c));
    end
end


function fig = local_plot_energy_flows(T, outputFolder)

    fig = figure('Name', 'Combined energiaáramlások - teljes BESS/PV grid', ...
        'Position', [120, 80, 1350, 850]);

    couplings = ["dc", "ac"];

    for i = 1:numel(couplings)

        c = couplings(i);
        sub = local_sorted_coupling_table(T, c);
        xLabels = string(sub.BESS_PV_ratio);

        Y = [ ...
            sub.pvToLoad_kWh, ...
            sub.gridToLoad_kWh, ...
            sub.bessToLoad_kWh, ...
            sub.pvToBess_kWh] ./ 1000;

        subplot(2, 1, i);
        bar(categorical(xLabels, xLabels, 'Ordinal', true), Y, 'stacked');
        grid on;
        ylabel('Energia [MWh]');
        title(sprintf('Energiaáramlások - %s csatolás', upper(c)));
        legend({ ...
            'PV -> fogyasztás', ...
            'Hálózat -> fogyasztás', ...
            'BESS -> fogyasztás', ...
            'PV -> BESS'}, ...
            'Location', 'bestoutside');

        if i == numel(couplings)
            xlabel('BESS/PV arány [-]');
        end
    end

    local_save_figure(fig, outputFolder, 'thesis_combined_energy_flows_ac_dc');
end


function fig = local_plot_losses(T, outputFolder)

    fig = figure('Name', 'Combined veszteségkomponensek - teljes BESS/PV grid', ...
        'Position', [140, 90, 1350, 850]);

    couplings = ["dc", "ac"];

    for i = 1:numel(couplings)

        c = couplings(i);
        sub = local_sorted_coupling_table(T, c);
        xLabels = string(sub.BESS_PV_ratio);

        Y = [ ...
            sub.inverterLoss_kWh, ...
            sub.dcdcLoss_kWh, ...
            sub.bessInternalLoss_kWh, ...
            sub.clippedEnergy_kWh] ./ 1000;

        subplot(2, 1, i);
        bar(categorical(xLabels, xLabels, 'Ordinal', true), Y, 'stacked');
        grid on;
        ylabel('Energia [MWh]');
        title(sprintf('Veszteségkomponensek - %s csatolás', upper(c)));
        legend({ ...
            'Inverter / PCS veszteség', ...
            'DC/DC veszteség', ...
            'BESS belső veszteség', ...
            'Leszabályozott energia'}, ...
            'Location', 'bestoutside');

        if i == numel(couplings)
            xlabel('BESS/PV arány [-]');
        end
    end

    local_save_figure(fig, outputFolder, 'thesis_combined_losses_ac_dc');
end


function fig = local_plot_economics_and_npv(T, outputFolder)

    fig = figure('Name', 'Combined gazdasági mérleg és nettó jelenérték', ...
        'Position', [160, 70, 1350, 950]);

    couplings = ["dc", "ac"];

    for i = 1:numel(couplings)

        c = couplings(i);
        sub = local_sorted_coupling_table(T, c);
        xLabels = string(sub.BESS_PV_ratio);

        Y = [ ...
            sub.energySavingVsNoBess_HUF_per_year, ...
            sub.performanceSavingVsNoBess_HUF_per_year, ...
           -sub.bessSohCapexAnnual_HUF, ...
           -sub.bessOpexAnnual_HUF] ./ 1e6;

        subplot(3, 1, i);
        bar(categorical(xLabels, xLabels, 'Ordinal', true), Y, 'grouped');
        yline(0, 'k-');
        grid on;
        ylabel('millió Ft/év');
        title(sprintf('Éves megtakarítások és BESS költségek - %s csatolás', upper(c)));
        legend({ ...
            'Energiaköltség megtakarítás', ...
            'Teljesítménydíj megtakarítás', ...
            'BESS SoH CAPEX', ...
            'BESS OPEX'}, ...
            'Location', 'bestoutside');

        if i == numel(couplings)
            xlabel('BESS/PV arány [-]');
        end
    end

    subplot(3, 1, 3); hold on; grid on;

    for i = 1:numel(couplings)
        c = couplings(i);
        sub = local_sorted_coupling_table(T, c);

        plot(sub.BESS_PV_ratio, sub.combinedPeriodNPV_HUF ./ 1e6, '-o', ...
            'LineWidth', 1.5, ...
            'MarkerSize', 4, ...
            'DisplayName', upper(c));
    end

    yline(0, 'k-');
    xlabel('BESS/PV arány [-]');
    ylabel('millió Ft');
    title('Időszaki nettó jelenérték');
    legend('Location', 'best');

    local_save_figure(fig, outputFolder, 'thesis_combined_economics_npv_ac_dc');
end


function fig = local_plot_topology_comparison(T, outputFolder)
% LOCAL_PLOT_TOPOLOGY_COMPARISON
%
% Kifejezetten az AC es DC csatolas kozul adodo muszaki-gazdasagi
% kulonbsegeket mutatja. A mutatok parositott BESS/PV aranyok menten
% hasonlitjak ossze a ket topologiat.

    dc = local_sorted_coupling_table(T, "dc");
    ac = local_sorted_coupling_table(T, "ac");

    [ratios, iDc, iAc] = intersect(dc.BESS_PV_ratio, ac.BESS_PV_ratio, 'stable');

    if isempty(ratios)
        error('Nincs közös BESS/PV arány az AC/DC topológiai összehasonlításhoz.');
    end

    dc = dc(iDc, :);
    ac = ac(iAc, :);

    dcStorageInput = dc.pvToBess_kWh + dc.gridToBess_kWh;
    acStorageInput = ac.pvToBess_kWh + ac.gridToBess_kWh;

    dcTotalLoss = dc.inverterLoss_kWh + dc.dcdcLoss_kWh + dc.bessInternalLoss_kWh;
    acTotalLoss = ac.inverterLoss_kWh + ac.dcdcLoss_kWh + ac.bessInternalLoss_kWh;

    dcStorageEff = 100 .* local_safe_divide_vec(dc.bessToLoad_kWh, dcStorageInput);
    acStorageEff = 100 .* local_safe_divide_vec(ac.bessToLoad_kWh, acStorageInput);

    dcPvStorageShare = 100 .* local_safe_divide_vec(dc.pvToBess_kWh, dcStorageInput);
    acPvStorageShare = 100 .* local_safe_divide_vec(ac.pvToBess_kWh, acStorageInput);

    dcLossPerBessOut = local_safe_divide_vec(dcTotalLoss, dc.bessToLoad_kWh);
    acLossPerBessOut = local_safe_divide_vec(acTotalLoss, ac.bessToLoad_kWh);

    npvDiff = dc.combinedPeriodNPV_HUF - ac.combinedPeriodNPV_HUF;
    energySavingDiff = dc.energySavingVsNoBess_HUF_per_year - ac.energySavingVsNoBess_HUF_per_year;
    contractDiff = dc.bestContract_kW - ac.bestContract_kW;

    fig = figure('Name', 'AC/DC topológiai különbségek - combined', ...
        'Position', [100, 50, 1400, 1050]);

    subplot(4, 1, 1); hold on; grid on;
    plot(ratios, dcStorageEff, '-o', 'LineWidth', 1.5, 'DisplayName', 'DC');
    plot(ratios, acStorageEff, '-o', 'LineWidth', 1.5, 'DisplayName', 'AC');
    ylabel('Hasznosítás [%]');
    title('Tárolási út hatásfoka: BESS -> fogyasztás / BESS töltés');
    legend('Location', 'best');

    subplot(4, 1, 2); hold on; grid on;
    plot(ratios, dcLossPerBessOut, '-o', 'LineWidth', 1.5, 'DisplayName', 'DC');
    plot(ratios, acLossPerBessOut, '-o', 'LineWidth', 1.5, 'DisplayName', 'AC');
    ylabel('kWh/kWh');
    title('Veszteségigény hasznos BESS-kisütésre vetítve');
    legend('Location', 'best');

    subplot(4, 1, 3); hold on; grid on;
    plot(ratios, dcPvStorageShare, '-o', 'LineWidth', 1.5, 'DisplayName', 'DC');
    plot(ratios, acPvStorageShare, '-o', 'LineWidth', 1.5, 'DisplayName', 'AC');
    ylabel('PV részarány [%]');
    title('PV eredetű BESS töltés részaránya');
    legend('Location', 'best');

    subplot(4, 1, 4); hold on; grid on;
    plot(ratios, npvDiff ./ 1e6, '-o', 'LineWidth', 1.5, 'DisplayName', 'NPV különbség: DC - AC');
    plot(ratios, energySavingDiff ./ 1e6, '-o', 'LineWidth', 1.5, 'DisplayName', 'Energiamegtakarítás különbség: DC - AC');
    yyaxis right;
    plot(ratios, contractDiff, '--o', 'LineWidth', 1.2, 'DisplayName', 'Contract különbség: DC - AC');
    ylabel('Contract különbség [kW]');
    yyaxis left;
    yline(0, 'k-');
    ylabel('millió Ft');
    xlabel('BESS/PV arány [-]');
    title('Gazdasági és contract különbségek');
    legend('Location', 'best');

    local_save_figure(fig, outputFolder, 'thesis_combined_topology_difference_ac_dc');
end


function sub = local_sorted_coupling_table(T, coupling)

    sub = T(T.coupling == coupling, :);
    sub = sortrows(sub, 'BESS_PV_ratio');

    if isempty(sub) || height(sub) == 0
        error('Nincs érvényes %s csatolású candidate a combined kiértékeléshez.', coupling);
    end
end


function tf = local_has_columns(T, colNames)

    tf = all(ismember(colNames, T.Properties.VariableNames));
end


function local_require_columns(T, colNames, hardError)

    if nargin < 3
        hardError = true;
    end

    missing = colNames(~ismember(colNames, T.Properties.VariableNames));

    if isempty(missing)
        return;
    end

    msg = sprintf('Hiányzó candidateTable oszlop(ok): %s', strjoin(string(missing), ', '));

    if hardError
        error('%s', msg);
    else
        warning('%s', msg);
    end
end


function local_print_skip_message(plotName, missingColumns)

    fprintf('\n%s kihagyva.\n', plotName);
    fprintf('A mentett eredményfájlok nem tartalmazzák az ehhez szükséges új oszlopokat:\n');

    for i = 1:numel(missingColumns)
        fprintf('  - %s\n', missingColumns{i});
    end

    fprintf(['A fő mutató- és gazdasági/NPV ábra ettől még elkészül. ', ...
             'Az energiaáramlási, veszteség- és topológiai különbségábrákhoz ', ...
             'újra kell futtatni a combined szimulációt.\n']);
end


function y = local_safe_divide_vec(a, b)

    y = NaN(size(a));
    mask = isfinite(a) & isfinite(b) & abs(b) > 1e-12;
    y(mask) = a(mask) ./ b(mask);
end


function local_save_figure(fig, outputFolder, fileName)

    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    savefig(fig, fullfile(outputFolder, [fileName, '.fig']));

    try
        exportgraphics(fig, fullfile(outputFolder, [fileName, '.png']), 'Resolution', 150);
    catch
        saveas(fig, fullfile(outputFolder, [fileName, '.png']));
    end
end
