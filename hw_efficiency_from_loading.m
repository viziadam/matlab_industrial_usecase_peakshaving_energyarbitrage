function eta_vec = hw_efficiency_from_loading(P_kW, P_rated_kW, load_points, eta_points)
% HW_EFFICIENCY_FROM_LOADING
%
% Teljesitmenyfuggo hatasfokgorbebol szamit idolepesenkenti hatasfokot.
%
% Bemenetek:
%   P_kW        : aktualis teljesitmeny [kW]
%   P_rated_kW  : nevleges teljesitmeny [kW]
%   load_points : relativ terhelesi pontok [-], peldaul [0 0.1 0.2 0.5 1]
%   eta_points  : hatasfokpontok [-]
%
% Kimenet:
%   eta_vec     : idolepesenkenti hatasfok [-]

    P_kW = P_kW(:).';

    if P_rated_kW <= 0
        error('P_rated_kW must be positive.');
    end

    if numel(load_points) ~= numel(eta_points)
        error('load_points and eta_points must have the same length.');
    end

    load_points = load_points(:);
    eta_points = eta_points(:);

    if any(diff(load_points) < 0)
        error('load_points must be monotonically increasing.');
    end

    loading = abs(P_kW) ./ P_rated_kW;
    loading = min(max(loading, 0), 1);

    eta_vec = interp1( ...
        load_points, ...
        eta_points, ...
        loading(:), ...
        'linear', ...
        'extrap');

    eta_vec = eta_vec(:).';
    eta_vec = min(max(eta_vec, 0.01), 1.0);

    eta_vec(abs(P_kW) < 1e-9) = 0;
end