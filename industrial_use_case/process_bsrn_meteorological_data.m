function process_bsrn_meteorological_data(P_stc, inputFolderPath, outputFolderPath)
% pelda meghivas:
% process_bsrn_meteorological_data("C:\Users\Vizi\Desktop\Egyetem\MSC VIK\Villamosmérnök\Diplomamunka\Napelemes rendszerek\Szimulaciok\Rendszerelemzes\industrial_use_case\BUD_basic_rad_2019-06_etseq\datasets", "C:\Users\Vizi\Desktop\Egyetem\MSC VIK\Villamosmérnök\Diplomamunka\Napelemes rendszerek\Szimulaciok\Rendszerelemzes\industrial_use_case\production")
% PROCESS_BSRN_METEOROLOGICAL_DATA Feldolgozza a havi BSRN .tab fájlokat,
% és napi bontásban legenerálja az 5 perces termelési adatstruktúrákat.
%
% INPUT:
%   inputFolderPath  - A letöltött .tab fájlokat tartalmazó mappa útvonala
%   outputFolderPath - A mappa, ahová a napi .mat fájlok kerülnek mentésre

    % Ellenőrizzük, létezik-e a kimeneti mappa, ha nem, létrehozzuk
    if ~exist(outputFolderPath, 'dir')
        mkdir(outputFolderPath);
    end

    % 1. Kikeressük az összes .tab fájlt a bemeneti mappából
    filePattern = fullfile(inputFolderPath, '*.tab');
    bsrnFiles = dir(filePattern);
    
    if isempty(bsrnFiles)
        error('Nem található .tab fájl a megadott mappában: %s', inputFolderPath);
    end
    
    fprintf('Összesen %d db havi fájl feldolgozása indul...\n', length(bsrnFiles));

    % Budapest - Lőrinc (BSRN állomás) koordinátái a napállás számításhoz
    lat = 47.429;
    lon = 19.182;

    % 2. Végigiterálunk minden havi fájlon
    for f = 1:length(bsrnFiles)
        fullFilePath = fullfile(inputFolderPath, bsrnFiles(f).name);
        fprintf('Feldolgozás alatt: %s\n', bsrnFiles(f).name);
        
        % --- A. Fejléc dinamikus megkeresése ---
        lines = readlines(fullFilePath);
        headerLineIdx = find(startsWith(lines, 'Date/Time'), 1);
        
        if isempty(headerLineIdx)
            warning('Nem található Date/Time fejléc a fájlban: %s. Kihagyva.', bsrnFiles(f).name);
            continue;
        end
        
        % --- B. Adatok beolvasása ---
        opts = detectImportOptions(fullFilePath, 'FileType', 'text', 'Delimiter', '\t');
        opts.VariableNamesLine = headerLineIdx;
        opts.DataLines = [headerLineIdx + 1, Inf];
        
        % Oszlopok beolvasása (A MATLAB a speciális karaktereket '_' -re cseréli)
        data = readtable(fullFilePath, opts);
        
        % Dinamikus oszlopazonosítás (hogy a W/m**2 formátumváltozások ne okozzanak hibát)
        colNames = data.Properties.VariableNames;
        idxDate = find(contains(colNames, 'Date_Time'), 1);
        idxSWD  = find(contains(colNames, 'SWD') & ~contains(colNames, 'std') & ~contains(colNames, 'min') & ~contains(colNames, 'max'), 1);
        idxDIF  = find(contains(colNames, 'DIF') & ~contains(colNames, 'std') & ~contains(colNames, 'min') & ~contains(colNames, 'max'), 1);
        idxSWU  = find(contains(colNames, 'SWU') & ~contains(colNames, 'std') & ~contains(colNames, 'min') & ~contains(colNames, 'max'), 1);
        idxT2   = find(contains(colNames, 'T2'), 1);
        
        dates = data{:, idxDate};
        
        if ~isdatetime(dates)
            try
                dates = datetime(dates, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss');
            catch
                % Ha nincs másodperc a formátumban (ahogy a te tab fájlodban sincs)
                dates = datetime(dates, 'InputFormat', 'yyyy-MM-dd''T''HH:mm');
            end
        end
        % ----------------------------------------------------------------------
        
        % --- C. Napi bontás ciklus ---
        uniqueDays = unique(dates(1:end) - timeofday(dates(1:end))); % Éjféli időbélyegek
        
        for d = 1:length(uniqueDays)
            currentDay = uniqueDays(d);
            
            % Dátum kinyerése a mentéshez
            [y, m, day] = ymd(currentDay);
            
            % Az aktuális napra eső adatok logikai indexe
            dayMask = (dates >= currentDay) & (dates < (currentDay + days(1)));
            
            % Ha nincs adat a napra, ugrunk
            if sum(dayMask) == 0
                continue;
            end
            
            % Nyers perces adatok kinyerése
            rawTime = dates(dayMask);
            rawGHI  = data{dayMask, idxSWD};
            rawDIF  = data{dayMask, idxDIF};
            rawSWU  = data{dayMask, idxSWU};
            rawTamb = data{dayMask, idxT2};
            
            % --- JAVÍTÁS: Cellatömbök konvertálása számmá (double) ---
            if iscell(rawGHI) || isstring(rawGHI)
                rawGHI = str2double(string(rawGHI));
            end
            if iscell(rawDIF) || isstring(rawDIF)
                rawDIF = str2double(string(rawDIF));
            end
            if iscell(rawSWU) || isstring(rawSWU)
                rawSWU = str2double(string(rawSWU));
            end
            if iscell(rawTamb) || isstring(rawTamb)
                rawTamb = str2double(string(rawTamb));
            end
            
            % --- D. Tisztítás és Szinkronizálás (Robusztus verzió) ---
            % BSRN-ben a hiányzó sugárzás gyakran -1 vagy <-100.
            rawGHI(rawGHI < 0) = 0;
            rawDIF(rawDIF < 0) = 0;
            rawSWU(rawSWU < 0) = 0;
            % Hőmérsékletnél a -99.9 jelenti a hibát
            rawTamb(rawTamb < -50) = NaN; 
            
            % Létrehozunk egy tökéletes, megszakítás nélküli 1 perces tengelyt a napra (1440 pont)
            perfect1MinAxis = (currentDay : minutes(1) : (currentDay + hours(23) + minutes(59)))';
            
            % 1. GHI interpoláció (extrapoláció helyett 0-val töltjük fel a peremeket)
            valid = ~isnan(rawGHI);
            [uTime, uIdx] = unique(rawTime(valid));
            uVal = rawGHI(valid); uVal = uVal(uIdx);
            if length(uTime) >= 2
                cleanGHI = interp1(uTime, uVal, perfect1MinAxis, 'linear', 0); % <-- JAVÍTVA: 'extrap' helyett 0
            else
                cleanGHI = zeros(size(perfect1MinAxis));
            end
            
            % 2. DIF interpoláció
            valid = ~isnan(rawDIF);
            [uTime, uIdx] = unique(rawTime(valid));
            uVal = rawDIF(valid); uVal = uVal(uIdx);
            if length(uTime) >= 2
                cleanDIF = interp1(uTime, uVal, perfect1MinAxis, 'linear', 0); % <-- JAVÍTVA: 0
            else
                cleanDIF = zeros(size(perfect1MinAxis));
            end
            
            % 3. SWU interpoláció
            valid = ~isnan(rawSWU);
            [uTime, uIdx] = unique(rawTime(valid));
            uVal = rawSWU(valid); uVal = uVal(uIdx);
            if length(uTime) >= 2
                cleanSWU = interp1(uTime, uVal, perfect1MinAxis, 'linear', 0); % <-- JAVÍTVA: 0
            else
                cleanSWU = zeros(size(perfect1MinAxis));
            end
            
            % 4. Tamb (Hőmérséklet) interpoláció (Itt maradhat az extrap, vagy 'nearest', mert a 0 fok torzítana)
            valid = ~isnan(rawTamb);
            [uTime, uIdx] = unique(rawTime(valid));
            uVal = rawTamb(valid); uVal = uVal(uIdx);
            if length(uTime) >= 2
                cleanTamb = interp1(uTime, uVal, perfect1MinAxis, 'nearest', 'extrap'); % <-- JAVÍTVA: nearest jobb a hőmérsékletre
            else
                cleanTamb = 20 * ones(size(perfect1MinAxis));
            end
            
            % Extrapoláció miatt esetlegesen becsúszó negatív értékek nullázása
            cleanGHI(cleanGHI < 0) = 0; 
            cleanDIF(cleanDIF < 0) = 0; 
            cleanSWU(cleanSWU < 0) = 0;
            
            % --- E. Downsampling 5 percesre (1440 -> 288 pont) ---
            % Átlagolás 5 perces blokkokban, hogy megmaradjon az energiaegyensúly
            GHI_5min  = mean(reshape(cleanGHI, 5, []), 1);
            DIF_5min  = mean(reshape(cleanDIF, 5, []), 1);
            SWU_5min  = mean(reshape(cleanSWU, 5, []), 1);
            Tamb_5min = mean(reshape(cleanTamb, 5, []), 1);
            
            % 5 perces idővektor (0-tól 1435-ig, percekben éjféltől)
            tminVec = 0:5:1435;
            
            % 5 perces datetime vektor a napállás számításhoz
            perfect5MinAxis = perfect1MinAxis(1:5:end);
            
            % --- F. Napállás számítás az 5 perces tengelyre ---
            [sunElev_vec, sunAzim_vec] = calculate_sun_position(perfect5MinAxis, lat, lon);
            
            % --- G. Átadás a resultBuffer generátornak ---
            % (Itt hívjuk meg a korábban megírt függvényedet)
            create_daily_production_buffer(P_stc, y, m, day, tminVec, ...
                GHI_5min, DIF_5min, SWU_5min, Tamb_5min, ...
                sunElev_vec, sunAzim_vec, outputFolderPath);
        end
    end
    fprintf('\nAz összes fájl feldolgozása és a napi struktúrák mentése befejeződött.\n');
end

% --- LOKÁLIS FÜGGVÉNY: Napállás kalkulátor ---
function [elevation, azimuth] = calculate_sun_position(datetimeVec, lat, lon)
    % Gyors és robusztus napállás kalkulátor (közelítő SPA)
    % datetimeVec: UTC időbélyegek
    % Visszatérési értékek fokban (elevation, azimuth)
    
    % Julián nap számítása (UTC)
    [y, m, d] = ymd(datetimeVec);
    [h, mn, s] = hms(datetimeVec); % <--- JAVÍTVA: min helyett mn!
    
    % Napok száma az évben
    dayOfYear = day(datetimeVec, 'dayofyear');
    
    % Fractional hour
    hour_utc = h + mn/60 + s/3600; % <--- JAVÍTVA: min helyett mn!
    
    % Eq of Time (percek) és Deklináció (fok) Spencer (1971) alapján
    B = 2 * pi * (dayOfYear - 1) / 365;
    
    eqtime = 229.18 * (0.000075 + 0.001868 * cos(B) - 0.032077 * sin(B) ...
             - 0.014615 * cos(2*B) - 0.040849 * sin(2*B));
             
    declination = 0.006918 - 0.399912 * cos(B) + 0.070257 * sin(B) ...
                  - 0.006758 * cos(2*B) + 0.000907 * sin(2*B) ...
                  - 0.002697 * cos(3*B) + 0.00148 * sin(3*B);
    declination = rad2deg(declination);
    
    % True Solar Time (TST)
    time_offset = eqtime + (4 * lon);
    tst = hour_utc * 60 + time_offset;
    
    % Hour Angle (HRA) fokban
    hra = (tst / 4) - 180;
    
    % Elevation
    sin_elev = sind(declination) .* sind(lat) + cosd(declination) .* cosd(lat) .* cosd(hra);
    elevation = asind(sin_elev);
    
    % Azimuth (0 = Észak, 180 = Dél)
    cos_azim = (sind(declination) .* cosd(lat) - cosd(declination) .* sind(lat) .* cosd(hra)) ./ cosd(elevation);
    % Numerikus hibák kiküszöbölése (-1 és 1 közé szorítás)
    cos_azim = max(-1, min(1, cos_azim)); % Most már a beépített min() függvény fut le!
    azimuth = acosd(cos_azim);
    
    % Délutáni korrekció
    idx = hra > 0;
    azimuth(idx) = 360 - azimuth(idx);
    
    % Sorvektorrá alakítás a korábbi struktúrához
    elevation = elevation';
    azimuth = azimuth';
end