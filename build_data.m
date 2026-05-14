function data = build_data(cfg)
% BUILD_DATA
%
% Ipari PV+BESS peak shaving + energia arbitrázs + contract optimum
% feladathoz szükséges idősorok előkészítése.
%
% Kötelező kimeneti mezők:
%   data.days(d).date
%   data.days(d).P_load_kW
%   data.days(d).P_pv_A_dc_kW
%   data.days(d).P_pv_B_dc_kW
%   data.days(d).Price.buy_huf
%   data.days(d).dt_h
%
% Nincs fallback. Ha a PV/load/price adatok nem szinkronizálhatók,
% a függvény hibát dob.

    % =====================================================================
    % 1) Kötelező cfg mezők
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
    % 2) Load + price betöltése
    % =====================================================================
    % Ez a run_single_bess_contract_search logikáját követi.
    % Elvárt kimenet:
    %   Load(d).date
    %   Load(d).P_load_kW
    %   Load(d).dt_h
    %
    %   Price(d).date
    %   Price(d).buy_huf

    [Load, Price] = build_load_price_cache();

    if isempty(Load)
        error('Load cache is empty.');
    end

    if isempty(Price)
        error('Price cache is empty.');
    end

    requiredLoadFields = {'date', 'P_load_kW', 'dt_h'};

    for k = 1:numel(requiredLoadFields)
        if ~isfield(Load, requiredLoadFields{k})
            error('A Load struktúra nem tartalmazza ezt a mezőt: Load.%s', ...
                requiredLoadFields{k});
        end
    end

    requiredPriceFields = {'date', 'buy_huf'};

    for k = 1:numel(requiredPriceFields)
        if ~isfield(Price, requiredPriceFields{k})
            error('A Price struktúra nem tartalmazza ezt a mezőt: Price.%s', ...
                requiredPriceFields{k});
        end
    end

    % =====================================================================
    % 3) PV_A és PV_B konkrét teljesítményű termelés
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

    requiredPvFields = {'date', 'Ppv', 'dt_h'};

    for k = 1:numel(requiredPvFields)

        f = requiredPvFields{k};

        if ~isfield(PV_A, f)
            error('A PV_A struktúra nem tartalmazza ezt a mezőt: PV_A.%s', f);
        end

        if ~isfield(PV_B, f)
            error('A PV_B struktúra nem tartalmazza ezt a mezőt: PV_B.%s', f);
        end
    end

    % =====================================================================
    % 4) Dátum szerinti szinkronizálás
    % =====================================================================
    loadDates = [Load.date].';
    priceDates = [Price.date].';
    pvADates = [PV_A.date].';
    pvBDates = [PV_B.date].';

    [commonDates, idxLoad, idxPrice] = intersect(loadDates, priceDates);
    [commonDates, idxCommon, idxPVA] = intersect(commonDates, pvADates);

    idxLoad = idxLoad(idxCommon);
    idxPrice = idxPrice(idxCommon);

    [commonDates, idxCommon, idxPVB] = intersect(commonDates, pvBDates);

    idxLoad = idxLoad(idxCommon);
    idxPrice = idxPrice(idxCommon);
    idxPVA = idxPVA(idxCommon);

    if isempty(commonDates)
        error('No common dates found between Load, Price, PV_A and PV_B.');
    end

    nDays = numel(commonDates);

    fprintf('\nSynchronization by exact dates:\n');
    fprintf('  Load days:   %d\n', numel(Load));
    fprintf('  Price days:  %d\n', numel(Price));
    fprintf('  PV_A days:   %d\n', numel(PV_A));
    fprintf('  PV_B days:   %d\n', numel(PV_B));
    fprintf('  Common days: %d\n', nDays);
    fprintf('  First common date: %s\n', datestr(commonDates(1), 'yyyy-mm-dd'));
    fprintf('  Last common date:  %s\n', datestr(commonDates(end), 'yyyy-mm-dd'));

    % =====================================================================
    % 5) Napi struktúrák feltöltése
    % =====================================================================
    emptyDay = struct( ...
        'date', NaT, ...
        'P_load_kW', [], ...
        'P_pv_A_dc_kW', [], ...
        'P_pv_B_dc_kW', [], ...
        'Price', struct('buy_huf', []), ...
        'dt_h', []);

    data = struct();
    data.days = repmat(emptyDay, 1, nDays);

    for d = 1:nDays

        L = Load(idxLoad(d));
        PA = PV_A(idxPVA(d));
        PB = PV_B(idxPVB(d));
        PR = Price(idxPrice(d));

        P_load_kW = cfg.loadScale .* L.P_load_kW(:).';

        P_pv_A_dc_kW = PA.Ppv(:).' / 1000;
        P_pv_B_dc_kW = PB.Ppv(:).' / 1000;

        dt_load_h = L.dt_h;
        dt_pv_A_h = PA.dt_h;
        dt_pv_B_h = PB.dt_h;

        if abs(dt_pv_A_h - dt_load_h) > 1e-12
            P_pv_A_dc_kW = local_resample_power_to_target_dt( ...
                P_pv_A_dc_kW, ...
                dt_pv_A_h, ...
                dt_load_h);
        end

        if abs(dt_pv_B_h - dt_load_h) > 1e-12
            P_pv_B_dc_kW = local_resample_power_to_target_dt( ...
                P_pv_B_dc_kW, ...
                dt_pv_B_h, ...
                dt_load_h);
        end

        buy_huf = PR.buy_huf(:).';

        if numel(P_pv_A_dc_kW) ~= numel(P_load_kW)
            error('PV_A és load vektorhossz eltérés dátumnál: %s', ...
                datestr(commonDates(d), 'yyyy-mm-dd'));
        end

        if numel(P_pv_B_dc_kW) ~= numel(P_load_kW)
            error('PV_B és load vektorhossz eltérés dátumnál: %s', ...
                datestr(commonDates(d), 'yyyy-mm-dd'));
        end

        if numel(buy_huf) ~= numel(P_load_kW)
            error('Price és load vektorhossz eltérés dátumnál: %s', ...
                datestr(commonDates(d), 'yyyy-mm-dd'));
        end

        data.days(d).date = commonDates(d);
        data.days(d).P_load_kW = P_load_kW;
        data.days(d).P_pv_A_dc_kW = P_pv_A_dc_kW;
        data.days(d).P_pv_B_dc_kW = P_pv_B_dc_kW;
        data.days(d).Price.buy_huf = buy_huf;
        data.days(d).dt_h = dt_load_h;
    end

    % =====================================================================
    % 6) Info
    % =====================================================================
    data.info = struct();

    data.info.createdAt = datetime('now');
    data.info.nDays = nDays;
    data.info.dt_h = data.days(1).dt_h;
    data.info.nT = numel(data.days(1).P_load_kW);

    data.info.loadScale = cfg.loadScale;

    data.info.firstDate = commonDates(1);
    data.info.lastDate = commonDates(end);

    data.info.rawLoadDays = numel(Load);
    data.info.rawPriceDays = numel(Price);
    data.info.rawPvADays = numel(PV_A);
    data.info.rawPvBDays = numel(PV_B);
    data.info.commonDays = nDays;

    data.info.P_pv_A_dc_kWp = sum(cfg.pvA.P_dc_kWp);
    data.info.P_pv_B_dc_kWp = sum(cfg.pvB.P_dc_kWp);
    data.info.P_pv_total_dc_kWp = ...
        data.info.P_pv_A_dc_kWp + data.info.P_pv_B_dc_kWp;

    fprintf('\nIndustrial time series synchronized.\n');
    fprintf('Days: %d\n', data.info.nDays);
    fprintf('Steps per day: %d\n', data.info.nT);
    fprintf('dt_h: %.6f h\n', data.info.dt_h);
    fprintf('PV_A: %.3f kWp\n', data.info.P_pv_A_dc_kWp);
    fprintf('PV_B: %.3f kWp\n', data.info.P_pv_B_dc_kWp);
    fprintf('PV total: %.3f kWp\n', data.info.P_pv_total_dc_kWp);
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