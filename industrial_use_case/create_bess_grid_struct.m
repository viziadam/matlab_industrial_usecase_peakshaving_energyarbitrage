function bess_results = create_bess_grid_struct()
    % CREATE_BESS_GRID_STRUCT 
    % Bemeneti paraméterek nélkül, belső konfiguráció alapján generálja le
    % a BESS rácspontokat, majd elmenti az aktuális mappába.

    % ==========================================
    % --- BELSŐ KONFIGURÁCIÓ ---
    % ==========================================
    E_ratio_grid  = 0:0.05:3; % Akku/Inverter arányok (órákban)
    C_rate_grid   = [0.5];                             % C-ráták (pl. 0.5C)
    
    Pdc_kWp       = 749;                               % Fix napelem csúcsteljesítmény [kWp]
    Pinv_kW       = 550;                               % Fix AC inverter limit (400 + 150) [kW]
    LifetimeYears = 10;                                % Szimulált élettartam [év]
    % ==========================================

    % Rács méreteinek meghatározása
    num_E = numel(E_ratio_grid);
    num_C = numel(C_rate_grid);
    total_points = num_E * num_C;
    
    % Valós DC/AC arány kiszámítása a fix rendszerre
    actual_dcac = Pdc_kWp / Pinv_kW;

    % Üres struktúra tömb előfoglalása a memóriában
    % A mezőnevek pontosan megegyeznek a korábbi struktúráddal
    bess_results = repmat(struct(...
        'E_bess', NaN, ...        
        'C_rate', NaN, ...
        'P_max', NaN, ...
        'dcac', actual_dcac, ...  
        'Pdc', Pdc_kWp, ...
        'Pinv', Pinv_kW, ...
        'LifetimeYears', LifetimeYears, ...
        'runAt', NaT, ...
        'results', struct() ...   % Üres konténer a lefutott adatoknak
    ), total_points, 1);

    % Rács feltöltése a valós értékekkel
    idx = 1;
    for i = 1:num_E
        for j = 1:num_C
            % Valós kapacitás [kWh] = arány * Inverter mérete [kW]
            E_cap = E_ratio_grid(i) * Pinv_kW; 
            C_r = C_rate_grid(j);
            
            bess_results(idx).E_bess = E_cap;
            bess_results(idx).C_rate = C_r;
            bess_results(idx).P_max  = E_cap * C_r;
            bess_results(idx).runAt  = datetime('now');
            
            idx = idx + 1;
        end
    end

    % --- MENTÉS AZ AKTUÁLIS KÖNYVTÁRBA ---
    % A 'pwd' (Print Working Directory) az aktuális MATLAB mappát adja vissza
    fileName = 'bess_simulation_grid.mat';
    savePath = fullfile(pwd, fileName);
    
    save(savePath, 'bess_results');
    
    % Visszajelzés a Parancsablakba
    fprintf('BESS rács (%d pont) sikeresen legenerálva!\n', total_points);
    fprintf('Fájl mentve ide: %s\n', savePath);
end