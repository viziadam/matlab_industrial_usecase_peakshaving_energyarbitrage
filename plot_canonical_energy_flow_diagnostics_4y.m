function fig = plot_canonical_energy_flow_diagnostics_4y(full_result)
% PLOT_CANONICAL_ENERGY_FLOW_DIAGNOSTICS_4Y
%
% Diagnosztikai abra a topologiak altal explicit visszaadott kanonikus
% energiaaramlasi mezokbol.
%
% A fuggveny nem szarmaztat uj, alternativ energiaaramlasi logikat:
% csak a topology_* fuggvenyekben eloallitott mezoket olvassa ki.
%
% Hasznalt mezok, ha elerhetok:
%   P_pv_to_bess_kW
%   P_grid_to_bess_kW
%   P_pv_to_bess_loss_kW
%   P_grid_to_bess_loss_kW
%   P_pv_to_bess_stored_kW
%   P_grid_to_bess_stored_kW
%   P_bess_discharge_before_conversion_kW
%   P_bess_to_load_kW
%   P_bess_to_load_conversion_loss_kW
%   P_grid_import_kW
%   P_grid_to_load_kW
%   E_grid_import_base
%   C_grid_to_bess_import_HUF
%   C_grid_to_bess_stored_import_equiv_HUF
%   C_bess_discharge_before_conversion_import_equiv_HUF
%   C_bess_to_load_import_equiv_HUF

    if ~isfield(full_result, 'final_day') || isempty(full_result.final_day)
        fig = [];
        return;
    end

    if ~isfield(full_result.final_day, 'res') || isempty(full_result.final_day.res)
        fig = [];
        return;
    end

    res = full_result.final_day.res;

    if isfield(full_result.final_day, 'load')
        n = numel(full_result.final_day.load(:));
    elseif isfield(res, 'P_grid_import_kW')
        n = numel(res.P_grid_import_kW(:));
    else
        fig = [];
        return;
    end

    dt_h = 24 / n;
    t = (0:n-1).' * dt_h;

    P_pv_to_bess = local_power(res, 'P_pv_to_bess_kW', n);
    P_grid_to_bess = local_power(res, 'P_grid_to_bess_kW', n);
    P_pv_to_bess_stored = local_power(res, 'P_pv_to_bess_stored_kW', n);
    P_grid_to_bess_stored = local_power(res, 'P_grid_to_bess_stored_kW', n);
    P_pv_to_bess_loss = local_power(res, 'P_pv_to_bess_loss_kW', n);
    P_grid_to_bess_loss = local_power(res, 'P_grid_to_bess_loss_kW', n);

    P_bess_dis_before = local_power(res, 'P_bess_discharge_before_conversion_kW', n);
    P_bess_to_load = local_power(res, 'P_bess_to_load_kW', n);
    P_bess_to_load_loss = local_power(res, 'P_bess_to_load_conversion_loss_kW', n);

    P_grid_import = local_power(res, 'P_grid_import_kW', n);
    P_grid_to_load = local_power(res, 'P_grid_to_load_kW', n);

    if isfield(res, 'E_grid_import_base')
        P_grid_no_bess = local_vec(res.E_grid_import_base(:) ./ dt_h, n);
    else
        P_grid_no_bess = NaN(n, 1);
    end

    C_grid_to_bess_import = local_cost(res, 'C_grid_to_bess_import_HUF', n);
    C_grid_to_bess_stored = local_cost(res, 'C_grid_to_bess_stored_import_equiv_HUF', n);
    C_bess_dis_before = local_cost(res, 'C_bess_discharge_before_conversion_import_equiv_HUF', n);
    C_bess_to_load = local_cost(res, 'C_bess_to_load_import_equiv_HUF', n);

    fig = figure('Name', 'Kanonikus energiaaramlasi diagnosztika', ...
        'Position', [100, 60, 1450, 1050]);

    tiledlayout(fig, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile;
    hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');
    area(ax1, t, [P_pv_to_bess, P_grid_to_bess]);
    plot(ax1, t, P_pv_to_bess_stored + P_grid_to_bess_stored, 'k-', 'LineWidth', 1.4, ...
        'DisplayName', 'BESS-ben eltárolt energiaáram');
    ylabel(ax1, 'kW');
    title(ax1, 'BESS töltés forrás szerint, konverzió előtt');
    legend(ax1, {'PV -> BESS', 'Grid -> BESS', 'BESS-ben eltárolt'}, 'Location', 'bestoutside');
    xlim(ax1, [0 24]);

    ax2 = nexttile;
    hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');
    area(ax2, t, [P_pv_to_bess_loss, P_grid_to_bess_loss, P_bess_to_load_loss]);
    ylabel(ax2, 'kW');
    title(ax2, 'Kanonikus konverziós veszteségek energiaút szerint');
    legend(ax2, {'PV -> BESS veszteség', 'Grid -> BESS veszteség', 'BESS -> load veszteség'}, ...
        'Location', 'bestoutside');
    xlim(ax2, [0 24]);

    ax3 = nexttile;
    hold(ax3, 'on'); grid(ax3, 'on'); box(ax3, 'on');
    plot(ax3, t, P_grid_import, 'k-', 'LineWidth', 1.4, 'DisplayName', 'Teljes grid import');
    plot(ax3, t, P_grid_to_load, 'b-', 'LineWidth', 1.2, 'DisplayName', 'Grid -> load');
    plot(ax3, t, P_grid_to_bess, 'r-', 'LineWidth', 1.2, 'DisplayName', 'Grid -> BESS');
    if any(isfinite(P_grid_no_bess))
        plot(ax3, t, P_grid_no_bess - P_grid_import, 'm--', 'LineWidth', 1.2, ...
            'DisplayName', 'NoBESS import - aktuális import');
    end
    ylabel(ax3, 'kW');
    title(ax3, 'Grid import felbontása és NoBESS különbség');
    legend(ax3, 'Location', 'bestoutside');
    xlim(ax3, [0 24]);

    ax4 = nexttile;
    hold(ax4, 'on'); grid(ax4, 'on'); box(ax4, 'on');
    plot(ax4, t, cumsum(C_grid_to_bess_import), 'b-', 'LineWidth', 1.3, ...
        'DisplayName', 'Grid -> BESS import költség');
    plot(ax4, t, cumsum(C_grid_to_bess_stored), 'b--', 'LineWidth', 1.3, ...
        'DisplayName', 'Grid eredetű eltárolt energia importáras értéke');
    plot(ax4, t, cumsum(C_bess_dis_before), 'r-', 'LineWidth', 1.3, ...
        'DisplayName', 'Kisütés konverzió előtt importáras érték');
    plot(ax4, t, cumsum(C_bess_to_load), 'r--', 'LineWidth', 1.3, ...
        'DisplayName', 'BESS -> load importáras érték');
    ylabel(ax4, 'HUF kumulált');
    xlabel(ax4, 'Idő [h]');
    title(ax4, 'Importáras költség / energiaérték mutatók');
    legend(ax4, 'Location', 'bestoutside');
    xlim(ax4, [0 24]);
end


function P = local_power(res, fieldName, n)

    if isfield(res, fieldName)
        P = res.(fieldName)(:);
    else
        P = zeros(n, 1);
    end

    P = local_vec(P, n);
end


function C = local_cost(res, fieldName, n)

    if isfield(res, fieldName)
        C = res.(fieldName)(:);
    else
        C = zeros(n, 1);
    end

    C = local_vec(C, n);
end


function v = local_vec(x, n)

    v = x(:);

    if isempty(v)
        v = zeros(n, 1);
        return;
    end

    if numel(v) < n
        v = [v; repmat(v(end), n - numel(v), 1)];
    elseif numel(v) > n
        v = v(1:n);
    end
end
