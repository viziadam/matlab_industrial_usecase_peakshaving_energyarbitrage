function yearlyResult = evaluate_selected_candidate_yearly_budget( ...
    DB, cfg, evalCfg, selectedCandidateIndex)
% EVALUATE_SELECTED_CANDIDATE_YEARLY_BUDGET
%
% Egy kiválasztott candidate részletes éves költségvetése.
%
% A függvény a diagnosztikai mentésből dolgozik:
%   DB.diagnostics.candidate_<idx>.summary.full_result
%
% Kötelezően kell hozzá:
%   - baseline candidate: BESS_PV_ratio = 0
%   - selected candidate részletes simSummary/full_result
%
% Éves bontásban számolja:
%   - energia költség
%   - lekötött teljesítmény költség
%   - overrun költség
%   - degradációs költség
%   - évesített beruházási költség
%   - BESS OPEX
%   - contract saving
%   - energy saving
%   - overrun saving
%   - BESS added value

    if ~isfield(DB, 'candidateTable')
        error('DB.candidateTable hiányzik.');
    end

    if ~isfield(DB, 'diagnostics')
        error('DB.diagnostics hiányzik. Részletes éves budget csak diagnosztikai mentésből készíthető.');
    end

    T = DB.candidateTable;

    if selectedCandidateIndex < 1 || selectedCandidateIndex > height(T)
        error('Érvénytelen selectedCandidateIndex.');
    end

    baselineIdx = find(abs(T.BESS_PV_ratio) < 1e-12);

    if isempty(baselineIdx)
        error('Nincs baseline candidate: BESS_PV_ratio = 0.');
    end

    if numel(baselineIdx) > 1
        error('Több baseline candidate található.');
    end

    selectedField = sprintf('candidate_%d', selectedCandidateIndex);
    baselineField = sprintf('candidate_%d', baselineIdx);

    if ~isfield(DB.diagnostics, selectedField)
        error('A DB.diagnostics nem tartalmazza a kiválasztott candidate-et: %s', selectedField);
    end

    if ~isfield(DB.diagnostics, baselineField)
        error('A DB.diagnostics nem tartalmazza a baseline candidate-et: %s', baselineField);
    end

    selectedDiag = DB.diagnostics.(selectedField);
    baselineDiag = DB.diagnostics.(baselineField);

    if ~isfield(selectedDiag, 'summary') || ~isfield(selectedDiag.summary, 'full_result')
        error('A kiválasztott candidate diagnosztikája nem tartalmaz summary.full_result mezőt.');
    end

    if ~isfield(baselineDiag, 'summary') || ~isfield(baselineDiag.summary, 'full_result')
        error('A baseline candidate diagnosztikája nem tartalmaz summary.full_result mezőt.');
    end

    selectedFull = selectedDiag.summary.full_result;
    baselineFull = baselineDiag.summary.full_result;

    selectedRow = T(selectedCandidateIndex, :);
    baselineRow = T(baselineIdx, :);

    local_require_full_result_fields(selectedFull, 'selectedFull');
    local_require_full_result_fields(baselineFull, 'baselineFull');

    % =====================================================================
    % Évindex
    % =====================================================================
    nDays = numel(selectedFull.daily_energy_cost);

    if numel(baselineFull.daily_energy_cost) ~= nDays
        error('A selected és baseline full_result naphossza eltér.');
    end

    % Éves bontás a szimulációs napok alapján.
    % 365 napos évek szerint vágunk, az utolsó év lehet rövidebb.
    yearIndex = floor((0:nDays-1) / 365) + 1;
    nYears = max(yearIndex);

    Year = (1:nYears).';
    DaysInYear = accumarray(yearIndex(:), 1, [nYears, 1], @sum, 0);

    % =====================================================================
    % Candidate költségek éves bontásban
    % =====================================================================
    EnergyCost_HUF = accumarray(yearIndex(:), selectedFull.daily_energy_cost(:), [nYears, 1], @sum, 0);
    ContractCost_HUF = accumarray(yearIndex(:), selectedFull.daily_contract_cost(:), [nYears, 1], @sum, 0);
    OverrunCost_HUF = accumarray(yearIndex(:), selectedFull.daily_overrun_cost(:), [nYears, 1], @sum, 0);
    DegradationCost_HUF = accumarray(yearIndex(:), selectedFull.daily_deg_cost(:), [nYears, 1], @sum, 0);
    OperationalCost_HUF = EnergyCost_HUF + ContractCost_HUF + OverrunCost_HUF + DegradationCost_HUF;

    BaselineEnergyCost_HUF = accumarray(yearIndex(:), baselineFull.daily_energy_cost(:), [nYears, 1], @sum, 0);
    BaselineContractCost_HUF = accumarray(yearIndex(:), baselineFull.daily_contract_cost(:), [nYears, 1], @sum, 0);
    BaselineOverrunCost_HUF = accumarray(yearIndex(:), baselineFull.daily_overrun_cost(:), [nYears, 1], @sum, 0);

    % =====================================================================
    % Beruházás és OPEX évesített része
    % =====================================================================
    crf = local_capital_recovery_factor( ...
        evalCfg.economics.discountRate, ...
        evalCfg.economics.projectLifetime_years);

    capexPV_HUF = selectedRow.P_PV_kW * cfg.cost.pv_huf_per_kWp;

    capexBESS_HUF = ...
        selectedRow.E_BESS_kWh * cfg.cost.bess_huf_per_kWh + ...
        selectedRow.P_BESS_kW * cfg.cost.bess_power_huf_per_kW;

    capexInverter_HUF = selectedRow.P_inv_kW * cfg.cost.inverter_huf_per_kW;

    initialCapex_HUF = capexPV_HUF + capexBESS_HUF + capexInverter_HUF;

    AnnualizedInitialCapex_HUF = repmat(initialCapex_HUF * crf, nYears, 1);
    AnnualizedBessCapex_HUF = repmat(capexBESS_HUF * crf, nYears, 1);

    AnnualBessOPEX_HUF = repmat( ...
        capexBESS_HUF * cfg.cost.bess_opex_frac_per_year, ...
        nYears, ...
        1);

    AnnualPVOPEX_HUF = repmat( ...
        capexPV_HUF * cfg.cost.pv_opex_frac_per_year, ...
        nYears, ...
        1);

    AnnualInverterOPEX_HUF = repmat( ...
        capexInverter_HUF * cfg.cost.inverter_opex_frac_per_year, ...
        nYears, ...
        1);

    AnnualTotalOPEX_HUF = AnnualBessOPEX_HUF + AnnualPVOPEX_HUF + AnnualInverterOPEX_HUF;

    % =====================================================================
    % Megtakarítások / hozzáadott érték
    % =====================================================================
    ContractSaving_HUF = BaselineContractCost_HUF - ContractCost_HUF;
    EnergySaving_HUF = BaselineEnergyCost_HUF - EnergyCost_HUF;
    OverrunSaving_HUF = BaselineOverrunCost_HUF - OverrunCost_HUF;

    BessCost_HUF = ...
        AnnualizedBessCapex_HUF + ...
        AnnualBessOPEX_HUF + ...
        DegradationCost_HUF;

    BessAddedValue_HUF = ...
        ContractSaving_HUF + ...
        EnergySaving_HUF + ...
        OverrunSaving_HUF - ...
        BessCost_HUF;

    TotalAnnualCostWithCapex_HUF = ...
        OperationalCost_HUF + ...
        AnnualizedInitialCapex_HUF + ...
        AnnualTotalOPEX_HUF;

    BessThroughput_kWh = accumarray(yearIndex(:), selectedFull.daily_bess_throughput(:), [nYears, 1], @sum, 0);

    BessLCOE_HUF_per_kWh = NaN(nYears, 1);
    hasThroughput = BessThroughput_kWh > 0;

    BessLCOE_HUF_per_kWh(hasThroughput) = ...
        BessCost_HUF(hasThroughput) ./ BessThroughput_kWh(hasThroughput);

    % =====================================================================
    % Tábla
    % =====================================================================
    yearlyBudgetTable = table( ...
        Year, ...
        DaysInYear, ...
        EnergyCost_HUF, ...
        ContractCost_HUF, ...
        OverrunCost_HUF, ...
        DegradationCost_HUF, ...
        OperationalCost_HUF, ...
        AnnualizedInitialCapex_HUF, ...
        AnnualizedBessCapex_HUF, ...
        AnnualBessOPEX_HUF, ...
        AnnualTotalOPEX_HUF, ...
        TotalAnnualCostWithCapex_HUF, ...
        BaselineEnergyCost_HUF, ...
        BaselineContractCost_HUF, ...
        BaselineOverrunCost_HUF, ...
        EnergySaving_HUF, ...
        ContractSaving_HUF, ...
        OverrunSaving_HUF, ...
        BessCost_HUF, ...
        BessAddedValue_HUF, ...
        BessThroughput_kWh, ...
        BessLCOE_HUF_per_kWh);

    % =====================================================================
    % Ábrák
    % =====================================================================
    outputFolder = fullfile( ...
        cfg.diagnostics.outputFolder, ...
        sprintf('candidate_%06d', selectedCandidateIndex), ...
        'yearly_budget');

    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    fig1 = local_plot_yearly_cost_budget(yearlyBudgetTable, outputFolder);
    fig2 = local_plot_yearly_value_stack(yearlyBudgetTable, outputFolder);
    fig3 = local_plot_yearly_bess_indicators(yearlyBudgetTable, outputFolder);

    % =====================================================================
    % Output
    % =====================================================================
    yearlyResult = struct();

    yearlyResult.createdAt = datetime('now');
    yearlyResult.selectedCandidateIndex = selectedCandidateIndex;
    yearlyResult.baselineCandidateIndex = baselineIdx;

    yearlyResult.selectedCandidate = table2struct(selectedRow);
    yearlyResult.baselineCandidate = table2struct(baselineRow);

    yearlyResult.yearlyBudgetTable = yearlyBudgetTable;

    yearlyResult.figures = struct();
    yearlyResult.figures.costBudget = fig1;
    yearlyResult.figures.valueStack = fig2;
    yearlyResult.figures.bessIndicators = fig3;
