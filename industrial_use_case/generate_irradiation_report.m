function generate_irradiation_report(folderPath)
% GENERATE_IRRADIATION_REPORT - Irradiációs riport az új resultBuffer struktúrából.
% Bemenet: folderPath - A napi .mat fájlokat tartalmazó mappa elérési útja.

    try, set(groot,'defaultFigureRenderer','painters'); end %#ok<TRYNC>
    
    % Ha nincs megadva útvonal, bekérjük
    if nargin < 1 || isempty(folderPath)
        folderPath = uigetdir('', 'Válaszd ki a napi .mat fájlok mappáját');
        if folderPath == 0, return; end
    end

    % Címkék
    monthsHU  = {'Jan','Feb','Már','Ápr','Máj','Jún','Júl','Aug','Szep','Okt','Nov','Dec'};
    seasonsHU = {'Tél','Tavasz','Nyár','Ősz'};
    
    % Fájlok beolvasása
    files = dir(fullfile(folderPath, 'resultBuffer_ORIG_*.mat'));
    if isempty(files)
        warning('Nincs megfelelő fájl a megadott mappában!'); 
        return; 
    end
    
    numFiles = length(files);
    fprintf('Adatok beolvasása %d fájlból...\n', numFiles);

    % --- 0) Adatgyűjtő változók előkészítése ---
    dates = NaT(numFiles, 1);
    GHI_daily_sum  = zeros(numFiles, 1);
    DNHI_daily_sum = zeros(numFiles, 1);
    
    % Profilokhoz (átlagoláshoz)
    timeAxis = (0:5:1435) / 60; % Órák tizedes formában (0-tól 23.91-ig)
    prof_DNHI_m = zeros(12, 288); count_m = zeros(12, 1);
    prof_DHI_m  = zeros(12, 288);
    prof_DNHI_s = zeros(4, 288);  count_s = zeros(4, 1);
    prof_DHI_s  = zeros(4, 288);

    % Fájlok iterálása
    for i = 1:numFiles
        data = load(fullfile(folderPath, files(i).name), 'resultBuffer');
        rb = data.resultBuffer;
        
        % Dátum
        dt = datetime(rb.timeDay, 'InputFormat', 'yyyy.MM.dd');
        dates(i) = dt;
        
        % Vektorok kinyerése (W/m2)
        GHI = rb.irradiationData.GHI;
        DHI = rb.irradiationData.DIF;
        DNHI = max(0, GHI - DHI); % Direkt Horizontális komponens
        
        % Napi energia összegek (Wh/m2) -> (W * 5perc / 60perc/óra)
        GHI_daily_sum(i)  = sum(GHI) * (5/60);
        DNHI_daily_sum(i) = sum(DNHI) * (5/60);
        
        % Hónap és Évszak meghatározása
        m = month(dt);
        if ismember(m, [12, 1, 2]), s = 1;      % Tél
        elseif ismember(m, [3, 4, 5]), s = 2;   % Tavasz
        elseif ismember(m, [6, 7, 8]), s = 3;   % Nyár
        else, s = 4; end                        % Ősz
        
        % Profilok akkumulálása
        prof_DNHI_m(m, :) = prof_DNHI_m(m, :) + DNHI;
        prof_DHI_m(m, :)  = prof_DHI_m(m, :) + DHI;
        count_m(m) = count_m(m) + 1;
        
        prof_DNHI_s(s, :) = prof_DNHI_s(s, :) + DNHI;
        prof_DHI_s(s, :)  = prof_DHI_s(s, :) + DHI;
        count_s(s) = count_s(s) + 1;
    end
    
    % Időrendbe állítás a biztonság kedvéért
    [dates, sortIdx] = sort(dates);
    GHI_daily_sum  = GHI_daily_sum(sortIdx);
    DNHI_daily_sum = DNHI_daily_sum(sortIdx);
    
    yVec = year(dates);
    mVec = month(dates);
    years = unique(yVec);
    nY = length(years);

    % --- CSONKA ÉVEK SZŰRÉSE (Legalább 360 nap kell egy évhez) ---
    validYearsMask = false(nY, 1);
    for i = 1:nY
        % Itt módosítottuk 350-re a küszöböt!
        if sum(yVec == years(i)) >= 350 
            validYearsMask(i) = true;
        else
            fprintf('Figyelem: A %d. év csonka (csak %d nap), kihagyva az éves statisztikákból.\n', ...
                years(i), sum(yVec == years(i)));
        end
    end
    validYears = years(validYearsMask);
    nY_valid = length(validYears);

    %% ---------- 1) ÉVES FIGURE (Éves összegek) ----------
    GHI_year  = nan(nY_valid,1);
    DNHI_year = nan(nY_valid,1);
    ratioY    = nan(nY_valid,1); 
    
    for i = 1:nY_valid
        idx = (yVec == validYears(i));
        GHI_year(i)  = sum(GHI_daily_sum(idx)) / 1000;   % kWh/m^2 / év
        DNHI_year(i) = sum(DNHI_daily_sum(idx)) / 1000;  % kWh/m^2 / év
        ratioY(i)    = DNHI_year(i) / max(GHI_year(i), eps);
    end
    
    P50Y = mean(GHI_year,'omitnan');         
    P90Y = prctile(GHI_year,10);             
    P10Y = prctile(GHI_year,90);             
    
    GHI_year_mu  = mean(GHI_year,'omitnan');
    DNHI_year_mu = mean(DNHI_year,'omitnan');
    
    figure('Name','Éves összkép – ÖSSZESÍTETT értékek és P-értékek');
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
    
    nexttile; bar(GHI_year); grid on; xticks(1:nY_valid); xticklabels(string(validYears));
    ylabel('kWh/m^2 / év'); title('Összes GHI (évenként)');
    yline(GHI_year_mu,'--k', sprintf('%d év átlaga', nY_valid),'LabelHorizontalAlignment','left');
    
    nexttile; bar(DNHI_year); grid on; xticks(1:nY_valid); xticklabels(string(validYears));
    ylabel('kWh/m^2 / év'); title('Összes DNHI (évenként)');
    yline(DNHI_year_mu,'--k', sprintf('%d év átlaga', nY_valid),'LabelHorizontalAlignment','left');
    
    nexttile; bar(ratioY); grid on; xticks(1:nY_valid); xticklabels(string(validYears));
    ylim([0, max(1,1.1*max(ratioY,[],'omitnan'))]); ylabel('DNHI/GHI [-]'); title('DNHI/GHI arány');
    
    nexttile; Pvec = [P90Y, P50Y, P10Y]; bh = bar(Pvec); grid on;
    xticks(1:3); xticklabels({'P90','P50','P10'}); ylabel('kWh/m^2 / év');
    if numel(bh)==1, bh.FaceColor = 'flat'; end
    bh.CData = [0.20 0.20 0.70; 0.30 0.60 0.30; 0.85 0.35 0.10];
    legend({'konzervatív','átlag','optimista'},'Location','best');
    title('P-értékek (éves GHI)');

    %% ---------- 1/B) ÚJ FIGURE: ÉVES NAPI ÁTLAGOK ----------
    GHI_daily_avg_year  = nan(nY_valid,1);
    DNHI_daily_avg_year = nan(nY_valid,1);
    ratioY_daily        = nan(nY_valid,1); 
    
    for i = 1:nY_valid
        idx = (yVec == validYears(i));
        % Itt ÁTLAGOLJUK a napi értékeket az adott évben
        GHI_daily_avg_year(i)  = mean(GHI_daily_sum(idx)) / 1000;   % kWh/m^2 / nap
        DNHI_daily_avg_year(i) = mean(DNHI_daily_sum(idx)) / 1000;  % kWh/m^2 / nap
        ratioY_daily(i)        = DNHI_daily_avg_year(i) / max(GHI_daily_avg_year(i), eps);
    end
    
    GHI_daily_avg_mu  = mean(GHI_daily_avg_year,'omitnan');
    DNHI_daily_avg_mu = mean(DNHI_daily_avg_year,'omitnan');
    
    figure('Name','Éves összkép – ÁTLAGOS NAPI értékek évenként');
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
    
    nexttile; bar(GHI_daily_avg_year); grid on; xticks(1:nY_valid); xticklabels(string(validYears));
    ylabel('kWh/m^2 / nap'); title('Átlagos napi GHI (évenként)');
    yline(GHI_daily_avg_mu,'--k', sprintf('%d év átlaga', nY_valid),'LabelHorizontalAlignment','left');
    
    nexttile; bar(DNHI_daily_avg_year); grid on; xticks(1:nY_valid); xticklabels(string(validYears));
    ylabel('kWh/m^2 / nap'); title('Átlagos napi DNHI (évenként)');
    yline(DNHI_daily_avg_mu,'--k', sprintf('%d év átlaga', nY_valid),'LabelHorizontalAlignment','left');
    
    nexttile; bar(ratioY_daily); grid on; xticks(1:nY_valid); xticklabels(string(validYears));
    ylim([0, max(1,1.1*max(ratioY_daily,[],'omitnan'))]); ylabel('DNHI/GHI [-]'); title('Átlagos napi DNHI/GHI arány');
    
    % P-értékek az összes releváns nap (teljes évek) alapján
    valid_days_idx = ismember(yVec, validYears);
    all_valid_daily_GHI = GHI_daily_sum(valid_days_idx) / 1000; % kWh/m2/nap
    
    P50D = mean(all_valid_daily_GHI,'omitnan');         
    P90D = prctile(all_valid_daily_GHI,10);             
    P10D = prctile(all_valid_daily_GHI,90);             
    
    nexttile; PvecD = [P90D, P50D, P10D]; bhD = bar(PvecD); grid on;
    xticks(1:3); xticklabels({'P90','P50','P10'}); ylabel('kWh/m^2 / nap');
    if numel(bhD)==1, bhD.FaceColor = 'flat'; end
    bhD.CData = [0.20 0.20 0.70; 0.30 0.60 0.30; 0.85 0.35 0.10];
    legend({'konzervatív','átlag','optimista'},'Location','best');
    title('P-értékek (Összes napi GHI eloszlása)');

    %% ---------- 2) HAVI FIGURE ----------
    GHIm  = nan(12, nY_valid);
    DNHIm = nan(12, nY_valid);
    for i = 1:nY_valid
        for m = 1:12
            idx = (yVec == validYears(i) & mVec == m);
            if any(idx)
                GHIm(m,i)  = sum(GHI_daily_sum(idx)) / 1000;
                DNHIm(m,i) = sum(DNHI_daily_sum(idx)) / 1000;
            end
        end
    end
    
    GHIm_mu   = mean(GHIm, 2, 'omitnan');  
    DNHIm_mu  = mean(DNHIm, 2, 'omitnan');
    ratioM_mu = DNHIm_mu ./ max(GHIm_mu, eps);
    
    monthly_all = GHIm(:); monthly_all = monthly_all(isfinite(monthly_all));
    P50M = mean(monthly_all,'omitnan'); P90M = prctile(monthly_all,10); P10M = prctile(monthly_all,90);
    
    figure('Name','Havi összkép – összesített értékek és P-értékek');
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
    
    nexttile; bar(GHIm_mu); grid on; xticks(1:12); xticklabels(monthsHU);
    ylabel('kWh/m^2 / hó'); title('Összes GHI (többéves átlag)');
    
    nexttile; bar(DNHIm_mu); grid on; xticks(1:12); xticklabels(monthsHU);
    ylabel('kWh/m^2 / hó'); title('Összes DNHI (többéves átlag)');
    
    nexttile; bar(ratioM_mu); grid on; xticks(1:12); xticklabels(monthsHU);
    ylim([0, max(1,1.1*max(ratioM_mu,[],'omitnan'))]); ylabel('DNHI/GHI [-]'); title('DNHI/GHI arány');
    
    nexttile; PvecM = [P90M, P50M, P10M]; bh = bar(PvecM); grid on;
    xticks(1:3); xticklabels({'P90','P50','P10'}); ylabel('kWh/m^2 / hó');
    if numel(bh)==1, bh.FaceColor = 'flat'; end
    bh.CData = [0.20 0.20 0.70; 0.30 0.60 0.30; 0.85 0.35 0.10];
    legend({'konzervatív','átlag','optimista'},'Location','best'); title('P-értékek (havi GHI)');

    % Havi P-értékek külön plot
    P90m = nan(12,1); P50m = nan(12,1); P10m = nan(12,1);
    for m = 1:12
        x = GHIm(m,:); x = x(isfinite(x));
        if ~isempty(x)
            P50m(m) = mean(x,'omitnan'); P90m(m) = prctile(x,10); P10m(m) = prctile(x,90);
        end
    end
    figure('Name','Havi P-ertekek (GHI)');
    Pm = [P90m, P50m, P10m]; bh = bar(Pm, 'grouped'); grid on;
    xticks(1:12); xticklabels(monthsHU); ylabel('kWh/m^2 / hónap'); title('Havi GHI percentilisek');
    set(bh(1), 'FaceColor', [0.20 0.20 0.70]); set(bh(2), 'FaceColor', [0.30 0.60 0.30]); set(bh(3), 'FaceColor', [0.85 0.35 0.10]);
    legend({'konzervatív','átlag','optimista'}, 'Location', 'best');

    %% ---------- 3) ÉVSZAKOS FIGURE ----------
    sVec = zeros(size(mVec));
    sVec(ismember(mVec, [12,1,2])) = 1; sVec(ismember(mVec, [3,4,5])) = 2;
    sVec(ismember(mVec, [6,7,8])) = 3; sVec(ismember(mVec, [9,10,11])) = 4;
    
    GHIs = nan(4, nY_valid); DNHIs = nan(4, nY_valid);
    for i = 1:nY_valid
        for s = 1:4
            idx = (yVec == validYears(i) & sVec == s);
            if any(idx)
                GHIs(s,i)  = sum(GHI_daily_sum(idx)) / 1000;
                DNHIs(s,i) = sum(DNHI_daily_sum(idx)) / 1000;
            end
        end
    end
    
    GHIs_mu = mean(GHIs, 2, 'omitnan'); DNHIs_mu = mean(DNHIs, 2, 'omitnan');
    ratioS_mu = DNHIs_mu ./ max(GHIs_mu, eps);
    
    seasons_all = GHIs(:); seasons_all = seasons_all(isfinite(seasons_all));
    P50S = mean(seasons_all,'omitnan'); P90S = prctile(seasons_all,10); P10S = prctile(seasons_all,90);
    
    figure('Name','Évszakos összkép');
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
    nexttile; bar(GHIs_mu); grid on; xticks(1:4); xticklabels(seasonsHU); ylabel('kWh/m^2 / évszak'); title('Összes GHI (többéves átlag)');
    nexttile; bar(DNHIs_mu); grid on; xticks(1:4); xticklabels(seasonsHU); ylabel('kWh/m^2 / évszak'); title('Összes DNHI (többéves átlag)');
    nexttile; bar(ratioS_mu); grid on; xticks(1:4); xticklabels(seasonsHU); ylim([0, max(1,1.1*max(ratioS_mu,[],'omitnan'))]); ylabel('DNHI/GHI [-]'); title('DNHI/GHI arány');
    nexttile; PvecS = [P90S, P50S, P10S]; bh = bar(PvecS); grid on; xticks(1:3); xticklabels({'P90','P50','P10'}); ylabel('kWh/m^2 / évszak');
    if numel(bh)==1, bh.FaceColor = 'flat'; end
    bh.CData = [0.20 0.20 0.70; 0.30 0.60 0.30; 0.85 0.35 0.10];
    legend({'konzervatív','átlag','optimista'},'Location','best'); title('P-értékek (évszakos GHI)');

    % Évszakos P-értékek
    P90s = nan(4,1); P50s = nan(4,1); P10s = nan(4,1);
    for s = 1:4
        x = GHIs(s,:); x = x(isfinite(x));
        if ~isempty(x)
            P50s(s) = mean(x,'omitnan'); P90s(s) = prctile(x,10); P10s(s) = prctile(x,90);
        end
    end
    figure('Name','Évszakos P-ertekek (GHI)');
    Ps = [P90s, P50s, P10s]; bh = bar(Ps, 'grouped'); grid on;
    xticks(1:4); xticklabels(seasonsHU); ylabel('kWh/m^2 / évszak'); title('Évszakos GHI percentilisek');
    set(bh(1), 'FaceColor', [0.20 0.20 0.70]); set(bh(2), 'FaceColor', [0.30 0.60 0.30]); set(bh(3), 'FaceColor', [0.85 0.35 0.10]);
    legend({'konzervatív','átlag','optimista'}, 'Location', 'best');

    %% ---------- 4) NAPI PROFILOK ----------
    avgDNHI_m = prof_DNHI_m ./ max(count_m, 1); avgDNHI_m(count_m==0, :) = NaN;
    avgDHI_m  = prof_DHI_m  ./ max(count_m, 1); avgDHI_m(count_m==0, :)  = NaN;
    
    figure('Name','Átlagos napi teljesítményprofilok – Havi bontás');
    tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
    nexttile; hold on; grid on; plot(timeAxis, avgDNHI_m'); xlabel('Óra'); ylabel('W/m^2'); legend(monthsHU,'Location','bestoutside'); title('DNHI – átlagos napi profilok (havi)');
    nexttile; hold on; grid on; plot(timeAxis, avgDHI_m'); xlabel('Óra'); ylabel('W/m^2'); legend(monthsHU,'Location','bestoutside'); title('DHI – átlagos napi profilok (havi)');

    avgDNHI_s = prof_DNHI_s ./ max(count_s, 1); avgDNHI_s(count_s==0, :) = NaN;
    avgDHI_s  = prof_DHI_s  ./ max(count_s, 1); avgDHI_s(count_s==0, :)  = NaN;

    figure('Name','Átlagos napi teljesítményprofilok – Évszakos bontás');
    tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
    nexttile; hold on; grid on; plot(timeAxis, avgDNHI_s'); xlabel('Óra'); ylabel('W/m^2'); legend(seasonsHU,'Location','bestoutside'); title('DNHI – átlagos napi profilok (évszakos)');
    nexttile; hold on; grid on; plot(timeAxis, avgDHI_s'); xlabel('Óra'); ylabel('W/m^2'); legend(seasonsHU,'Location','bestoutside'); title('DHI – átlagos napi profilok (évszakos)');
    
    fprintf('A plottolás sikeresen befejeződött.\n');
end