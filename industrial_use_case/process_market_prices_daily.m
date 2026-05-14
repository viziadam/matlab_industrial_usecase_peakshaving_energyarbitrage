function process_market_prices_daily(csvFolderPath, savePath)
% PROCESS_MARKET_PRICES_DAILY - HUPX órás árak napi 5-perces vektorokká alakítása
% Bemenetek:
%   csvFolderPath - A mappa elérési útja, ahol az energy_prices_2025.csv található
%   savePath      - A mentési mappa, ahova a napi price_YYYY_MM_DD.mat fájlokat mentjük

    % --- 1. Fájl útvonalak összeállítása és szigorú ellenőrzése ---
    csvFile = fullfile(csvFolderPath, 'energy_prices_2025.csv');
    
    assert(isfolder(csvFolderPath), 'Fatális hiba: A forrásmappa nem létezik: %s', csvFolderPath);
    assert(isfile(csvFile), 'Fatális hiba: Az energy_prices_2025.csv fájl nem található itt: %s', csvFile);
    assert(isfolder(savePath), 'Fatális hiba: A mentési mappa nem létezik: %s', savePath);

    % --- 2. Célirányos beolvasás (Energy-Charts struktúra alapján) ---
    fprintf('Áradatok beolvasása az energy_prices_2025.csv fájlból...\n');
    
    % Import opciók létrehozása: 4. sortól indul az adat, 5 oszlop van
    opts = delimitedTextImportOptions('NumVariables', 5, 'Delimiter', ',', 'DataLines', [4, Inf]);
    opts.VariableNames = {'TimeStr', 'Nuclear', 'NonRen', 'Ren', 'Price_EUR'};
    opts.VariableTypes = {'string', 'double', 'double', 'double', 'double'};
    
    % Fájl beolvasása a szabályok alapján
    T = readtable(csvFile, opts);
    
    % Idő konvertálása (ISO 8601 formátum időzónával), konvertálás UTC-re
    timeData = datetime(T.TimeStr, 'InputFormat', 'yyyy-MM-dd''T''HH:mmXXX', 'TimeZone', 'UTC'); 
    priceData_EUR = T.Price_EUR;

    % --- 3. Konkrét Ipari Árak Kiszámítása (HUF/kWh) ---
    EUR_HUF_RATE = 395.0; 
    GRID_FEE_HUF = 11.78; 
    BUY_MARGIN_HUF = 4.00; 
    SELL_FEE_HUF = 3.00;  

    % Bázisár (EUR/MWh -> HUF/kWh)
    base_huf_kwh = (priceData_EUR * EUR_HUF_RATE) / 1000;

    buy_huf = base_huf_kwh + GRID_FEE_HUF + BUY_MARGIN_HUF;
    sell_huf = max(0, base_huf_kwh - SELL_FEE_HUF);

    % Órás Timetable létrehozása
    TT_hourly = timetable(timeData, buy_huf, sell_huf, 'VariableNames', {'BuyPrice', 'SellPrice'});

    % --- 4. Sűrítés 5 perces felbontásra (Lépcsős kiterjesztés) ---
    fprintf('Órás adatok kiterjesztése 5-perces rácsra...\n');
    TT_5min = retime(TT_hourly, 'regular', 'previous', 'TimeStep', minutes(5));

    % --- 5. Napi Cachelés (.mat fájlok mentése) ---
    fprintf('Napi struktúrák generálása...\n');
    dates = dateshift(TT_5min.Properties.RowTimes, 'start', 'day');
    uniqueDates = unique(dates);
    
    timeMinAxis = 0:5:1435; % Időtengely percben
    validDaysCount = 0;
    
    for i = 1:length(uniqueDates)
        currentDay = uniqueDates(i);
        dailyData = TT_5min(dates == currentDay, :);
        
        % Ellenőrzés: 24 óra * 12 = 288 adatpont
        if height(dailyData) == 288
            
            priceCache = struct();
            priceCache.projectName    = 'Industrial_Market_Prices';
            priceCache.dateString     = datestr(currentDay, 'yyyy.mm.dd');
            priceCache.timeMinAxis    = timeMinAxis; % 1x288 sorvektor
            
            % Adatok mentése (oszlopvektorból 1x288 sorvektorrá alakítva)
            priceCache.buyPrice_HUF   = dailyData.BuyPrice';
            priceCache.sellPrice_HUF  = dailyData.SellPrice';
            
            % Fájl mentése (pl: price_2025_01_01.mat)
            fileName = sprintf('price_%s.mat', datestr(currentDay, 'yyyy_mm_dd'));
            fullFilePath = fullfile(savePath, fileName);
            save(fullFilePath, 'priceCache');
            
            validDaysCount = validDaysCount + 1;
        end
    end
    
    fprintf('Kész! %d db napi price .mat fájl (1x288-as vektorokkal) elmentve a mappába.\n', validDaysCount);
end