function process_smart_company_pw(csvFolderPath, savePath)
% PROCESS_SMART_COMPANY_PW - Tiszta, nem negatív Bruttó Fogyasztás generálása
% 5 perces időlépéssel: Teljesítmény átlagolva, Energia összegezve.

    % --- 1. Fájl útvonalak összeállítása és szigorú ellenőrzése ---
    csvFile_P = fullfile(csvFolderPath, 'electricity_P.csv');
    csvFile_W = fullfile(csvFolderPath, 'electricity_W.csv');
    
    assert(isfile(csvFile_P), 'Fatális hiba: A Teljesítmény (P) fájl nem található itt: %s', csvFile_P);
    assert(isfile(csvFile_W), 'Fatális hiba: Az Energia (W) fájl nem található itt: %s', csvFile_W);
    assert(isfolder(savePath), 'Fatális hiba: A mentési mappa nem létezik: %s', savePath);

    % --- 2. Adatok beolvasása ---
    fprintf('Fájlok beolvasása (Ez a fájlmérettől függően eltarthat 1-2 percig)...\n');
    TP = readtable(csvFile_P, 'VariableNamingRule', 'preserve');
    TW = readtable(csvFile_W, 'VariableNamingRule', 'preserve');
    
    % Időoszlopok konvertálása datetime formátumra
    timeColP = TP.Properties.VariableNames{1};
    timeColW = TW.Properties.VariableNames{1};
    TP.(timeColP) = datetime(TP.(timeColP), 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
    TW.(timeColW) = datetime(TW.(timeColW), 'InputFormat', 'yyyy-MM-dd HH:mm:ss');

    % --- 3. TISZTA BRUTTÓ FOGYASZTÁS számítása ---
    fprintf('Tiszta Bruttó Fogyasztás (Gross Load) számítása és szűrése...\n');
    
    % Segédfüggvény (NaN értékeket 0-ként kezeli)
    getSummedCols = @(T, name) sum(T{:, contains(T.Properties.VariableNames, name, 'IgnoreCase', true)}, 2, 'omitnan');
    
    % JAVÍTOTT Fizikai mérleg: Mivel a PV és CHP termelés NEGATÍV, levonjuk őket, 
    % hogy matematikailag hozzáadódjanak a hálózati (pozitív) terheléshez!
    total_P = getSummedCols(TP, 'total') - getSummedCols(TP, 'pv') - getSummedCols(TP, 'chp');
    total_W = getSummedCols(TW, 'total') - getSummedCols(TW, 'pv') - getSummedCols(TW, 'chp');
    
    % *** SZIGORÚ SZŰRÉS A KÉRÉSEDNEK MEGFELELŐEN ***
    % Minden 0 alatti (negatív) értéket felhúzunk nullára!
    total_P = max(0, total_P); 
    total_W = max(0, total_W);

    % Timetable létrehozása
    TTP = timetable(TP.(timeColP), total_P, 'VariableNames', {'TotalLoad_P'});
    TTW = timetable(TW.(timeColW), total_W, 'VariableNames', {'TotalLoad_W'});

    % --- 4. Sűrítés (Retime) 5 perces felbontásra ---
    fprintf('Adatok sűrítése 5 perces felbontásra (P: átlagolás, W: összegzés)...\n');
    
    % TTP: Teljesítmény átlagolása
    TTP_5min = retime(TTP, 'regular', 'mean', 'TimeStep', minutes(5)); 
    % TTW: Energia összegezése
    TTW_5min = retime(TTW, 'regular', 'sum', 'TimeStep', minutes(5));  
    
    % Szinkronizáljuk a két táblát egy közös Timetable-be
    TT_Combined = synchronize(TTP_5min, TTW_5min, 'intersection');
    
    % Adathiány (NaN) kezelése az 5-perces rácson
    TT_Combined.TotalLoad_P = fillmissing(TT_Combined.TotalLoad_P, 'previous'); 
    TT_Combined.TotalLoad_W = fillmissing(TT_Combined.TotalLoad_W, 'constant', 0); 
    
    % Utolsó biztonsági ellenőrzés a szinkronizálás és fillmissing után
    TT_Combined.TotalLoad_P = max(0, TT_Combined.TotalLoad_P);
    TT_Combined.TotalLoad_W = max(0, TT_Combined.TotalLoad_W);

    % --- 5. Napi Cachelés és timeMinAxis létrehozása ---
    fprintf('Napi struktúrák generálása...\n');
    dates = dateshift(TT_Combined.Time, 'start', 'day');
    uniqueDates = unique(dates);
    
    timeMinAxis = 0:5:1435; % Időtengely percben
    validDaysCount = 0;
    
    for i = 1:length(uniqueDates)
        currentDay = uniqueDates(i);
        dailyData = TT_Combined(dates == currentDay, :);
        
        % Ellenőrzés: 24 óra * 12 = 288 adatpont
        if height(dailyData) == 288
            
            consumptionCache = struct();
            consumptionCache.projectName    = 'Pure_Consumption_PW';
            consumptionCache.dateString     = datestr(currentDay, 'yyyy.mm.dd');
            consumptionCache.timeMinAxis    = timeMinAxis; % 1x288 sorvektor
            
            % Adatok mentése (oszlopvektorból 1x288 sorvektorrá alakítva)
            consumptionCache.powerTotal_W   = dailyData.TotalLoad_P';
            consumptionCache.energyTotal_Wh = dailyData.TotalLoad_W';
            
            % Fájl mentése
            fileName = sprintf('consumption_ORIG_%s.mat', datestr(currentDay, 'yyyy_mm_dd'));
            fullFilePath = fullfile(savePath, fileName);
            save(fullFilePath, 'consumptionCache');
            
            validDaysCount = validDaysCount + 1;
        end
    end
    
    fprintf('Feldolgozás kész! %d db tiszta, nem negatív napi .mat fájl elmentve a mappába.\n', validDaysCount);
end