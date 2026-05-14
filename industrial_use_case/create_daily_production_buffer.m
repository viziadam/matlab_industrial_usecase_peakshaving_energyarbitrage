function create_daily_production_buffer(P_stc, year, month, day, tminVec, GHI_vec, DIF_vec, SWU_vec, Tamb_vec, sunElev_vec, sunAzim_vec, savePath)
% CREATE_DAILY_PRODUCTION_BUFFER Legenerálja a napi termelési mátrixot minden orientációra.
%
% INPUTOK:
%   year, month, day - Az adott nap dátumrészei (számként)
%   tminVec - Idővektor [0, 5, 10... 1435]
%   GHI_vec, DIF_vec, SWU_vec, Tamb_vec - Napi meteorológiai vektorok
%   sunElev_vec, sunAzim_vec - Napállás vektorok
%   savePath - A mappa elérési útja, ahová menteni kell

    % --- 1. Konfiguráció és Paraméterek ---
    tiltsX = 0:1:40;
    tiltsZ = 0:5:355;
    
    % Fájlnév generálása: resultBuffer_ORIG_yyyy_mm_dd.mat
    fileName = sprintf('resultBuffer_ORIG_%04d_%02d_%02d.mat', year, month, day);
    fullFilePath = fullfile(savePath, fileName);
    
    % Időbélyeg formázása a struktúrához (pl. '2023.06.21')
    timeDayStr = sprintf('%04d.%02d.%02d', year, month, day);

    % --- 2. Üres eredménytábla előkészítése ---
    % Kiszámoljuk az összes kombináció számát
    numComb = length(tiltsX) * length(tiltsZ);
    
    % Táblázatos forma létrehozása (table használata a tPDC oszlopban cellákkal)
    % Ez biztosítja a gyors és egyértelmű tiltX, tiltZ alapú szűrést
    resultsTable = table('Size', [numComb, 3], ...
        'VariableTypes', {'double', 'double', 'cell'}, ...
        'VariableNames', {'tiltX', 'tiltZ', 'tPDC'});

    % --- 3. Számítási ciklus (Grid Search) ---
    rowIdx = 1;
    for tx = tiltsX
        for tz = tiltsZ
            % Meghívjuk a korábban definiált validált PV modellt
            % A függvény megkapja a napi vektorokat és visszaadja a napi P_dc vektort
            P_dc_daily = pv_module_model(P_stc, tminVec, GHI_vec, DIF_vec, SWU_vec, Tamb_vec, sunElev_vec, sunAzim_vec, tx, tz);
            
            % Adatok rögzítése a táblázatba
            resultsTable.tiltX(rowIdx) = tx;
            resultsTable.tiltZ(rowIdx) = tz;
            resultsTable.tPDC{rowIdx}  = P_dc_daily; % Cellába mentjük a vektort
            
            rowIdx = rowIdx + 1;
        end
    end

    % --- 4. A tisztított resultBuffer struktúra összeállítása ---
    % Csak a szükséges mezőket hagyjuk meg a képek alapján
    resultBuffer = struct();
    resultBuffer.projectName    = 'PV_PRODUCTION_VALIDATED_BSRN_BUDAPEST';
    resultBuffer.timeDay        = timeDayStr;
    resultBuffer.timeVectorMin  = tminVec;
    resultBuffer.timeStepMin    = tminVec(2) - tminVec(1); % Pl. 5
    resultBuffer.timeIdx        = length(tminVec);
    
    % Metaadatok (üres structok vagy alapértékek)
    resultBuffer.sunPathData      = struct('elevation', sunElev_vec, 'azimuth', sunAzim_vec);
    resultBuffer.irradiationData  = struct('GHI', GHI_vec, 'DIF', DIF_vec, 'ALBEDO', SWU_vec);
    resultBuffer.temperatureData  = struct('Tamb', Tamb_vec);
    resultBuffer.windSpeedData    = struct(); 
    
    % Az új táblázatos eredmény mező
    resultBuffer.results = resultsTable;

    % --- 5. Mentés és Felülírás vizsgálata ---
    if exist(fullFilePath, 'file')
        fprintf('Fájl már létezik (%s), teljes felülírás...\n', fileName);
        delete(fullFilePath); % Biztosítjuk a tiszta mentést
    end
    
    save(fullFilePath, 'resultBuffer');
    fprintf('Sikeres mentés: %s\n', fullFilePath);
end