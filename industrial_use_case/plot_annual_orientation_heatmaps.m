function plot_annual_orientation_heatmaps(folderPath)
% PLOT_ANNUAL_YIELD_HEATMAP - Geometriai hőtérkép a specifikus hozamról
% X tengely: tiltZ (Tájolás)
% Y tengely: tiltX (Dőlésszög)
% Érték: Átlagos éves termelés órában kifejezve (Ekvivalens csúcsórák)

    P_stc = 715; % A modul STC teljesítménye [W]

    % --- 1. Fájlok beolvasása ---
    if nargin < 1 || isempty(folderPath)
        folderPath = uigetdir('', 'Válaszd ki a napi .mat fájlok mappáját');
        if folderPath == 0, return; end
    end

    files = dir(fullfile(folderPath, 'resultBuffer_ORIG_*.mat'));
    if isempty(files)
        warning('Nincs megfelelő fájl a megadott mappában!'); 
        return; 
    end

    % Dátumok kinyerése a fájlnevekből
    numFiles = length(files);
    fileDates = NaT(numFiles, 1);
    for i = 1:numFiles
        tok = regexp(files(i).name, 'ORIG_(\d{4})_(\d{2})_(\d{2})', 'tokens', 'once');
        if ~isempty(tok)
            fileDates(i) = datetime(str2double(tok{1}), str2double(tok{2}), str2double(tok{3}));
        end
    end
    
    yVec = year(fileDates);
    years = unique(yVec);
    nY = length(years);

    % --- 2. Csonka évek szűrése (>350 nap) ---
    validYearsMask = false(nY, 1);
    for i = 1:nY
        if sum(yVec == years(i)) >= 350 
            validYearsMask(i) = true;
        end
    end
    
    validYears = years(validYearsMask);
    if isempty(validYears)
        error('Nincs elegendő adat egyetlen teljes évhez sem (>350 nap)!');
    end

    % --- 3. Orientációk kinyerése az első valid fájlból ---
    firstValidIdx = find(ismember(yVec, validYears), 1);
    data1 = load(fullfile(folderPath, files(firstValidIdx).name), 'resultBuffer');
    res1 = data1.resultBuffer.results;
    
    tiltsX = unique(res1.tiltX); % Dőlésszögek (Y tengely)
    tiltsZ = unique(res1.tiltZ); % Tájolások (X tengely)
    nX = length(tiltsX);
    nZ = length(tiltsZ);

    % Adatgyűjtő mátrix: összes megtermelt energia [Wh]
    totalEnergyWh = zeros(nX, nZ);
    validDaysCount = 0;

    fprintf('Adatok összegzése %d teljes évre...\n', length(validYears));

    % --- 4. Adatok akkumulálása ---
    for i = 1:numFiles
        if ~ismember(yVec(i), validYears)
            continue; % Csak a teljes éveket dolgozzuk fel
        end
        
        data = load(fullfile(folderPath, files(i).name), 'resultBuffer');
        res = data.resultBuffer.results;
        
        for r = 1:height(res)
            tx = res.tiltX(r);
            tz = res.tiltZ(r);
            ix = find(tiltsX == tx);
            iz = find(tiltsZ == tz);
            
            % Napi energia [Wh] = Teljesítmény [W] * 5 perc / 60 perc
            dailyEnergyWh = sum(res.tPDC{r}) * (5/60);
            
            totalEnergyWh(ix, iz) = totalEnergyWh(ix, iz) + dailyEnergyWh;
        end
        validDaysCount = validDaysCount + 1;
    end

    % --- 5. Számítás: Átlagos éves termelés [óra] ---
    % 1. Kiszámoljuk a napi átlagot [Wh/nap] (ez kompenzálja a hiányzó napokat)
    avgDailyEnergyWh = totalEnergyWh / validDaysCount;
    
    % 2. Felszorozzuk 365-tel az éves [Wh/év] értékhez
    avgAnnualEnergyWh = avgDailyEnergyWh * 365;
    
    % 3. Osztjuk a modul STC teljesítményével -> Ekvivalens csúcsórák [h/év]
    % Ez pontosan megegyezik a fajlagos hozammal (kWh/kWp)
    specificYieldHours = avgAnnualEnergyWh / P_stc;

    % --- 6. Hőtérkép megrajzolása ---
    figure('Name', 'Orientációs Hőtérkép (Specifikus Hozam)', 'Position', [200, 200, 800, 600]);
    
    % Címkék generálása a tengelyekhez
    xLabels = cellstr(num2str(tiltsZ(:), '%d°'));
    yLabels = cellstr(num2str(tiltsX(:), '%d°'));
    
    % Iránytű szövegek hozzáadása az X tengelyhez a könnyebb érthetőségért
    dirNames = containers.Map({0, 90, 180, 270}, {' (Észak)', ' (Kelet)', ' (Dél)', ' (Nyugat)'});
    for i = 1:length(tiltsZ)
        if isKey(dirNames, tiltsZ(i))
            xLabels{i} = [xLabels{i}, dirNames(tiltsZ(i))];
        end
    end

    % MATLAB Heatmap objektum létrehozása
    h = heatmap(xLabels, yLabels, specificYieldHours);
    
    % Hőtérkép formázása
    h.Title = sprintf('Átlagos Éves Termelés Orientációnként\n(%d év átlaga, %dW STC modulra vetítve)', length(validYears), P_stc);
    h.XLabel = 'Tájolás (Azimut, tiltZ)';
    h.YLabel = 'Dőlésszög (tiltX)';
    h.Colormap = turbo; % Szép átmenetes színskála
    h.CellLabelFormat = '%.0f h'; % Egész órákra kerekített értékek megjelenítése a cellákban
    
    % Tengelyek megfordítása, hogy a 0 fokos dőlés legyen alul (opcionális, de megszokott)
    h.YDisplayData = flipud(h.YDisplayData);

    fprintf('A hőtérkép elkészült!\n');
end