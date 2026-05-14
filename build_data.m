function data = build_data(cfg)
% BUILD_DATA
%
% Ipari PV+BESS peak shaving + energia arbitrázs + contract optimum
% feladathoz szükséges idősorok előkészítése.
%
% Működés:
%   - Load és Price a build_load_price_cache() kimenetéből jön.
%   - Price már month-day alapon van a load napokra illesztve.
%   - PV_A és PV_B külön build_pv_cache() hívással jön.
%   - PV illesztés nem azonos év alapján történik, hanem hónap-nap alapján.
%   - Load évekhez PV éveket rendelünk ciklikusan.
%   - Ha adott load naphoz nincs PV_A/PV_B a hozzárendelt PV évben,
%     akkor az a nap kimarad.
%
% Kimenet:
%   data.days(d).date
%   data.days(d).P_load_kW
%   data.days(d).P_pv_A_dc_kW
%   data.days(d).P_pv_B_dc_kW
%   data.days(d).Price.buy_huf
%   data.days(d).Price.sell_huf
%   data.days(d).dt_h

    % =====================================================================
    % 1) Kötelező cfg mezők ellenőrzése
    % =====================================================================
    requiredTopFields = {'pvA', 'pvB', 'pv', 'loadScale'};

    for k = 1:numel(requiredTopFields)
        if ~isfield(cfg, requiredTopFields{k})
            error('Hiányzó cfg mező: cfg.%s', requiredTopFields{k});
        end
    end

    requiredPvGroupFields = {'tiltX', 'tiltZ', 'P_dc_kWp'};

    for k = 1:numel(requiredPvGroupFields)

        f = requiredPvGroupFields{k};

        if ~isfield(cfg.pvA, f)
            error('Hiányzó cfg mező: cfg.pvA.%s', f);
        end

        if ~isfield(cfg.pvB, f)
            error('Hiányzó cfg mező: cfg.pvB.%s', f);
        end
    end

    if ~isfield(cfg.pv, 'modulePower_kWp')
        error('Hiányzó cfg mező: cfg.pv.modulePower_kWp');
    end

    if ~isnumeric(cfg.loadScale) || ~isscalar(cfg.loadScale) || ...
       ~isfinite(cfg.loadScale) || cfg.loadScale <= 0
        error('cfg.loadScale must be a positive finite scalar.');
    end

    fprintf('Load scale factor: %.4f\n', cfg.loadScale);

    % =====================================================================
    % 2) Load + Price betöltése
    % =====================================================================
    [Load, Price] = build_load_price_cache();

    if isempty(Load)
        error('Load cache is empty.');
    end

    if isempty(Price)
        error('Price cache is empty.');
    end

    if numel(Load) ~= numel(Price)
        error('Load és Price elemszáma eltér.');
    end

    requiredLoadFields = {'date', 'year', 'month', 'day', 'mmddKey', 'P_load_kW', 'dt_h'};

    for f = 1:numel(requiredLoadFields)
        if ~isfield(Load, requiredLoadFields{f})
            error('A Load struktúra nem tartalmazza ezt a mezőt: Load.%s', ...
                requiredLoadFields{f});
        end
    end

    requiredPriceFields = {'date', 'sourceDate', 'mmddKey', 'buy_huf', 'sell_huf', 'dt_h'};

    for f = 1:numel(requiredPriceFields)
        if ~isfield(Price, requiredPriceFields{f})
            error('A Price struktúra nem tartalmazza ezt a mezőt: Price.%s', ...
                requiredPriceFields{f});
        end
    end

    % =====================================================================
    % 3) PV_A és PV_B betöltése
    % =====================================================================
    PV_A = build_pv_cache( ...
        cfg.pvA.tiltX, ...
        cfg.pvA.tiltZ, ...
        cfg.pvA.P_dc_kWp, ...
        cfg.pv.modulePower_kWp);

    PV_B = build_pv_cache( ...
        cfg.pvB.tiltX, ...
        cfg.pvB.tiltZ, ...
        cfg.pvB.P_dc_kWp, ...
        cfg.pv.modulePower_kWp);

    if isempty(PV_A)
        error('PV_A cache is empty.');
    end

    if isempty(PV_B)
        error('PV_B cache is empty.');
    end

    requiredPVFields = {'date', 'year', 'month', 'day', 'mmddKey', 'Ppv', 'dt_h'};

    for f = 1:numel(requiredPVFields)

        fieldName = requiredPVFields{f};

        if ~isfield(PV_A, fieldName)
            error('A PV_A struktúra nem tartalmazza ezt a mezőt: PV_A.%s', fieldName);
        end

        if ~isfield(PV_B, fieldName)
            error('A PV_B struktúra nem tartalmazza ezt a mezőt: PV_B.%s', fieldName);
        end
    end

    % =====================================================================
    % 4) PV évek kiválasztása
    % =====================================================================
    pvYearsA = unique([PV_A.year]);
    pvYearsB = unique([PV_B.year]);

    pvYears = intersect(pvYearsA, pvYearsB);

    if isempty(pvYears)
        error('Nincs közös PV év PV_A és PV_B között.');
    end

    pvYears = sort(pvYears);

    fprintf('\nPV évek, amelyekből month-day sablon használható:\n');
    disp(pvYears);

    % =====================================================================
    % 5) PV index map építése year + month-day alapján
    % =====================================================================
    pvAMap = local_build_pv_year_mmdd_map(PV_A, 'PV_A');
    pvBMap = local_build_pv_year_mmdd_map(PV_B, 'PV_B');

    % =====================================================================
    % 6) Load évekhez PV évek rendelése ciklikusan
    % =====================================================================
    loadYears = unique([Load.year]);
    loadYears = sort(loadYears);

    yearMap = containers.Map('KeyType', 'double', 'ValueType', 'double');

    for i = 1:numel(loadYears)

        pvYearIdx = mod(i - 1, numel(pvYears)) + 1;
        yearMap(loadYears(i)) = pvYears(pvYearIdx);

        fprintf('Load év %d -> PV év %d\n', loadYears(i), pvYears(pvYearIdx));
    end

    % =====================================================================
    % 7) Napi data.days felépítése
    % =====================================================================
    emptyDay = struct( ...
        'date', NaT, ...
        'loadYear', [], ...
        'pvSourceYear', [], ...
        'pvSourceDateA', NaT, ...
        'pvSourceDateB', NaT, ...
        'priceSourceDate', NaT, ...
        'P_load_kW', [], ...
        'P_pv_A_dc_kW', [], ...
        'P_pv_B_dc_kW', [], ...
        'Price', struct('buy_huf', [], 'sell_huf', []), ...
        'dt_h', []);

    data = struct();
    data.days = repmat(emptyDay, 1, numel(Load));

    outIdx = 0;
    skippedMissingPV = 0;
    skippedVectorMismatch = 0;

    for i = 1:numel(Load)

        if Load(i).date ~= Price(i).date
            error('Load és Price dátum eltér az indexnél: %d', i);
        end

        if Load(i).mmddKey ~= Price(i).mmddKey
            error('Load és Price mmddKey eltér az indexnél: %d', i);
        end

        loadYear = Load(i).year;
        pvYear = yearMap(loadYear);

        pvKey = local_year_mmdd_key(pvYear, Load(i).mmddKey);

        if ~pvAMap.isKey(pvKey) || ~pvBMap.isKey(pvKey)
            skippedMissingPV = skippedMissingPV + 1;
            continue;
        end

        idxA = pvAMap(pvKey);
        idxB = pvBMap(pvKey);

        PA = PV_A(idxA);
        PB = PV_B(idxB);

        P_load_kW = cfg.loadScale .* Load(i).P_load_kW(:).';

        P_pv_A_dc_kW = PA.Ppv(:).' / 1000;
        P_pv_B_dc_kW = PB.Ppv(:).' / 1000;

        buy_huf = Price(i).buy_huf(:).';
        sell_huf = Price(i).sell_huf(:).';

        dt_load_h = Load(i).dt_h;

        if abs(Price(i).dt_h - dt_load_h) > 1e-12
            error('Load és Price dt_h eltér. Load date: %s', ...
                datestr(Load(i).date, 'yyyy-mm-dd'));
        end

        if abs(PA.dt_h - dt_load_h) > 1e-12
            P_pv_A_dc_kW = local_resample_power_to_target_dt( ...
                P_pv_A_dc_kW, PA.dt_h, dt_load_h);
        end

        if abs(PB.dt_h - dt_load_h) > 1e-12
            P_pv_B_dc_kW = local_resample_power_to_target_dt( ...
                P_pv_B_dc_kW, PB.dt_h, dt_load_h);
        end

        nT = numel(P_load_kW);

        if numel(P_pv_A_dc_kW) ~= nT || ...
           numel(P_pv_B_dc_kW) ~= nT || ...
           numel(buy_huf) ~= nT || ...
           numel(sell_huf) ~= nT

            skippedVectorMismatch = skippedVectorMismatch + 1;
            continue;
        end

        outIdx = outIdx + 1;

        data.days(outIdx).date = Load(i).date;
        data.days(outIdx).loadYear = loadYear;
        data.days(outIdx).pvSourceYear = pvYear;
        data.days(outIdx).pvSourceDateA = PA.date;
        data.days(outIdx).pvSourceDateB = PB.date;
        data.days(outIdx).priceSourceDate = Price(i).sourceDate;

        data.days(outIdx).P_load_kW = P_load_kW;
        data.days(outIdx).P_pv_A_dc_kW = P_pv_A_dc_kW;
        data.days(outIdx).P_pv_B_dc_kW = P_pv_B_dc_kW;

        data.days(outIdx).Price.buy_huf = buy_huf;
        data.days(outIdx).Price.sell_huf = sell_huf;

        data.days(outIdx).dt_h = dt_load_h;
    end

    if outIdx == 0
        error('Nem maradt egyetlen szinkronizált nap sem Load/Price/PV illesztés után.');
    end

    data.days = data.days(1:outIdx);

    % =====================================================================
    % 8) Info
    % =====================================================================
    data.info = struct();

    data.info.createdAt = datetime('now');
    data.info.nDays = numel(data.days);
    data.info.dt_h = data.days(1).dt_h;
    data.info.nT = numel(data.days(1).P_load_kW);

    data.info.loadScale = cfg.loadScale;

    data.info.firstDate = data.days(1).date;
    data.info.lastDate = data.days(end).date;

    data.info.rawLoadPriceDays = numel(Load);
    data.info.rawPvADays = numel(PV_A);
    data.info.rawPvBDays = numel(PV_B);

    data.info.skippedMissingPV = skippedMissingPV;
    data.info.skippedVectorMismatch = skippedVectorMismatch;

    data.info.loadYears = loadYears;
    data.info.pvYears = pvYears;

    data.info.P_pv_A_dc_kWp = sum(cfg.pvA.P_dc_kWp);
    data.info.P_pv_B_dc_kWp = sum(cfg.pvB.P_dc_kWp);
    data.info.P_pv_total_dc_kWp = ...
        data.info.P_pv_A_dc_kWp + data.info.P_pv_B_dc_kWp;

    fprintf('\nIndustrial time series synchronized.\n');
    fprintf('Final simulation days: %d\n', data.info.nDays);
    fprintf('Steps per day: %d\n', data.info.nT);
    fprintf('dt_h: %.6f h\n', data.info.dt_h);
    fprintf('Skipped days due to missing PV month-day: %d\n', skippedMissingPV);
    fprintf('Skipped days due to vector mismatch: %d\n', skippedVectorMismatch);
    fprintf('PV_A: %.3f kWp\n', data.info.P_pv_A_dc_kWp);
    fprintf('PV_B: %.3f kWp\n', data.info.P_pv_B_dc_kWp);
    fprintf('PV total: %.3f kWp\n', data.info.P_pv_total_dc_kWp);
