function [Load, Price] = build_load_price_cache()
% BUILD_LOAD_PRICE_CACHE
%
% Ipari PV+BESS szimulációhoz fogyasztási és energiaár adatok betöltése.
%
% Fontos működés:
%   - Nem hoz létre mesterséges 365 napos éveket.
%   - Nem tölt fel hiányzó napokat 0-val.
%   - Csak a ténylegesen meglévő consumption napok kerülnek be.
%   - Csak olyan consumption éveket használ, ahol legalább 350 nap van.
%   - A price adat egy vagy több évből jöhet, de month-day alapon kerül
%     ráillesztésre minden valid load napra.
%   - Ha adott load naphoz nincs price month-day, akkor az a nap kimarad.
%
% Kimenet:
%   Load(i).date
%   Load(i).year
%   Load(i).month
%   Load(i).day
%   Load(i).mmddKey
%   Load(i).P_load_kW
%   Load(i).dt_h
%
%   Price(i).date          - a load nap dátuma
%   Price(i).sourceDate    - az eredeti price fájl dátuma
%   Price(i).year
%   Price(i).month
%   Price(i).day
%   Price(i).mmddKey
%   Price(i).buy_huf
%   Price(i).sell_huf
%   Price(i).dt_h

    persistent cachedLoad cachedPrice

    if ~isempty(cachedLoad)
        fprintf('Load és Price adatok betöltve a memóriából (RAM).\n');
        Load = cachedLoad;
        Price = cachedPrice;
        return;
    end

    fprintf('Load és Price adatok betöltése valós napok alapján...\n');

    minDaysPerYear = 350;

    thisDir = fileparts(mfilename('fullpath'));
    loadDir = fullfile(thisDir, 'consumption');
    priceDir = fullfile(thisDir, 'energy_prices');

    loadFiles = dir(fullfile(loadDir, '*.mat'));
    priceFiles = dir(fullfile(priceDir, '*.mat'));

    if isempty(loadFiles)
        error('Nem találhatók .mat fájlok a consumption mappában: %s', loadDir);
    end

    if isempty(priceFiles)
        error('Nem találhatók .mat fájlok az energy_prices mappában: %s', priceDir);
    end

    % =====================================================================
    % 1) Consumption fájlok beolvasása
    % =====================================================================
    loadRaw = struct( ...
        'date', {}, ...
        'year', {}, ...
        'month', {}, ...
        'day', {}, ...
        'mmddKey', {}, ...
        'P_load_kW', {}, ...
        'dt_h', {}, ...
        'fileName', {});

    for i = 1:numel(loadFiles)

        filePath = fullfile(loadDir, loadFiles(i).name);
        S = load(filePath);

        if ~isfield(S, 'consumptionCache')
            error('A consumption fájl nem tartalmaz consumptionCache változót: %s', loadFiles(i).name);
        end

        cc = S.consumptionCache;

        requiredFields = {'dateString', 'timeMinAxis', 'powerTotal_W'};

        for f = 1:numel(requiredFields)
            if ~isfield(cc, requiredFields{f})
                error('A consumptionCache nem tartalmazza ezt a mezőt: %s, fájl: %s', ...
                    requiredFields{f}, loadFiles(i).name);
            end
        end

        dt = local_parse_date_string(cc.dateString);

        if month(dt) == 2 && day(dt) == 29
            continue;
        end

        P_load_kW = cc.powerTotal_W(:).' / 1000;
        dt_h = local_dt_from_time_axis(cc.timeMinAxis, numel(P_load_kW), loadFiles(i).name);

        item = struct();

        item.date = dt;
        item.year = year(dt);
        item.month = month(dt);
        item.day = day(dt);
        item.mmddKey = local_mmdd_key(item.month, item.day);
        item.P_load_kW = P_load_kW;
        item.dt_h = dt_h;
        item.fileName = string(loadFiles(i).name);

        loadRaw(end+1) = item; %#ok<AGROW>
    end

    if isempty(loadRaw)
        error('Nem maradt beolvasható consumption nap.');
    end

    % =====================================================================
    % 2) Load évek szűrése legalább 350 nap alapján
    % =====================================================================
    loadYears = unique([loadRaw.year]);

    validLoadYears = [];

    for i = 1:numel(loadYears)

        y = loadYears(i);
        nDaysY = sum([loadRaw.year] == y);

        if nDaysY >= minDaysPerYear
            validLoadYears(end+1) = y; %#ok<AGROW>
        else
            fprintf('Consumption év kihagyva: %d, csak %d nap áll rendelkezésre.\n', ...
                y, nDaysY);
        end
    end

    if isempty(validLoadYears)
        error('Nincs olyan consumption év, ahol legalább %d nap rendelkezésre áll.', ...
            minDaysPerYear);
    end

    keepLoad = ismember([loadRaw.year], validLoadYears);
    loadRaw = loadRaw(keepLoad);

    [~, orderLoad] = sort([loadRaw.date]);
    loadRaw = loadRaw(orderLoad);

    % =====================================================================
    % 3) Price fájlok beolvasása
    % =====================================================================
    priceRaw = struct( ...
        'date', {}, ...
        'year', {}, ...
        'month', {}, ...
        'day', {}, ...
        'mmddKey', {}, ...
        'buy_huf', {}, ...
        'sell_huf', {}, ...
        'dt_h', {}, ...
        'fileName', {});

    for i = 1:numel(priceFiles)

        filePath = fullfile(priceDir, priceFiles(i).name);
        S = load(filePath);

        if ~isfield(S, 'priceCache')
            error('A price fájl nem tartalmaz priceCache változót: %s', priceFiles(i).name);
        end

        pc = S.priceCache;

        requiredFields = {'dateString', 'timeMinAxis', 'buyPrice_HUF', 'sellPrice_HUF'};

        for f = 1:numel(requiredFields)
            if ~isfield(pc, requiredFields{f})
                error('A priceCache nem tartalmazza ezt a mezőt: %s, fájl: %s', ...
                    requiredFields{f}, priceFiles(i).name);
            end
        end

        dt = local_parse_date_string(pc.dateString);

        if month(dt) == 2 && day(dt) == 29
            continue;
        end

        buy_huf = pc.buyPrice_HUF(:).';
        sell_huf = pc.sellPrice_HUF(:).';

        if numel(buy_huf) ~= numel(sell_huf)
            error('A buyPrice_HUF és sellPrice_HUF vektorhossz eltér, fájl: %s', ...
                priceFiles(i).name);
        end

        dt_h = local_dt_from_time_axis(pc.timeMinAxis, numel(buy_huf), priceFiles(i).name);

        item = struct();

        item.date = dt;
        item.year = year(dt);
        item.month = month(dt);
        item.day = day(dt);
        item.mmddKey = local_mmdd_key(item.month, item.day);
        item.buy_huf = buy_huf;
        item.sell_huf = sell_huf;
        item.dt_h = dt_h;
        item.fileName = string(priceFiles(i).name);

        priceRaw(end+1) = item; %#ok<AGROW>
    end

    if isempty(priceRaw)
        error('Nem maradt beolvasható price nap.');
    end

    % =====================================================================
    % 4) Price év kiválasztása
    % =====================================================================
    priceYears = unique([priceRaw.year]);

    validPriceYears = [];

    for i = 1:numel(priceYears)

        y = priceYears(i);
        nDaysY = sum([priceRaw.year] == y);

        if nDaysY >= minDaysPerYear
            validPriceYears(end+1) = y; %#ok<AGROW>
        else
            fprintf('Price év kihagyva: %d, csak %d nap áll rendelkezésre.\n', ...
                y, nDaysY);
        end
    end

    if isempty(validPriceYears)
        error('Nincs olyan price év, ahol legalább %d nap rendelkezésre áll.', ...
            minDaysPerYear);
    end

    % Ha több price év van, az első valid évet használjuk sablonként.
    priceTemplateYear = validPriceYears(1);

    fprintf('Price sablonév: %d\n', priceTemplateYear);

    priceTemplate = priceRaw([priceRaw.year] == priceTemplateYear);

    % =====================================================================
    % 5) Price map month-day kulcs alapján
    % =====================================================================
    priceMap = containers.Map('KeyType', 'char', 'ValueType', 'double');

    for i = 1:numel(priceTemplate)

        key = priceTemplate(i).mmddKey;

        if priceMap.isKey(key)
            error('Duplikált price month-day kulcs a sablonévben: %s', key);
        end

        priceMap(key) = i;
    end

    % =====================================================================
    % 6) Load napok és price sablon összekapcsolása
    % =====================================================================
    Load = struct( ...
        'date', {}, ...
        'year', {}, ...
        'month', {}, ...
        'day', {}, ...
        'mmddKey', {}, ...
        'P_load_kW', {}, ...
        'dt_h', {}, ...
        'fileName', {});

    Price = struct( ...
        'date', {}, ...
        'sourceDate', {}, ...
        'year', {}, ...
        'month', {}, ...
        'day', {}, ...
        'mmddKey', {}, ...
        'buy_huf', {}, ...
        'sell_huf', {}, ...
        'dt_h', {}, ...
        'fileName', {});

    skippedNoPrice = 0;

    for i = 1:numel(loadRaw)

        key = loadRaw(i).mmddKey;

        if ~priceMap.isKey(key)
            skippedNoPrice = skippedNoPrice + 1;
            continue;
        end

        pIdx = priceMap(key);
        p = priceTemplate(pIdx);

        if abs(loadRaw(i).dt_h - p.dt_h) > 1e-12
            error('Eltérő dt_h load és price között. Load date: %s, price source date: %s', ...
                datestr(loadRaw(i).date, 'yyyy-mm-dd'), ...
                datestr(p.date, 'yyyy-mm-dd'));
        end

        if numel(loadRaw(i).P_load_kW) ~= numel(p.buy_huf)
            error('Eltérő vektorhossz load és price között. Load date: %s, price source date: %s', ...
                datestr(loadRaw(i).date, 'yyyy-mm-dd'), ...
                datestr(p.date, 'yyyy-mm-dd'));
        end

        Load(end+1) = loadRaw(i); %#ok<AGROW>

        priceItem = struct();

        priceItem.date = loadRaw(i).date;
        priceItem.sourceDate = p.date;
        priceItem.year = loadRaw(i).year;
        priceItem.month = loadRaw(i).month;
        priceItem.day = loadRaw(i).day;
        priceItem.mmddKey = loadRaw(i).mmddKey;
        priceItem.buy_huf = p.buy_huf;
        priceItem.sell_huf = p.sell_huf;
        priceItem.dt_h = p.dt_h;
        priceItem.fileName = p.fileName;

        Price(end+1) = priceItem; %#ok<AGROW>
    end

    if isempty(Load)
        error('Nem maradt szinkronizált Load/Price nap.');
    end

    if numel(Load) ~= numel(Price)
        error('Belső hiba: Load és Price elemszám eltér.');
    end

    % =====================================================================
    % 7) Cache és log
    % =====================================================================
    cachedLoad = Load;
    cachedPrice = Price;

    fprintf('\nLoad/Price szinkronizálás kész.\n');
    fprintf('Valid load évek száma: %d\n', numel(validLoadYears));
    fprintf('Valid load napok száma price illesztés előtt: %d\n', numel(loadRaw));
    fprintf('Kihagyott napok price hiány miatt: %d\n', skippedNoPrice);
    fprintf('Végső Load/Price napok száma: %d\n', numel(Load));
    fprintf('Első nap: %s\n', datestr(Load(1).date, 'yyyy-mm-dd'));
    fprintf('Utolsó nap: %s\n', datestr(Load(end).date, 'yyyy-mm-dd'));
