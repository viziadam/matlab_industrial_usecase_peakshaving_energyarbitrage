function plot_results2_heatmap(folderPath)
% PLOT_RESULTS2_HEATMAP - Geometriai hőtérkép a konzulens adatain 
% lefutott saját modell (results2) alapján.

    P_stc = 715; % A modul STC teljesítménye [W]

    % --- 1. Mappa és fájlok beolvasása ---
    if nargin < 1 || isempty(folderPath)
        folderPath = uigetdir('', 'Válaszd ki a konzulens .mat fájljainak mappáját');
        if folderPath == 0, return; end
    end

    files = dir(fullfile(folderPath, '*.mat'));
    if isempty(files)
        warning('Nincs .mat fájl a megadott mappában!'); 
        return; 
    end

    fprintf('Adatok beolvasása és validálása...\n');

    % --- 2. Orientációk kinyerése az első érvényes fájlból ---
    firstValidIdx = 0;
    for i = 1:length(files)
        try
            % Csak a resultBuffer-t töltjük be a memóriaspórolás miatt
            data = load(fullfile(folderPath, files(i).name), 'resultBuffer');
            if isfield(data.resultBuffer, 'results2')
                firstValidIdx = i;
                break;
            end
        catch
            % Ha hibás a fájl, megyünk tovább
        end
    end

    if firstValidIdx == 0
        error('Egyetlen fájlban sem található a "results2" tábla! Futtasd le előbb a validate_against_consultant függvényt.');
    end

    % Dőlésszögek és tájolások kinyerése
    data1 = load(fullfile(folderPath, files(firstValidIdx).name), 'resultBuffer');
    res2 = data1.resultBuffer.results2;
    tiltsX = unique(res2.tiltX);
    tiltsZ = unique(res2.tiltZ);
    nX = length(tiltsX);
    nZ = length(tiltsZ);

    totalEnergyWh = zeros(nX, nZ);
    validDaysCount = 0;

    % --- 3. Adatok akkumulálása ---
    for i = 1:length(files)
        try
            data = load(fullfile(folderPath, files(i).name), 'resultBuffer');
            rb = data.resultBuffer;
            
            % Ha ebben a napban nincs results2, kihagyjuk
            if ~isfield(rb, 'results2')
                continue; 
            end
            
            % Időlépés kinyerése (percben) az integráláshoz
            if isfield(rb, 'timeStepMin')
                dt_min = rb.timeStepMin;
            else
                dt_min = 5; % Biztonsági alapérték, ha hiányozna
            end
            
            res = rb.results2;
            
            for r = 1:height(res)
                tx = res.tiltX(r);
                tz = res.tiltZ(r);
                ix = find(tiltsX == tx);
                iz = find(tiltsZ == tz);
                
                % Teljesítmény vektor (W) -> Napi Energia (Wh)
                pdc_vec = res.tPDC{r};
                dailyEnergyWh = sum(pdc_vec) * (dt_min / 60);
                
                totalEnergyWh(ix, iz) = totalEnergyWh(ix, iz) + dailyEnergyWh;
            end
            validDaysCount = validDaysCount + 1;
            
        catch
            % Hibás nap átugrása
        end
    end

    if validDaysCount == 0
        error('Nem sikerült érvényes napokat feldolgozni!');
    end

    % --- 4. Számítás: Átlagos éves termelés [óra] ---
    % Napi átlag [Wh/nap] (kompenzálja a hiányzó napokat)
    avgDailyEnergyWh = totalEnergyWh / validDaysCount;
    
    % Felszorozzuk 365-tel az éves [Wh/év] értékhez
    avgAnnualEnergyWh = avgDailyEnergyWh * 365;
    
    % Osztjuk a modul STC teljesítményével -> Ekvivalens csúcsórák [h/év]
    specificYieldHours = avgAnnualEnergyWh / P_stc;

    % --- 5. Hőtérkép megrajzolása ---
    figure('Name', 'Saját Modell a Konzulens Adatain (results2)', 'Position', [200, 200, 800, 600]);
    
    xLabels = cellstr(num2str(tiltsZ(:), '%d°'));
    yLabels = cellstr(num2str(tiltsX(:), '%d°'));
    
    % Iránytű szövegek
    dirNames = containers.Map({0, 90, 180, 270}, {' (Észak)', ' (Kelet)', ' (Dél)', ' (Nyugat)'});
    for i = 1:length(tiltsZ)
        if isKey(dirNames, tiltsZ(i))
            xLabels{i} = [xLabels{i}, dirNames(tiltsZ(i))];
        end
    end

    % Heatmap objektum
    h = heatmap(xLabels, yLabels, specificYieldHours);
    
    h.Title = sprintf('Saját Modell Éves Termelése (results2)\n(%d validált nap alapján, %dW STC modulra)', validDaysCount, P_stc);
    h.XLabel = 'Tájolás (Azimut, tiltZ)';
    h.YLabel = 'Dőlésszög (tiltX)';
    h.Colormap = turbo;
    h.CellLabelFormat = '%.0f h';
    
    % 0 fokos dőlés legyen alul
    h.YDisplayData = flipud(h.YDisplayData);

    fprintf('Feldolgozva: %d nap. A hőtérkép sikeresen elkészült!\n', validDaysCount);
end