end


function pvMap = local_build_pv_year_mmdd_map(PV, label)

    pvMap = containers.Map('KeyType', 'char', 'ValueType', 'double');

    for i = 1:numel(PV)

        key = local_year_mmdd_key(PV(i).year, PV(i).mmddKey);

        if pvMap.isKey(key)
            error('%s duplikált year-mmdd kulcs: %s', label, key);
        end

        pvMap(key) = i;
    end
end


function key = local_year_mmdd_key(y, mmddKey)

    key = sprintf('%04d-%s', y, char(mmddKey));
end


function y = local_resample_power_to_target_dt(x, dt_in_h, dt_out_h)

    x = x(:).';

    if abs(dt_in_h - dt_out_h) < 1e-12
        y = x;
        return;
    end

    if dt_out_h > dt_in_h

        factorReal = dt_out_h / dt_in_h;
        factor = round(factorReal);

        if abs(factorReal - factor) > 1e-9
            error('Target dt_h must be an integer multiple of input dt_h.');
        end

        nBlocks = floor(numel(x) / factor);

        if nBlocks < 1
            error('Not enough samples for resampling.');
        end

        nUse = nBlocks * factor;

        xUse = x(1:nUse);
        xMat = reshape(xUse, factor, nBlocks);

        y = mean(xMat, 1);

    else

        factorReal = dt_in_h / dt_out_h;
        factor = round(factorReal);

        if abs(factorReal - factor) > 1e-9
            error('Input dt_h must be an integer multiple of target dt_h.');
        end

        y = repelem(x, factor);
    end
end