function avg_power_kW = calculate_average_daily_profile(folderPath)
% CALCULATE_AVERAGE_DAILY_PROFILE - Átlagos napi fogyasztási profil (24h)
% Bemenet: A napi fogyasztási .mat fájlokat tartalmazó mappa
% Kimenet: 1x288-as vektor, az átlagos nap 5 perces értékeivel (kW)

    % Fájlok listázása a mappából
    files = dir(fullfile(folderPath, '*.mat'));
    numFiles = length(files);
    
    % Vektor előkészítése az összegzéshez (1x288 adatpont a 24 órára)
    sum_power_W = zeros(1, 288);
    validDays = 0;

    fprintf('Adatok beolvasása és összegzése %d fájlból...\n', numFiles);

    % Végigmegyünk az összes fájlon
    for i = 1:numFiles
        filePath = fullfile(folderPath, files(i).name);
        data = load(filePath);
        
        % Mivel tudjuk, hogy ezek a consumption fájlok, egyenesen kinyerjük az adatot
        if isfield(data, 'consumptionCache')
            % Biztosítjuk, hogy sorvektor legyen (1x288)
            dailyPower = data.consumptionCache.powerTotal_W(:)'; 
            
            if length(dailyPower) == 288
                sum_power_W = sum_power_W + dailyPower;
                validDays = validDays + 1;
            end
        end
    end

    % --- Átlag kiszámítása ---
    % Elosztjuk az összegzett wattokat a napok számával, és átváltjuk kW-ra
    avg_power_W = sum_power_W / validDays;
    avg_power_kW = avg_power_W / 1000;

    % Eredmények kiíratása a Parancsablakba
    fprintf('============================================\n');
    fprintf('Feldolgozott napok száma: %d\n', validDays);
    fprintf('Átlagos éjszakai/alap fogyasztás (Min): %.2f kW\n', min(avg_power_kW));
    fprintf('Átlagos napi csúcsfogyasztás (Max): %.2f kW\n', max(avg_power_kW));
    fprintf('============================================\n');

    % --- Ábrázolás (A 24 órás profil) ---
    % Létrehozzuk az X tengelyt órákban (0-tól 23.9-ig, 5 perces lépésközökkel)
    time_hours = (0:5:1435) / 60; 

    figure('Name', 'Átlagos Napi Fogyasztási Profil', 'Position', [200, 200, 900, 500]);
    
    % Alatti terület színezése a látványosabb grafikonért
    fill([time_hours, fliplr(time_hours)], [avg_power_kW, zeros(1, 288)], ...
         [0.2 0.4 0.8], 'FaceAlpha', 0.2, 'EdgeColor', 'none');
    hold on;
    grid on;
    
    % Maga a vonal vastagon
    plot(time_hours, avg_power_kW, 'b-', 'LineWidth', 2.5);
    
    % Vizuális finomhangolás
    title('A Gyár Átlagos Napi Fogyasztási Profilja (24 óra)', 'FontSize', 12, 'FontWeight', 'bold');
    xlabel('A nap órái [h]', 'FontSize', 11);
    ylabel('Átlagos Teljesítményigény [kW]', 'FontSize', 11);
    
    % X tengely beállítása, hogy pontosan 0-tól 24 óráig tartson, 2 órás osztásokkal
    xlim([0 24]);
    xticks(0:2:24);
    
    % Az átlagos csúcs és minimum pontjának megjelölése
    [max_val, max_idx] = max(avg_power_kW);
    [min_val, min_idx] = min(avg_power_kW);
    
    plot(time_hours(max_idx), max_val, 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
    text(time_hours(max_idx), max_val * 1.05, sprintf(' Csúcs: %.1f kW', max_val), 'Color', 'r', 'FontWeight', 'bold');
    
    plot(time_hours(min_idx), min_val, 'go', 'MarkerSize', 8, 'MarkerFaceColor', 'g');
    text(time_hours(min_idx), min_val * 0.90, sprintf(' Alap: %.1f kW', min_val), 'Color', 'g', 'FontWeight', 'bold');

    hold off;
end