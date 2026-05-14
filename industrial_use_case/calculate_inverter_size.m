function inv_size_kW = calculate_inverter_size(folderPath)
% CALCULATE_INVERTER_SIZE - Inverter statisztikai méretezése (95. percentilis)
% Bemenet: A napi fogyasztási .mat fájlokat tartalmazó mappa (pl. 'C:\adatok\')
% Kimenet: A javasolt inverter méret kW-ban a teljes időszakra

    % Fájlok listázása a mappából
    files = dir(fullfile(folderPath, '*.mat'));
    numFiles = length(files);

    % Memória lefoglalása a teljes időszakra (minden nap * 288 adatpont)
    all_power_W = zeros(numFiles * 288, 1);

    % Adatok beolvasása és összefűzése mindenféle kivételkezelés nélkül
    for i = 1:numFiles
        data = load(fullfile(folderPath, files(i).name), 'consumptionCache');
        
        % Pontos indexek kiszámítása az adott naphoz a nagy vektorban
        startIdx = (i - 1) * 288 + 1;
        endIdx = i * 288;
        
        all_power_W(startIdx:endIdx) = data.consumptionCache.powerTotal_W(:);
    end

    % --- Statisztikai Számítás a TELJES időszakra ---
    
    % 95. percentilis (Javasolt inverter méret)
    inv_size_W = prctile(all_power_W, 95);
    inv_size_kW = inv_size_W / 1000;
    
    % Abszolút maximum és átlag
    max_power_kW = max(all_power_W) / 1000;
    mean_power_kW = mean(all_power_W) / 1000;

    % Eredmények kiíratása a Parancsablakba
    fprintf('\n================ EREDMÉNYEK ================\n');
    fprintf('Feldolgozott teljes időszak: %d nap (%d adatpont)\n', numFiles, length(all_power_W));
    fprintf('Átlagos teljesítmény: %.2f kW\n', mean_power_kW);
    fprintf('Abszolút csúcsigény : %.2f kW\n', max_power_kW);
    fprintf('--------------------------------------------\n');
    fprintf('JAVASOLT INVERTER (95. percentilis): %.2f kW\n', inv_size_kW);
    fprintf('============================================\n');

    % --- Tartamgörbe (Load Duration Curve) ábrázolása ---
    
    % Növekvő sorrendbe rendezzük a teljes időszak adatait
    sorted_power_kW = sort(all_power_W) / 1000;
    
    % X tengely: A vizsgált időszak százalékos aránya (0-tól 100-ig)
    x_percent = linspace(0, 100, length(sorted_power_kW));

    figure('Name', 'Fogyasztási Tartamgörbe (Teljes Időszak)', 'Position', [200, 200, 800, 500]);
    plot(x_percent, sorted_power_kW, 'b-', 'LineWidth', 2);
    hold on;
    grid on;
    
    % 95. percentilis vonalak berajzolása
    yline(inv_size_kW, 'r--', 'LineWidth', 1.5);
    xline(95, 'r--', 'LineWidth', 1.5);
    
    % Vizuális kiegészítők
    plot(95, inv_size_kW, 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
    text(90, inv_size_kW + (max_power_kW * 0.05), sprintf(' 95. Percentilis:\n %.1f kW', inv_size_kW), 'Color', 'red', 'FontWeight', 'bold');

    title('Fogyasztási Tartamgörbe (Load Duration Curve) - Teljes Időszak');
    xlabel('A teljes vizsgált időszak százalékos aránya [%]');
    ylabel('Rendszer Teljesítményigénye [kW]');
    legend('Sorba rendezett teljesítményigény', '95% statisztikai határ', 'Location', 'northwest');
    hold off;
end