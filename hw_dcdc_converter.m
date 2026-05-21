function [P_low_W, P_loss_W, eta_vec, P_high_clipped_W] = hw_dcdc_converter(P_high_W, P_max_W, eta_nom, eff_load_points, eff_eta_points)
% HW_DCDC_CONVERTER
% Bidirectional DC/DC converter with load-dependent efficiency.
% Positive P_high_W: pack side to DC bus. Negative P_high_W: DC bus to pack side.

    if nargin < 4 || isempty(eff_load_points)
        eff_load_points = [0.00 1.00];
    end

    if nargin < 5 || isempty(eff_eta_points)
        eff_eta_points = [eta_nom eta_nom];
    end

    P_high_W = P_high_W(:).';
    N = numel(P_high_W);

    P_low_W = zeros(1, N);
    P_loss_W = zeros(1, N);
    eta_vec = zeros(1, N);

    P_max_W = max(P_max_W, eps);
    P_high_clipped_W = max(-P_max_W, min(P_high_W, P_max_W));

    eta_curve = hw_efficiency_from_loading( ...
        P_high_clipped_W ./ 1000, ...
        P_max_W ./ 1000, ...
        eff_load_points, ...
        eff_eta_points);

    eta_safe = max(eta_curve, eps);

    mask_dis = P_high_clipped_W > 0;
    mask_chg = P_high_clipped_W < 0;

    P_low_W(mask_dis) = P_high_clipped_W(mask_dis) ./ eta_safe(mask_dis);
    P_loss_W(mask_dis) = abs(P_low_W(mask_dis)) - abs(P_high_clipped_W(mask_dis));

    P_low_W(mask_chg) = P_high_clipped_W(mask_chg) .* eta_safe(mask_chg);
    P_loss_W(mask_chg) = abs(P_high_clipped_W(mask_chg)) - abs(P_low_W(mask_chg));

    eta_vec(mask_dis | mask_chg) = eta_curve(mask_dis | mask_chg);

    zeroMask = abs(P_high_clipped_W) < 1e-9;
    P_low_W(zeroMask) = 0;
    P_loss_W(zeroMask) = 0;
    eta_vec(zeroMask) = 0;

    P_loss_W = max(P_loss_W, 0);
end
