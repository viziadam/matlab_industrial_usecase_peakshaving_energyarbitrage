function dayVectors = industrial_dayvectors_from_dispatch_result( ...
    dc, ...
    dayRes, ...
    plan_today, ...
    C_energy_step_HUF, ...
    C_energy_no_bess_step_HUF, ...
    C_degradation_step_HUF, ...
    C_overrun_step_HUF, ...
    C_contract_step_HUF, ...
    C_objective_step_HUF)
% INDUSTRIAL_DAYVECTORS_FROM_DISPATCH_RESULT
%
% A topology eredményéből egységes dayVectors struktúrát készít.
%
% Nincs fallback:
%   ha a szükséges mező hiányzik, a függvény hibát dob.

    requiredDcFields = { ...
        'P_load_actual', ...
        'P_pv_dc_actual', ...
        'P_grid_no_bess_day', ...
        'dt_h'};

    for i = 1:numel(requiredDcFields)
        if ~isfield(dc, requiredDcFields{i})
            error('Hiányzó dc mező: dc.%s', requiredDcFields{i});
        end
    end

    requiredDayResFields = { ...
        'E_grid_import', ...
        'E_stored', ...
        'E_discharged', ...
        'P_curtailment_kW', ...
        'SoC'};

    for i = 1:numel(requiredDayResFields)
        if ~isfield(dayRes, requiredDayResFields{i})
            error('Hiányzó dayRes mező: dayRes.%s', requiredDayResFields{i});
        end
    end

    requiredPlanFields = { ...
        'P_grid_plan', ...
        'P_ch_plan', ...
        'P_dis_plan', ...
        'P_curt_plan', ...
        'SoC_plan'};

    for i = 1:numel(requiredPlanFields)
        if ~isfield(plan_today, requiredPlanFields{i})
            error('Hiányzó plan_today mező: plan_today.%s', requiredPlanFields{i});
        end
    end

    P_load_kW = dc.P_load_actual(:);
    P_pv_available_kW = dc.P_pv_dc_actual(:);
    P_grid_import_no_bess_kW = dc.P_grid_no_bess_day(:);

    N = numel(P_load_kW);
    dt_h = dc.dt_h;

    P_grid_import_kW = dayRes.E_grid_import(:) / dt_h;
    P_bess_charge_kW = dayRes.E_stored(:) / dt_h;
    P_bess_discharge_kW = dayRes.E_discharged(:) / dt_h;
    P_bess_throughput_kW = P_bess_charge_kW + P_bess_discharge_kW;
    P_curtailment_kW = dayRes.P_curtailment_kW(:);
    SoC = dayRes.SoC(:);

    vectorsToCheck = { ...
        'P_pv_available_kW', P_pv_available_kW; ...
        'P_grid_import_no_bess_kW', P_grid_import_no_bess_kW; ...
        'P_grid_import_kW', P_grid_import_kW; ...
        'P_bess_charge_kW', P_bess_charge_kW; ...
        'P_bess_discharge_kW', P_bess_discharge_kW; ...
        'P_bess_throughput_kW', P_bess_throughput_kW; ...
        'P_curtailment_kW', P_curtailment_kW; ...
        'SoC', SoC; ...
        'C_energy_step_HUF', C_energy_step_HUF(:); ...
        'C_energy_no_bess_step_HUF', C_energy_no_bess_step_HUF(:); ...
        'C_degradation_step_HUF', C_degradation_step_HUF(:); ...
        'C_overrun_step_HUF', C_overrun_step_HUF(:); ...
        'C_contract_step_HUF', C_contract_step_HUF(:); ...
        'C_objective_step_HUF', C_objective_step_HUF(:)};

    for i = 1:size(vectorsToCheck, 1)

        name = vectorsToCheck{i, 1};
        vec = vectorsToCheck{i, 2};

        if numel(vec) ~= N
            error('A(z) %s vektor hossza hibás. Várt: %d, kapott: %d.', ...
                name, N, numel(vec));
        end
    end

    dayVectors = struct();

    % ---------------------------------------------------------------------
    % Alap teljesítményvektorok
    % ---------------------------------------------------------------------
    dayVectors.P_load_kW = P_load_kW;
    dayVectors.P_pv_available_kW = P_pv_available_kW;

    dayVectors.P_grid_import_kW = P_grid_import_kW;
    dayVectors.P_grid_import_no_bess_kW = P_grid_import_no_bess_kW;

    dayVectors.P_bess_charge_kW = P_bess_charge_kW;
    dayVectors.P_bess_discharge_kW = P_bess_discharge_kW;
    dayVectors.P_bess_throughput_kW = P_bess_throughput_kW;

    dayVectors.P_curtailment_kW = P_curtailment_kW;

    dayVectors.SoC = SoC;

    % ---------------------------------------------------------------------
    % Költségvektorok
    % Ezeknél a cfg.output.scalarMetrics-ben mode = "sum".
    % ---------------------------------------------------------------------
    dayVectors.C_energy_step_HUF = C_energy_step_HUF(:);
    dayVectors.C_energy_no_bess_step_HUF = C_energy_no_bess_step_HUF(:);
    dayVectors.C_degradation_step_HUF = C_degradation_step_HUF(:);
    dayVectors.C_overrun_step_HUF = C_overrun_step_HUF(:);
    dayVectors.C_contract_step_HUF = C_contract_step_HUF(:);
    dayVectors.C_objective_step_HUF = C_objective_step_HUF(:);

    % ---------------------------------------------------------------------
    % Terv szerinti debug/diagnosztikai vektorok
    % ---------------------------------------------------------------------
    dayVectors.P_grid_plan_kW = plan_today.P_grid_plan(:);
    dayVectors.P_bess_charge_plan_kW = plan_today.P_ch_plan(:);
    dayVectors.P_bess_discharge_plan_kW = plan_today.P_dis_plan(:);
    dayVectors.P_curtailment_plan_kW = plan_today.P_curt_plan(:);
    dayVectors.SoC_plan = plan_today.SoC_plan(:);
end