end


function local_require_full_result_fields(fullResult, name)

    requiredFields = { ...
        'daily_energy_cost', ...
        'daily_contract_cost', ...
        'daily_overrun_cost', ...
        'daily_deg_cost', ...
        'daily_bess_throughput'};

    for i = 1:numel(requiredFields)

        f = requiredFields{i};

        if ~isfield(fullResult, f)
            error('%s nem tartalmazza a szükséges mezőt: %s', name, f);
        end
    end
end


function fig = local_plot_yearly_cost_budget(T, outputFolder)

    fig = figure('Name', 'Selected candidate yearly cost budget', ...
        'Position', [100, 80, 1350, 850]);

    tiledlayout(2, 1);

    nexttile;
    hold on;
    grid on;

    bar(T.Year, [ ...
        T.EnergyCost_HUF, ...
        T.ContractCost_HUF, ...
        T.OverrunCost_HUF, ...
        T.DegradationCost_HUF, ...
        T.AnnualizedInitialCapex_HUF, ...
        T.AnnualTotalOPEX_HUF] / 1e6, ...
        'stacked');

    xlabel('Szimulációs év');
    ylabel('Költség [millió HUF/év]');
    title('Kiválasztott candidate éves költségvetése');
    legend({ ...
        'Energia', ...
        'Lekötött teljesítmény', ...
        'Túllépés', ...
        'Degradáció', ...
        'Évesített beruházás', ...
        'OPEX'}, ...
        'Location', 'best');

    nexttile;
    hold on;
    grid on;

    plot(T.Year, T.TotalAnnualCostWithCapex_HUF / 1e6, '-o', ...
        'LineWidth', 1.8, ...
        'DisplayName', 'Teljes éves költség CAPEX résszel');

    plot(T.Year, T.OperationalCost_HUF / 1e6, '-s', ...
        'LineWidth', 1.5, ...
        'DisplayName', 'Operatív költség');

    xlabel('Szimulációs év');
    ylabel('Költség [millió HUF/év]');
    title('Éves teljes költség és operatív költség');
    legend('Location', 'best');

    local_save_figure(fig, outputFolder, 'yearly_cost_budget');
