function validate_against_consultant(folderPath)
% VALIDATE_AGAINST_CONSULTANT - A saját PV modell futtatása a konzulens adatain.
% Bemenet: folderPath - A konzulens .mat fájljait tartalmazó mappa

    % --- 1. Mappa beolvasása ---
    if nargin < 1 || isempty(folderPath)
        folderPath = uigetdir('', 'Válaszd ki a konzulens .mat fájljainak mappáját');
        if folderPath == 0, return; end
    end

    files = dir(fullfile(folderPath, '*.mat'));
    if isempty(files)
        warning('Nincs .mat fájl a megadott mappában!'); 
        return; 
    end

    numFiles = length(files);
    fprintf('%d darab konzulensi napi fájl feldolgozása indul...\n', numFiles);

    % --- 2. Konfiguráció és Paraméterek (A mi 32 orientációnk) ---
    tiltsX = [0, 5, 10, 15, 20, 30, 35, 40];
    tiltsZ = [0, 90, 180, 270];
    numComb = length(tiltsX) * length(tiltsZ);

    % --- 3. Fájlok iterálása ---
    for i = 1:numFiles
        fullFilePath = fullfile(folderPath, files(i).name);
        
        % Adat betöltése
        try
            data = load(fullFilePath);
            if isfield(data, 'resultBuffer')
                rb = data.resultBuffer;
            else
                fprintf('Kihagyva: %s (Nincs benne resultBuffer)\n', files(i).name);
                continue;
            end
        catch
            fprintf('Hiba a fájl olvasásakor: %s\n', files(i).name);
            continue;
        end
        
        % --- 4. Bemeneti adatok kinyerése a KONZULENS struktúrájából ---
        try
            tminVec     = rb.timeVectorMin;
            sunElev_vec = rb.sunPathData.elevation;
            sunAzim_vec = rb.sunPathData.azimuth;
            
            % Besugárzási mezők (Dinamikus keresés a képeken látható "irradiationDif..." miatt)
            irrFields = fieldnames(rb.irradiationData);
            ghiField = irrFields{contains(irrFields, 'GHI', 'IgnoreCase', true)};
            difField = irrFields{contains(irrFields, 'Dif', 'IgnoreCase', true)};
            
            GHI_vec = rb.irradiationData.(ghiField);
            DIF_vec = rb.irradiationData.(difField);
            
            % Albedó pótlása (Mivel a konzulens fájljában látszólag nincs SWU)
            SWU_vec = GHI_vec .* 0.2; 
            
            % Hőmérséklet (A képen "temperature" néven szerepel)
            Tamb_vec = rb.temperatureData.temperature;
            
        catch ME
            fprintf('Hiányzó vagy eltérő adatmező a %s fájlban! Hiba: %s\n', files(i).name, ME.message);
            continue;
        end
        
        % --- 5. Üres eredménytábla előkészítése a mi modellünkhöz ---
        resultsTable = table('Size', [numComb, 3], ...
            'VariableTypes', {'double', 'double', 'cell'}, ...
            'VariableNames', {'tiltX', 'tiltZ', 'tPDC'});
            
        % --- 6. Számítási ciklus a SAJÁT PV modellünkkel ---
        rowIdx = 1;
        for tx = tiltsX
            for tz = tiltsZ
                % A saját modelled meghívása a konzulens bemeneteivel
                % (Feltételezem, hogy a pv_module_model.m ott van a mappádban)
                P_dc_daily = pv_module_model(tminVec, GHI_vec, DIF_vec, SWU_vec, Tamb_vec, sunElev_vec, sunAzim_vec, tx, tz);
                
                % Eredmények mentése a táblázatba
                resultsTable.tiltX(rowIdx) = tx;
                resultsTable.tiltZ(rowIdx) = tz;
                resultsTable.tPDC{rowIdx}  = P_dc_daily; 
                
                rowIdx = rowIdx + 1;
            end
        end
        
        % --- 7. A results2 hozzáfűzése és a fájl FELÜLÍRÁSA ---
        rb.results2 = resultsTable; % Új mező létrehozása a struktúrában
        
        % A felülírás megvédése (az eredeti változónevet használjuk, ami a 'resultBuffer')
        resultBuffer = rb;
        save(fullFilePath, 'resultBuffer');
        
        % Opcionális: Százalékos kijelzés
        if mod(i, 50) == 0
            fprintf('Feldolgozva: %d / %d fájl...\n', i, numFiles);
        end
    end

    fprintf('Sikeresen lefutott! A konzulens fájljai kibővítve a "results2" mezővel.\n');
end