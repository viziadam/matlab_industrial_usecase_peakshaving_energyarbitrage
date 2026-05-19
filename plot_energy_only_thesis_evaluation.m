function figs = plot_energy_only_thesis_evaluation(T, cfg, outputFolder)
% PLOT_ENERGY_ONLY_THESIS_EVALUATION
%
% Energy-only mukodesi mod dolgozati kiertekelesi abraival foglalkozik.
% Nem valaszt legjobb jeloltet, hanem a teljes BESS/PV merethalot mutatja
% AC es DC csatolasra.
%
% Backward compatible mukodes:
%   - ha a regi results fajlokban meg nincsenek energiaaramlasi / veszteseg
%     oszlopok, akkor ezeket az abrakat kihagyja;
%   - a gazdasagi/NVP abra a regi eredmenyekbol is elkeszul, mert ehhez
%     elegendoek a korabban is mentett koltseg- es SoH-metrikak.
%
% Abrak:
%   1) Energiaaramlasok a teljes BESS/PV griden, ha vannak hozza oszlopok
%   2) Vesztesegkomponensek a teljes BESS/PV griden, ha vannak hozza oszlopok
%   3) Megtakaritas, BESS eves SoH CAPEX/OPEX es idoszaki NPV

    requiredEconomicColumns = { ...
        'coupling', ...
        'BESS_PV_ratio', ...
        'energySavingVsNoBess_HUF_per_year', ...
        'bessAnnualCapexOpex_HUF', ...
        'bessOpexAnnual_HUF'};

    local_require_columns(T, requiredEconomicColumns, true);

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

    hasFlowColumns = local_has_columns(T, flowColumns);
    hasLossColumns = local_has_columns(T, lossColumns);

    figs = struct();
    figs.energyFlows = [];
    figs.losses = [];
    figs.economics = [];

    if hasFlowColumns
        figs.energyFlows = local_plot_energy_flows(T, outputFolder);
    else
        local_print_skip_message('Energiaáramlási ábra', flowColumns);
    end

    if hasLossColumns
        figs.losses = local_plot_losses(T, outputFolder);
    else
        local_print_skip_message('Veszteségkomponens ábra', lossColumns);
    end

    figs.economics = local_plot_economics_and_npv(T, outputFolder);
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

    T.energyOnlyAnnualNetSaving_HUF = ...
        T.energySavingVsNoBess_HUF_per_year - ...
        T.bessAnnualCapexOpex_HUF;

    T.energyOnlyPeriodNPV_HUF = ...
        T.energyOnlyAnnualNetSaving_HUF .* annualDiscountFactor;
end


function fig = local_plot_energy_flows(T, outputFolder)

    fig = figure('Name', 'Energy-only energiaáramlások - teljes BESS/PV grid', ...
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

    local_save_figure(fig, outputFolder, 'thesis_energy_only_energy_flows_ac_dc');
end


function fig = local_plot_losses(T, outputFolder)

    fig = figure('Name', 'Energy-only veszteségkomponensek - teljes BESS/PV grid', ...
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

    local_save_figure(fig, outputFolder, 'thesis_energy_only_losses_ac_dc');
end


function fig = local_plot_economics_and_npv(T, outputFolder)

    fig = figure('Name', 'Energy-only gazdasági mérleg és nettó jelenérték', ...
        'Position', [160, 70, 1350, 950]);

    couplings = ["dc", "ac"];

    for i = 1:numel(couplings)

        c = couplings(i);
        sub = local_sorted_coupling_table(T, c);
        xLabels = string(sub.BESS_PV_ratio);

        Y = [ ...
            sub.energySavingVsNoBess_HUF_per_year, ...
           -sub.bessSohCapexAnnual_HUF, ...
           -sub.bessOpexAnnual_HUF] ./ 1e6;

        subplot(3, 1, i);
        bar(categorical(xLabels, xLabels, 'Ordinal', true), Y, 'grouped');
        yline(0, 'k-');
        grid on;
        ylabel('millió Ft/év');
        title(sprintf('Éves energia-megtakarítás és BESS költségek - %s csatolás', upper(c)));
        legend({ ...
            'Energia-megtakarítás', ...
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

        plot(sub.BESS_PV_ratio, sub.energyOnlyPeriodNPV_HUF ./ 1e6, '-o', ...
            'LineWidth', 1.5, ...
            'MarkerSize', 4, ...
            'DisplayName', upper(c));
    end

    yline(0, 'k-');
    xlabel('BESS/PV arány [-]');
    ylabel('millió Ft');
    title('Időszaki nettó jelenérték');
    legend('Location', 'best');

    local_save_figure(fig, outputFolder, 'thesis_energy_only_economics_npv_ac_dc');
end


function sub = local_sorted_coupling_table(T, coupling)

    sub = T(T.coupling == coupling, :);
    sub = sortrows(sub, 'BESS_PV_ratio');

    if isempty(sub) || height(sub) == 0
        error('Nincs érvényes %s csatolású candidate az energy-only kiértékeléshez.', coupling);
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

    fprintf(['A gazdasági/NVP ábra ettől még elkészül. ', ...
             'Az energiaáramlási és veszteségábrákhoz újra kell futtatni az energy_only szimulációt.\n']);
end


function local_save_figure(fig, outputFolder, fileName)

    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    savefig(fig, fullfile(outputFolder, [fileName, '.fig']));

    try
        exportgraphics(fig, fullfile(outputFolder, [fileName, '.png']), 'Resolution', 150);
    catch
        saveas(fig, fullfile(outputFolder, [fileName, '.png']);
    end
end