end


function fig = local_plot_yearly_value_stack(T, outputFolder)

    fig = figure('Name', 'Selected candidate yearly value stack', ...
        'Position', [120, 80, 1350, 850]);

    tiledlayout(2, 1);

    nexttile;
    hold on;
    grid on;

    bar(T.Year, [ ...
        T.ContractSaving_HUF, ...
        T.EnergySaving_HUF, ...
        T.OverrunSaving_HUF, ...
        -T.BessCost_HUF] / 1e6, ...
        'stacked');

    xlabel('Szimulációs év');
    ylabel('Érték [millió HUF/év]');
    title('Éves value stack: peak shaving + energiaoldali nyereség - BESS költség');
    legend({ ...
        'Lekötött teljesítmény csökkenéséből adódó nyereség', ...
        'Energia arbitrázs + önköltség csökkentés', ...
        'Túllépési költség csökkenése', ...
        'BESS éves költsége'}, ...
        'Location', 'best');

    nexttile;
    hold on;
    grid on;

    plot(T.Year, T.BessAddedValue_HUF / 1e6, '-o', ...
        'LineWidth', 1.8, ...
        'DisplayName', 'Nettó BESS hozzáadott érték');

    yline(0, 'k--', 'LineWidth', 1.0);

    xlabel('Szimulációs év');
    ylabel('Érték [millió HUF/év]');
    title('BESS nettó hozzáadott értéke évente');
    legend('Location', 'best');

    local_save_figure(fig, outputFolder, 'yearly_value_stack');
end


function fig = local_plot_yearly_bess_indicators(T, outputFolder)

    fig = figure('Name', 'Selected candidate yearly BESS indicators', ...
        'Position', [140, 80, 1250, 750]);

    tiledlayout(2, 1);

    nexttile;
    hold on;
    grid on;

    bar(T.Year, T.BessThroughput_kWh / 1e3);

    xlabel('Szimulációs év');
    ylabel('MWh/év');
    title('Éves BESS throughput');

    nexttile;
    hold on;
    grid on;

    plot(T.Year, T.BessLCOE_HUF_per_kWh, '-o', ...
        'LineWidth', 1.8, ...
        'DisplayName', 'BESS LCOE/LCOS');

    xlabel('Szimulációs év');
    ylabel('HUF/kWh');
    title('BESS fajlagos tárolási költség éves bontásban');
    legend('Location', 'best');

    local_save_figure(fig, outputFolder, 'yearly_bess_indicators');
end


function crf = local_capital_recovery_factor(r, n)

    if n <= 0
        error('A CRF evek szama legyen pozitiv.');
    end

    if r < 0
        error('A diszkontrata nem lehet negativ.');
    end

    if r == 0
        crf = 1 / n;
    else
        crf = r * (1 + r)^n / ((1 + r)^n - 1);
    end
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