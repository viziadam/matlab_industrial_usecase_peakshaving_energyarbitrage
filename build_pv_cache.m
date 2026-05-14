function PV = build_pv_cache(tiltX, tiltZ, Pdc_kWp, Ppan_kWp)
% BUILD_PV_CACHE
%
% PV adatok betöltése a production mappából.
%
% Fontos működés:
%   - Nem követeli meg a pontos 365 napos éveket.
%   - Csak olyan éveket tart meg, ahol legalább 350 nem-szökőnapi adat van.
%   - Feb 29 kimarad.
%   - A kimenet tartalmaz date/year/month/day/mmddKey mezőket.
%
% Kimenet:
%   PV(i).date
%   PV(i).year
%   PV(i).month
%   PV(i).day
%   PV(i).mmddKey
%   PV(i).Ppv
%   PV(i).timeMinVec
%   PV(i).dt_h
%   PV(i).timeDay

    persistent PV_MAP

    minDaysPerYear = 350;

    if isempty(PV_MAP)
        PV_MAP = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end

    cacheKey = sprintf('X%s_Z%s_P%s', ...
        mat2str(tiltX), ...
        mat2str(tiltZ), ...
        mat2str(Pdc_kWp));

    if PV_MAP.isKey(cacheKey)
        fprintf('PV adatok betöltve a memóriából: %s\n', cacheKey);
        PV = PV_MAP(cacheKey);
        return;
    end

    fprintf('PV adatok beolvasása a fájlokból: %s\n', cacheKey);

    thisDir = fileparts(mfilename('fullpath'));
    pvDir = fullfile(thisDir, 'production');

    files = dir(fullfile(pvDir, '*.mat'));

    if isempty(files)
        error('Nem találhatók .mat fájlok a production mappában: %s', pvDir);
    end

    rawPV = struct( ...
        'date', {}, ...
        'year', {}, ...
        'month', {}, ...
        'day', {}, ...
        'mmddKey', {}, ...
        'Ppv', {}, ...
        'timeMinVec', {}, ...
        'dt_h', {}, ...
        'timeDay', {}, ...
        'fileName', {});

    for k = 1:numel(files)

        filePath = fullfile(pvDir, files(k).name);
        S = load(filePath);

        if ~isfield(S, 'resultBuffer')
            error('A PV fájl nem tartalmaz resultBuffer változót: %s', files(k).name);
        end

        rb = S.resultBuffer;

        requiredFields = {'timeDay', 'timeVectorMin', 'timeStepMin', 'results'};

        for f = 1:numel(requiredFields)
            if ~isfield(rb, requiredFields{f})
                error('A resultBuffer nem tartalmazza ezt a mezőt: %s, fájl: %s', ...
                    requiredFields{f}, files(k).name);
            end
        end

        dt = local_parse_date_string(rb.timeDay);

        if month(dt) == 2 && day(dt) == 29
            continue;
        end

        timeMinVec = rb.timeVectorMin(:).';
        resTable = rb.results;

        requiredTableVars = {'tiltX', 'tiltZ', 'tPDC'};

        for f = 1:numel(requiredTableVars)
            if ~ismember(requiredTableVars{f}, resTable.Properties.VariableNames)
                error('A PV results table nem tartalmazza ezt az oszlopot: %s, fájl: %s', ...
                    requiredTableVars{f}, files(k).name);
            end
        end

        Ppv_total = zeros(1, numel(timeMinVec));

        for c = 1:numel(tiltZ)

            if isscalar(tiltX)
                cX = tiltX;
            else
                cX = tiltX(c);
            end

            cZ = tiltZ(c);
            cPower = Pdc_kWp(c);

            rowIdx = find(resTable.tiltX == cX & resTable.tiltZ == cZ, 1);

            if isempty(rowIdx)
                error('Nem található PV sor: tiltX=%g, tiltZ=%g, fájl: %s', ...
                    cX, cZ, files(k).name);
            end

            if iscell(resTable.tPDC)
                tPDC_raw = resTable.tPDC{rowIdx};
            else
                tPDC_raw = resTable.tPDC(rowIdx, :);
            end

            tPDC_raw = tPDC_raw(:).';

            if numel(tPDC_raw) ~= numel(timeMinVec)
                error('A tPDC és timeVectorMin hossza eltér, fájl: %s', files(k).name);
            end

            Ppv_total = Ppv_total + (tPDC_raw .* cPower / Ppan_kWp);
        end

        item = struct();

        item.date = dt;
        item.year = year(dt);
        item.month = month(dt);
        item.day = day(dt);
        item.mmddKey = local_mmdd_key(item.month, item.day);
        item.Ppv = Ppv_total;
        item.timeMinVec = timeMinVec;
        item.dt_h = rb.timeStepMin / 60;
        item.timeDay = rb.timeDay;
        item.fileName = string(files(k).name);

        rawPV(end+1) = item; %#ok<AGROW>
    end

    if isempty(rawPV)
        error('Nem maradt beolvasható PV nap.');
    end

    % =====================================================================
    % Évek szűrése legalább 350 nap alapján
    % =====================================================================
    yearsPV = unique([rawPV.year]);

    validYears = [];

    for i = 1:numel(yearsPV)

        y = yearsPV(i);
        nDaysY = sum([rawPV.year] == y);

        if nDaysY >= minDaysPerYear
            validYears(end+1) = y; %#ok<AGROW>
        else
            fprintf('PV év kihagyva: %d, csak %d nap áll rendelkezésre.\n', ...
                y, nDaysY);
        end
    end

    if isempty(validYears)
        error('Nincs olyan PV év, ahol legalább %d nap rendelkezésre áll.', ...
            minDaysPerYear);
    end

    keep = ismember([rawPV.year], validYears);
    PV = rawPV(keep);

    [~, order] = sort([PV.date]);
    PV = PV(order);

    fprintf('PV szűrés kész: %d valid év, %d nap kerül a memóriába.\n', ...
        numel(validYears), numel(PV));

    PV_MAP(cacheKey) = PV;
end


function dt = local_parse_date_string(dateString)

    if isstring(dateString)
        dateString = char(dateString);
    end

    tokens = regexp(dateString, '(\d{4})[.\-_](\d{1,2})[.\-_](\d{1,2})', ...
        'tokens', 'once');

    if isempty(tokens)
        error('Nem értelmezhető PV dátum string: %s', string(dateString));
    end

    y = str2double(tokens{1});
    m = str2double(tokens{2});
    d = str2double(tokens{3});

    if any(isnan([y, m, d]))
        error('Nem numerikus PV dátum komponens: %s', string(dateString));
    end

    dt = datetime(y, m, d);
end


function key = local_mmdd_key(m, d)

    key = sprintf('%02d-%02d', m, d);
end