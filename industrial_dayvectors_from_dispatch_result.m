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
% A topology eredmenyebol egyseges dayVectors strukturat keszit.
%
% A dolgozati kiertekeleshez kulon mentjuk:
%   - PV -> fogyasztas
%   - halozat -> fogyasztas
%   - BESS -> fogyasztas
%   - PV -> BESS toltes
%   - halozat -> BESS toltes
%   - inverter / DC-DC / BESS belso veszteseg
%   - leszabalyozott energia

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
    P_pv_dc_kW = dc.P_pv_dc_actual(:);
    P_grid_import_no_bess_kW = dc.P_grid_no_bess_day(:);

    N = numel(P_load_kW);
    dt_h = dc.dt_h;

    P_grid_import_kW = dayRes.E_grid_import(:) / dt_h;
    P_bess_charge_kW = dayRes.E_stored(:) / dt_h;
    P_bess_discharge_kW = dayRes.E_discharged(:) / dt_h;
    P_bess_throughput_kW = P_bess_charge_kW + P_bess_discharge_kW;
    P_curtailment_kW = dayRes.P_curtailment_kW(:);
    SoC = dayRes.SoC(:);

    P_pv_available_kW = local_get_pv_available_ac(dayRes, P_pv_dc_kW, N);

    % ---------------------------------------------------------------------
    % Actual energiaaramlasi felbontas
    % ---------------------------------------------------------------------
    % A BESS kisutest kulon kezeljuk, hogy DC csatolasnal a kozos inverter
    % kimenete ne rajzolodjon tevesen PV -> fogyasztas komponenskent.
    P_bess_to_load_kW = min(P_bess_discharge_kW, P_load_kW);

    remainingLoad_kW = max(P_load_kW - P_bess_to_load_kW, 0);
    P_pv_to_load_kW = min(P_pv_available_kW, remainingLoad_kW);

    remainingLoad_kW = max(remainingLoad_kW - P_pv_to_load_kW, 0);
    P_grid_to_load_kW = min(P_grid_import_kW, remainingLoad_kW);

    remainingLoad_kW = max(remainingLoad_kW - P_grid_to_load_kW, 0);
    P_grid_to_load_kW = P_grid_to_load_kW + remainingLoad_kW;

    P_pv_to_bess_kW = min(max(P_pv_available_kW - P_pv_to_load_kW, 0), P_bess_charge_kW);
    P_grid_to_bess_kW = max(P_bess_charge_kW - P_pv_to_bess_kW, 0);

    P_loss_inv_kW = local_get_energy_or_power_as_power(dayRes, 'P_loss_inv_kW', 'E_loss_inv', N, dt_h);
    P_loss_dcdc_kW = local_get_energy_or_power_as_power(dayRes, 'P_loss_dcdc_kW', 'E_loss_dcdc', N, dt_h);
    P_loss_bess_internal_kW = local_get_energy_or_power_as_power(dayRes, 'P_loss_bess_internal_kW', 'E_loss_joule', N, dt_h);

    vectorsToCheck = { ...
        'P_pv_available_kW', P_pv_available_kW; ...
        'P_grid_import_no_bess_kW', P_grid_import_no_bess_kW; ...
        'P_grid_import_kW', P_grid_import_kW; ...
        'P_bess_charge_kW', P_bess_charge_kW; ...
        'P_bess_discharge_kW', P_bess_discharge_kW; ...
        'P_bess_throughput_kW', P_bess_throughput_kW; ...
        'P_curtailment_kW', P_curtailment_kW; ...
        'P_pv_to_load_kW', P_pv_to_load_kW; ...
        'P_grid_to_load_kW', P_grid_to_load_kW; ...
        'P_bess_to_load_kW', P_bess_to_load_kW; ...
        'P_pv_to_bess_kW', P_pv_to_bess_kW; ...
        'P_grid_to_bess_kW', P_grid_to_bess_kW; ...
        'P_loss_inv_kW', P_loss_inv_kW; ...
        'P_loss_dcdc_kW', P_loss_dcdc_kW; ...
        'P_loss_bess_internal_kW', P_loss_bess_internal_kW; ...
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

    dayVectors.P_load_kW = P_load_kW;
    dayVectors.P_pv_available_kW = P_pv_available_kW;

    dayVectors.P_grid_import_kW = P_grid_import_kW;
    dayVectors.P_grid_import_no_bess_kW = P_grid_import_no_bess_kW;

    dayVectors.P_bess_charge_kW = P_bess_charge_kW;
    dayVectors.P_bess_discharge_kW = P_bess_discharge_kW;
    dayVectors.P_bess_throughput_kW = P_bess_throughput_kW;

    dayVectors.P_curtailment_kW = P_curtailment_kW;

    dayVectors.P_pv_to_load_kW = P_pv_to_load_kW;
    dayVectors.P_grid_to_load_kW = P_grid_to_load_kW;
    dayVectors.P_bess_to_load_kW = P_bess_to_load_kW;
    dayVectors.P_pv_to_bess_kW = P_pv_to_bess_kW;
    dayVectors.P_grid_to_bess_kW = P_grid_to_bess_kW;

    dayVectors.P_loss_inv_kW = P_loss_inv_kW;
    dayVectors.P_loss_dcdc_kW = P_loss_dcdc_kW;
    dayVectors.P_loss_bess_internal_kW = P_loss_bess_internal_kW;

    dayVectors.SoC = SoC;

    dayVectors.C_energy_step_HUF = C_energy_step_HUF(:);
    dayVectors.C_energy_no_bess_step_HUF = C_energy_no_bess_step_HUF(:);
    dayVectors.C_degradation_step_HUF = C_degradation_step_HUF(:);
    dayVectors.C_overrun_step_HUF = C_overrun_step_HUF(:);
    dayVectors.C_contract_step_HUF = C_contract_step_HUF(:);
    dayVectors.C_objective_step_HUF = C_objective_step_HUF(:);

    dayVectors.P_grid_plan_kW = plan_today.P_grid_plan(:);
    dayVectors.P_bess_charge_plan_kW = plan_today.P_ch_plan(:);
    dayVectors.P_bess_discharge_plan_kW = plan_today.P_dis_plan(:);
    dayVectors.P_curtailment_plan_kW = plan_today.P_curt_plan(:);
    dayVectors.SoC_plan = plan_today.SoC_plan(:);
end


function PpvAvailable = local_get_pv_available_ac(dayRes, P_pv_dc_kW, N)

    if isfield(dayRes, 'P_pv_ac_base_kW')
        PpvAvailable = dayRes.P_pv_ac_base_kW(:);
    elseif isfield(dayRes, 'P_pv_ac_kW') && ~isfield(dayRes, 'P_inv_ac_kW')
        PpvAvailable = dayRes.P_pv_ac_kW(:);
    elseif isfield(dayRes, 'P_pv_ac_kW') && isfield(dayRes, 'P_bess_dc_actual_kW')
        error(['DC topology esetén a dayRes.P_pv_ac_kW közös inverter kimenet is lehet. ', ...
               'Hiányzik dayRes.P_pv_ac_base_kW.']);
    elseif isfield(dayRes, 'P_pv_ac_kW')
        PpvAvailable = dayRes.P_pv_ac_kW(:);
    else
        error('Hiányzó dayRes mező: P_pv_ac_kW vagy P_pv_ac_base_kW.');
    end

    PpvAvailable = local_vec(PpvAvailable, N);
end


function P = local_get_energy_or_power_as_power(dayRes, powerField, energyField, N, dt_h)

    if isfield(dayRes, powerField)
        P = dayRes.(powerField)(:);
    elseif isfield(dayRes, energyField)
        P = dayRes.(energyField)(:) ./ dt_h;
    else
        error('Hiányzó dayRes veszteségmező: %s vagy %s.', powerField, energyField);
    end

    P = local_vec(P, N);
end


function v = local_vec(x, N)

    v = x(:);

    if numel(v) ~= N
        error('Vektorhossz eltérés. Várt: %d, kapott: %d.', N, numel(v));
    end
end