end


function dt = local_parse_date_string(dateString)

    if isstring(dateString)
        dateString = char(dateString);
    end

    tokens = regexp(dateString, '(\d{4})[.\-_](\d{1,2})[.\-_](\d{1,2})', ...
        'tokens', 'once');

    if isempty(tokens)
        error('Nem értelmezhető dátum string: %s', string(dateString));
    end

    y = str2double(tokens{1});
    m = str2double(tokens{2});
    d = str2double(tokens{3});

    if any(isnan([y, m, d]))
        error('Nem numerikus dátum komponens: %s', string(dateString));
    end

    dt = datetime(y, m, d);
end


function key = local_mmdd_key(m, d)

    key = sprintf('%02d-%02d', m, d);
end


function dt_h = local_dt_from_time_axis(timeMinAxis, nExpected, fileName)

    timeMinAxis = timeMinAxis(:).';

    if numel(timeMinAxis) ~= nExpected
        error('A timeMinAxis hossza nem egyezik az adatvektor hosszával, fájl: %s', ...
            fileName);
    end

    if numel(timeMinAxis) < 2
        error('A timeMinAxis túl rövid a dt_h meghatározásához, fájl: %s', ...
            fileName);
    end

    dtMin = median(diff(timeMinAxis));

    if ~isfinite(dtMin) || dtMin <= 0
        error('Érvénytelen dt perc érték, fájl: %s', fileName);
    end

    dt_h = dtMin / 60;
end