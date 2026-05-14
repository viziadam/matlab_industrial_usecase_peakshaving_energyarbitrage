function [globalIdx, hit] = dccoupled_simulation_core( tiltX, tiltZ, dcac_target, ChargeMode, ESpec_grid, CRate_grid, LifetimeYears, YearsAvailable, startIdx, totalPoints, t_start)
% BESS szimuláció – Teljes, modularizált verzió szigorú bemenetekkel

% ===== 1) BEMENETI ELLENŐRZÉS ÉS ELŐKÉSZÍTÉS =====
if isempty(LifetimeYears) || isempty(YearsAvailable), error('Hiba: Élettartam paraméterek hiányoznak!'); end

% Teljesítmény-rács kiválasztása (pontosan egynek kell lennie)
if isempty(CRate_grid), error('Hiba: Pontosan egy teljesítmény-meghatározást adj meg!'); end

thisDir = fileparts(mfilename('fullpath'));
matName = 'dccoupled_normalized_vault.mat'; % A fájl neve
matPath = fullfile(thisDir, matName);

if ~exist(matPath, 'file'), error('Hiba: Vault nem található: %s', matPath); end

% 2. Betöltés
% Mivel a mentésnél a fájlnevet használtuk változónévnek:
[~, varName, ~] = fileparts(matName);
varName = matlab.lang.makeValidName(varName); % Biztosítjuk, hogy ugyanazt a nevet kapjuk

data = load(matPath); 
S = data.(varName); % Közvetlenül kinyerjük a struktúrát a neve alapján

% Megfelelő rendszer és DC/AC pont keresése
sysIdx = dccoupled_find_orientation_idx(S.evaluations.systems, tiltX, tiltZ);
node = dccoupled_find_dcac_node(S.evaluations.systems(sysIdx).results, dcac_target);

Pdc = 1.0;
Pinv = Pdc / node.dcacratio;
timeAxis = utils_time_create_timeaxis(5);
runAt = datetime('now');

% Kapacitás rács véglegesítése
EGrid = ESpec_grid(:); 
NE = numel(EGrid);
NC = max([numel(CRate_grid)]);

rows_cell = cell(NE * NC, 1);

% Tábla és fájlkezelés előkészítése
rows(NE*NC, 1) = make_row_proto_pvref_();
F = numel(S.evaluations.files);
[filesPerYear, extraPerYear] = calculate_file_slices(F, YearsAvailable, LifetimeYears);

% PV adatok gyorsítótárazása
tic;
PV = build_pv_cache(S.evaluations.files, S.evaluations.systems(sysIdx).panelIndexes, timeAxis);
fprintf('Adatbetöltés kész: %.3f s\n', toc);



% ===== 2) SZIMULÁCIÓS FŐCIKLUS =====
r = 0;
for ie = 1:NE
    E_bess_cap = EGrid(ie);
    for ic = 1:NC
        r = r + 1;

        currentIdx = startIdx + r - 1;    
        t_point = tic;

        C = CRate_grid(ic);
        P_bess_max = C * E_bess_cap;
        
        pars = base_battery_pars_nonideal_(E_bess_cap, P_bess_max);
        % Inicializálás
        [~, state] = battery_core_model_vector([], 'init', pars, 1/12, []); 
        [agg, prof, degrad, state] = init_simulation_containers(LifetimeYears, timeAxis, E_bess_cap, pars, state);
        
        for iy = 1:LifetimeYears
            acc = init_accumulators_(timeAxis);
            selIdx = get_yearly_file_indices(iy, F, filesPerYear, extraPerYear);
            
            for jj = selIdx
                % 1. Napi PV adatok (már vektor)
                Ppv_vec = PV(jj).Ppv / 265; 
                dt_h = PV(jj).dt_h;
                
                % 2. VEKTOROS STRATÉGIA (Ez váltja ki a k-ciklust)
                % Egyszerre kiszámolja a nap összes lépését
                [dayRes, state] = dccoupled_energy_strategy_vector(Ppv_vec, Pinv, ChargeMode, pars, state, dt_h);
                
                % 3. KÖNYVELÉS (Vektoros összegek)
                % A day struktúra mezőit a vektorok összegeivel töltjük fel
                day = summarize_day_vector(dayRes, Ppv_vec, dt_h);
                
                % A profil gyűjtőkhöz egyszerűen hozzáadjuk a napi vektorokat
                acc = update_profile_accumulators_vector(acc, dayRes, Ppv_vec, dt_h, PV(jj));
                acc = add_day_to_acc_(acc, day);
            end
            
            [agg, prof, degrad, state] = finalize_year_data(iy, acc, agg, prof, degrad, state, E_bess_cap);
        end
        rows_cell{r} = pack_results_to_row(E_bess_cap, C, P_bess_max, ...
                  dcac_target, Pdc, Pinv, LifetimeYears, runAt, agg, prof, degrad, timeAxis);
        
        % --- PROGRESS BAR FRISSÍTÉSE ---
        point_time = toc(t_point);
        pct = currentIdx / totalPoints;
        elapsed = toc(t_start);
        remaining = (elapsed / currentIdx) * (totalPoints - currentIdx);
            
        % ETA számítás a belső rácshoz
        elapsed = toc(t_start);
        remaining = (elapsed / currentIdx) * (totalPoints - currentIdx);
            
        fprintf('\r[%3.0f%%] (%d/%d) | DCAC: %.1f | BESS: %.1fkWh | Pont: %.2fs | ETA: %s', ...
                pct*100, currentIdx, totalPoints, dcac_target, EGrid(ie), point_time, sec2hms(remaining));
        drawnow limitrate;
    end
    globalIdx = startIdx + r; % Visszaadjuk, hol tartunk (opcionális)
end
% ===== 3) MENTÉS =====
% A [rows_cell{:}] "kiborítja" a cellák tartalmát, a szögletes zárójel pedig tömbbé fűzi őket.
rows = [rows_cell{:}];
save_results_to_vault(matPath,  varName, S, sysIdx, dcac_target, rows);
hit = struct( 'rows', height(struct2table(rows)), 'runAt', runAt);

end

% ================== BECSOMAGOLT SEGÉDFÜGGVÉNYEK ==================

function row = make_row_proto_pvref_()
    row = struct('E_bess',NaN, ...         % fajlagos kapacitás
                 'C_rate',NaN, 'P_max', NaN, ... % fajlagos teljesítmény
                 'Ppv',NaN,'Pinv',NaN, ...
                 'dcac',NaN, 'LifetimeYears',NaN,'runAt',NaT,'results',[]);
end


function [fPY, ePY] = calculate_file_slices(F, YA, LY)
    % Kiszámolja az évenkénti fájlszeleteket (körkörös kezeléshez)
    fPY = max(1, floor(F / max(1, YA)));
    rem = F - fPY * YA;
    ePY = zeros(1, LY);
    for i = 1:min(rem, LY), ePY(i) = 1; end
end

function acc = init_accumulators_(timeAxis)
    M = numel(timeAxis); 
    z = zeros(1, M);
    
    % Idősoros gyűjtők (Profilokhoz)
    acc.cnt             = z;
    acc.P_pv_sum        = z; 
    acc.P_clip_raw      = z; 
    acc.P_clip_rec      = z;
    acc.P_ac_inv_out    = z; 
    acc.P_bess_ac_out   = z;
    
    acc.ndays = 0;

    acc.sum = struct(...
        'E_pv', 0, ...
        'E_ac_inv', 0, ...
        'E_clip_raw', 0, ...
        'E_stored', 0, ...
        'E_discharged', 0, ...
        'E_bess_ac', 0, ...
        'E_inv_loss', 0, ...
        'E_block_power_loss', 0, ...
        'E_block_cap_loss', 0);
    
    acc.peak = struct('P_pv_peak', 0, 'P_bess_stored_peak', 0, 'P_bess_dis_peak', 0);
end

function idxs = get_yearly_file_indices(iy, F, fPY, ePY)
    % Meghatározza az aktuális évben használandó fájlok indexeit
    baseShift = (iy-1)*fPY + sum(ePY(1:iy-1));
    startIdx = mod(baseShift, F) + 1;
    thisYearCount = fPY + ePY(iy);
    idxs = mod((startIdx-1) + (0:thisYearCount-1), F) + 1;
end

function acc = add_day_to_acc_(acc, day)
    f = fieldnames(acc.sum);
    for i=1:numel(f)
        k = f{i};
        if isfield(day,k)
            acc.sum.(k) = acc.sum.(k) + day.(k);
        end
    end
    
    acc.peak.P_pv_peak       = max(acc.peak.P_pv_peak,       day.P_pv_peak);
    acc.peak.P_bess_stored_peak = max(acc.peak.P_bess_stored_peak, day.P_bess_stored_peak);
    acc.peak.P_bess_dis_peak = max(acc.peak.P_bess_dis_peak, day.P_bess_dis_peak);
    acc.ndays = acc.ndays + 1;
end

function [agg, prof, degrad, state] = init_simulation_containers(NY, timeAxis, E_nom, pars, state)
    % Inicializálja a szimuláció gyűjtőstruktúráit
    agg = init_yearly_aggs_(NY);
    prof = init_profile_mats_(numel(timeAxis), NY);
    
    tmp = battery_core_model_vector(0, "charge", pars, 1/12, state);
    
    state.E_act = tmp.E_act;
    state.E_cap_eff = tmp.E_cap_eff;
    state.R_series = tmp.R_series_rel;
    
    degrad.E_cap_eff_y = nan(1, NY+1);
    degrad.cap_retention_y = nan(1, NY+1);
    degrad.cycles_equiv_cum_y = zeros(1, NY+1);
    degrad.E_cap_eff_kWh_y(1) = state.E_cap_eff;
    degrad.cap_retention_y(1) = state.E_cap_eff / E_nom;
end

function x = div_or_zero_(num, den)
    % Segédfüggvény a biztonságos osztáshoz (elkerüli a NaN-t, ha den=0)
    x = zeros(size(num));
    m = den > 0; 
    x(m) = num(m) ./ den(m);
end

function day = init_daily_struct_()
    % Létrehozza a napi gyűjtőstruktúrát, amit minden reggel nullázunk.
    
    day = struct(...
        'E_pv', 0, ...
        'E_ac_inv', 0, ...
        'E_clip_raw', 0, ...
        'E_stored', 0, ...
        'E_discharged', 0, ...
        'E_bess_ac', 0, ...
        'E_inv_loss', 0, ...
        'E_block_power_loss', 0, ...
        'E_block_cap_loss', 0, 'P_pv_peak', 0, 'P_bess_stored_peak', 0, 'P_bess_dis_peak', 0);
    
end

function [step, state] = dccoupled_energy_strategy_vector(Ppv_vec, Pinv, mode, pars, state, dt_h)
    % DC-coupled stratégia - TELJESEN VEKTORIZÁLT (MASZKOLT) verzió
    % Nincsenek belső for-ciklusok, a logika 1:1 az eredetivel.

    N = numel(Ppv_vec);
    E_pv_vec = Ppv_vec .* dt_h;

    % 1. STRATÉGIAI DÖNTÉS MASZKOKKAL
    mask_chg = Ppv_vec >= Pinv;
    mask_dis = ~mask_chg;

    % --- TÖLTÉS ÁG ELŐKÉSZÍTÉSE (Vektoros) ---
    E_clip_raw = zeros(1, N);
    E_clip_raw(mask_chg) = (Ppv_vec(mask_chg) - Pinv) .* dt_h;
    
    % Konverter hívása csak a töltési energiákra
    conv_chg = dcdc_converter_model_vector(E_clip_raw, 'charge', pars.P_rated, dt_h);

    % --- KISÜTÉS ÁG ELŐKÉSZÍTÉSE (Vektoros) ---
    P_gap = zeros(1, N);
    P_gap(mask_dis) = Pinv - Ppv_vec(mask_dis);
    E_req_ac_gap = P_gap .* dt_h;
    
    % Konverter hívása a hiányzó energiára (discharge mód: kiszámolja mennyit kér a cellától)
    conv_dis_req = dcdc_converter_model_vector(E_req_ac_gap, 'discharge', pars.P_rated, dt_h);

    % 2. AKKUMULÁTOR MODELL HÍVÁSA (Vektorosan, rekurzióval belül)
    % Összeállítunk egy "nettó kérés" vektort a cella felé:
    % Pozitív: amit a konverter betolna (töltés)
    % Negatív: amit a konverter kérne (kisütés)
    E_cell_request = zeros(1, N);
    E_cell_request(mask_chg) = conv_chg.E_out(mask_chg);
    E_cell_request(mask_dis) = -conv_dis_req.E_out(mask_dis); 

    % Meghívjuk a vektoros akku modellt (ez az egyetlen, ami belül rekurzív az SoC miatt)
    [bat, state] = battery_core_model_vector(E_cell_request, 'mixed', pars, dt_h, state);

    % 3. EREDMÉNYEK ÖSSZEFÉSÜLÉSE (Vektorosan)
    % Kisütés után az akkuból ténylegesen kijövő energiát újra átküldjük a konverteren az Inverter felé
    % (Ez felel meg az eredeti kódod conv = dcdc_converter_model(bat.E_out, 'charge'...) sorának)
    conv_dis_final = dcdc_converter_model_vector(bat.E_out, 'charge', pars.P_rated, dt_h);

    % DC gyűjtősín (DC Link) mérlege
    % Töltéskor: az Inverter fixen Pinv-et kap (vagy Ppv-t ha az kisebb)
    % Kisütéskor: Ppv + amit a BESS konvertere ténylegesen le tudott adni
    E_bess_to_dc = zeros(1, N);
    E_bess_to_dc(mask_dis) = conv_dis_final.E_out(mask_dis);
    
    step.E_dc_inv = zeros(1, N);
    step.E_dc_inv(mask_chg) = Pinv .* dt_h;
    step.E_dc_inv(mask_dis) = (Ppv_vec(mask_dis) .* dt_h) + E_bess_to_dc(mask_dis);

    % Inverter kimenet
    step.E_ac_inv  = step.E_dc_inv .* pars.inv_eta;
    step.E_inv_loss = step.E_dc_inv .* (1 - pars.inv_eta);

    % Könyvelés az eredeti nevekkel
    step.E_pv          = E_pv_vec;
    step.E_clip_raw    = E_clip_raw;
    step.E_stored      = bat.E_stored;
    step.E_discharged  = bat.E_discharged;
    step.E_bess_ac     = E_bess_to_dc .* pars.inv_eta;
    
    % Veszteségek összesítése
    step.conv_loss     = conv_chg.conv_loss + conv_dis_req.conv_loss + conv_dis_final.conv_loss;
    step.cell_loss     = bat.cell_loss;
    
    % Korlátok miatti veszteségek
    step.E_block_cap   = bat.E_block_cap;
    step.E_block_power = conv_chg.E_loss_conv_clipped + ...
                         conv_dis_req.E_loss_conv_clipped + ...
                         conv_dis_final.E_loss_conv_clipped;

    % Állapotok mentése (vektorként az egész napra)
    step.E_act         = bat.E_act;
    step.E_cap_eff     = bat.E_cap_eff;
    step.R_series_rel  = bat.R_series_rel;
end

function day = summarize_day_vector(s, Ppv_vec, dt_h)
    day = init_daily_struct_();
    day.E_pv         = sum(Ppv_vec * dt_h);
    day.E_ac_inv     = sum(s.E_ac_inv);
    day.E_clip_raw   = sum(s.E_clip_raw);
    day.E_stored     = sum(s.E_stored);
    day.E_discharged = sum(s.E_discharged);
    day.E_bess_ac    = sum(s.E_bess_ac);
    day.E_inv_loss   = sum(s.E_inv_loss);
    day.E_block_power_loss = sum(s.E_block_power);
    day.E_block_cap_loss   = sum(s.E_block_cap);
    
    % Peak értékek a vektor maximumai
    day.P_pv_peak          = max(Ppv_vec);
    day.P_bess_stored_peak = max(s.E_stored / dt_h);
    day.P_bess_dis_peak    = max(s.E_discharged / dt_h);
end

% function acc = update_profile_accumulators_vector(acc, s, Ppv_vec, dt_h, timeMinVec, timeAxis)
%     % Meghatározzuk, hogy a bejövő adatok (timeMinVec) 
%     % melyik indexre esnek a fix rácsban (timeAxis)
%     % A '5' a mintavételi idő (perc), ezt érdemes lehet változóként kezelni
%     binMin = timeAxis(2) - timeAxis(1);
%     idxs = round((timeMinVec - timeAxis(1)) / binMin) + 1;
% 
%     % Csak azokat tartjuk meg, amik a timeAxis tartományába esnek
%     valid = idxs >= 1 & idxs <= numel(acc.cnt);
%     target_idx = idxs(valid);
% 
%     % Ha a vektorok hossza eltér, a valid maszkot alkalmazzuk a forrás adatokon is
%     Ppv_valid = Ppv_vec(valid);
%     E_ac_inv_valid = s.E_ac_inv(valid);
%     E_clip_raw_valid = s.E_clip_raw(valid);
%     E_stored_valid = s.E_stored(valid);
%     E_bess_ac_valid = s.E_bess_ac(valid);
% 
%     % VEKTORIZÁLT HOZZÁADÁS: 
%     % Az acc.P_pv_sum(target_idx) = acc.P_pv_sum(target_idx) + Ppv_valid 
%     % NEM MŰKÖDIK jól, ha több adat esik ugyanabba a bin-be, ezért használunk accumarray-t:
% 
%     acc.cnt(target_idx) = acc.cnt(target_idx) + 1;
%     acc.P_pv_sum(target_idx)    = acc.P_pv_sum(target_idx)    + Ppv_valid;
%     acc.P_ac_inv_out(target_idx)   = acc.P_ac_inv_out(target_idx)   + (E_ac_inv_valid / dt_h);
%     acc.P_clip_raw(target_idx) = acc.P_clip_raw(target_idx) + (E_clip_raw_valid / dt_h);
%     acc.P_clip_rec(target_idx) = acc.P_clip_rec(target_idx) + (E_stored_valid / dt_h);
%     acc.P_bess_ac_out(target_idx)  = acc.P_bess_ac_out(target_idx)  + (E_bess_ac_valid / dt_h);
% end

function acc = update_profile_accumulators_vector(acc, s, Ppv_vec, dt_h, pv_node)
    % pv_node: ez a PV(jj) struktúra, ami már tartalmazza a targetIdx-et
    
    target_idx = pv_node.targetIdx;
    mask = pv_node.validMask;
    
    % Csak a maszkolt (valid) adatokat használjuk
    Ppv_valid = Ppv_vec(mask);
    E_ac_inv_valid = s.E_ac_inv(mask);
    E_clip_raw_valid = s.E_clip_raw(mask);
    E_stored_valid = s.E_stored(mask);
    E_bess_ac_valid = s.E_bess_ac(mask);
    
    % Nincs kerekítés, nincs matek, csak pakolás a helyére
    acc.cnt(target_idx) = acc.cnt(target_idx) + 1;
    acc.P_pv_sum(target_idx) = acc.P_pv_sum(target_idx) + Ppv_valid;
    acc.P_ac_inv_out(target_idx) = acc.P_ac_inv_out(target_idx) + (E_ac_inv_valid / dt_h);
    acc.P_clip_raw(target_idx) = acc.P_clip_raw(target_idx) + (E_clip_raw_valid / dt_h);
    acc.P_clip_rec(target_idx) = acc.P_clip_rec(target_idx) + (E_stored_valid / dt_h);
    acc.P_bess_ac_out(target_idx) = acc.P_bess_ac_out(target_idx) + (E_bess_ac_valid / dt_h);
end

function pars = base_battery_pars_nonideal_(E_cap_nom, Pmax)
% Alap BESS paraméterek – kalibráció belső defaultokon.
    pars = struct();

    % --- Névl. méretek és teljesítménykorlátok ---
    pars.E_cap_nom        = E_cap_nom;            
    pars.P_rated          = Pmax;              
    pars.C_chg_abs_max    = Pmax / max(E_cap_nom, eps);
    pars.C_dis_abs_max    = pars.C_chg_abs_max;
    pars.P_chg_max        = Pmax;
    pars.P_dis_max        = Pmax;

    % --- SoC határok és kezdeti állapot ---
    pars.SoC_min          = 0.20;
    pars.SoC_max          = 0.80;
    pars.SoC_init         = 0.50;

    % --- Konverter ág hatásfokok és ohmikus alapbüntetés ---
    pars.eta_c            = 0.975;
    pars.eta_d            = 0.975;
    pars.k_ohm            = 0.020;

    % --- Önkisülés ---
    pars.self_dis_per_h   = 2e-5;

    % --- Kapacitás alsó korlát ---
    pars.cap_floor_frac   = 0.70;

    % --- Inverter és DC/DC hatásfokok ---
    pars.inv_eta          = 0.97;
    pars.eta_c       = 0.98;
    pars.eta_d       = 0.98;

    % ===== Cella szintű kiegészítések =====
    pars.eta_cell         = 0.985;
    pars.eta_cell_min     = 0.90;

    % Pillanatnyi C-ráta és SoC büntetés a cellahatásfokra
    pars.k_eta_C2         = 0.02;
    pars.k_eta_soc        = 0.02;
    pars.soc_ref          = 0.5;

    % Impedancia-növekedés skálái
    pars.R_growth_time_k  = 0.50;
    pars.R_growth_cap_k   = 1.00;

    % Ajánlott C-ráta (belső referencia)
    C_abs                 = Pmax / max(E_cap_nom, eps);
    C_ref                 = min(C_abs, 0.5);
    pars.C_rec_chg        = C_ref;
    pars.C_rec_dis        = C_ref;
end

function out = init_yearly_aggs_(NY)
    z = zeros(1,NY);
    out = struct( ...
      'E_pv',z,'E_ac_inv',z,'E_clip_raw',z,'E_stored',z,'E_clip_waste',z, ...
      'E_bess_ac',z,'E_block_power_loss',z,'E_inv_loss',z, ...  % ÚJ
      'E_block_cap_loss',z,'P_pv_peak',z,'P_bess_stored_peak',z,'P_bess_dis_peak',z, ...
      'P_pv_peak_kW',z,'P_ac_peak_kW',z,'P_bess_chg_peak_kW',z,'P_bess_dis_peak_kW',z);
    
end

function y = finalize_year_(acc)
    % Az év végén az akkumulált (összeadott) napi adatokból 
    % kiszámolja az éves átlagos napi profilokat.
    y = struct();
    
    % Alapvető éves összegek (MWh)
    y.E_pv           = acc.sum.E_pv;
    y.E_ac_inv          = acc.sum.E_ac_inv;
    y.E_clip_raw        = acc.sum.E_clip_raw;
    y.E_stored        = acc.sum.E_stored;
    y.E_clip_waste      = max(acc.sum.E_clip_raw - acc.sum.E_stored, 0);
    y.E_bess_ac         = acc.sum.E_bess_ac;
    y.E_block_power_loss     = acc.sum.E_block_power_loss;
    y.E_inv_loss     = acc.sum.E_inv_loss;
    y.E_block_cap_loss        = acc.sum.E_block_cap_loss;

    y.P_pv_peak = acc.peak.P_pv_peak;
    y.P_bess_stored_peak = acc.peak.P_bess_stored_peak;
    y.P_bess_dis_peak = acc.peak.P_bess_dis_peak;
    
    
    % ÁTLAGPROFILOK KISZÁMÍTÁSA (Összeg / Napok száma)
    prof = struct();
    prof.P_pv_sum    = div_or_zero_(acc.P_pv_sum,    acc.cnt);
    prof.P_clip_raw = div_or_zero_(acc.P_clip_raw, acc.cnt);
    prof.P_clip_rec = div_or_zero_(acc.P_clip_rec, acc.cnt);
    prof.P_ac_inv_out   = div_or_zero_(acc.P_ac_inv_out,   acc.cnt);
    prof.P_bess_ac_out  = div_or_zero_(acc.P_bess_ac_out,  acc.cnt);
    y.profiles = prof;
end

function [agg, prof, degrad, state] = finalize_year_data(iy, acc, agg, prof, degrad, state, E_nom)
    % iy: aktuális év, E_nom: BESS névleges kapacitás [kWh], Pdc_kW: PV névleges [kWp]
    
    yres = finalize_year_(acc);
    f = fieldnames(agg);
    for i=1:numel(f)
        if isfield(yres, f{i}), agg.(f{i})(iy) = yres.(f{i}); end
    end
    
    
    % Recovery Rate (Mentett / Összes levágott)
    agg.recovery_rate(iy)    = yres.E_stored / max(yres.E_clip_raw, eps);
    
    % Profilok mentése (már benne volt az eredetiben)
    prof.P_pv_sum(:,iy) = yres.profiles.P_pv_sum;
    prof.P_ac_inv_out(:,iy) = yres.profiles.P_ac_inv_out;
    
    % Degradáció könyvelése
    degrad.E_cap_eff_kWh_y(iy+1) = state.E_cap_eff;
    degrad.cap_retention_y(iy+1) = state.E_cap_eff / E_nom;
    degrad.cycles_equiv_cum_y(iy+1) = degrad.cycles_equiv_cum_y(iy) + ((yres.E_stored+yres.E_bess_ac)/E_nom);
end
% function row = pack_results_to_row(E_bess, C, Pmax, dcac, Pdc, Pinv, NY, runAt, agg, prof, degrad, tAxis)
%     row = make_row_proto_pvref_();
%     row.E_bess = E_bess; 
%     row.C_rate = C;
%     row.P_max = Pmax;  
%     row.dcac = dcac;             % Ez a másik fő változód (Y tengely a ploton)
%     row.Pdc = Pdc; 
%     row.Pinv = Pinv; 
%     row.LifetimeYears = NY; 
%     row.runAt = runAt;
% 
%     % Összegzett eredmények a könnyű plotoláshoz
%     res.agg = agg; 
%     res.profiles = prof; 
%     res.degrad = degrad; 
%     res.timeAxis = tAxis;
% 
%     % --- KIEMELT NORMALIZÁLT MUTATÓK ---
%     res.avg_recovery_rate = mean(agg.recovery_rate); % Átlagos hatékonyság
%     % res.avg_spec_gain_h   = mean(agg.spec_clip_rec_h); % Átlagos éves plusz óra [h/év]
%     res.total_cycles      = degrad.cycles_equiv_cum_y(end);
%     res.final_soh         = degrad.cap_retention_y(end);
% 
%     row.results = res;
% end

function row = pack_results_to_row(E_bess, C, Pmax, dcac, Pdc, Pinv, NY, runAt, agg, prof, degrad, tAxis)
    % PACK_RESULTS_TO_ROW Összecsomagolja egyetlen rácspont szimulációs eredményeit.
    %
    % Ez a függvény felelős azért, hogy a bonyolult gyűjtőstruktúrákat (éves, profil, degradáció)
    % egyetlen, a Vault-ba menthető sorba (row) rendezze.

    % 1. Alap adatok (Méretezési paraméterek)
    row.E_bess = E_bess;        % BESS névleges kapacitás [kWh]
    row.C_rate = C;             % Kiválasztott C-ráta
    row.P_max  = Pmax;          % BESS max teljesítmény [kW]
    row.dcac   = dcac;          % Alkalmazott DC/AC arány
    row.Pdc    = Pdc;           % Napelem DC teljesítmény (normalizált 1.0 vagy kW)
    row.Pinv   = Pinv;          % Inverter AC teljesítmény
    row.LifetimeYears = NY;     % Szimulált évek száma
    row.runAt  = runAt;         % Szimuláció futtatásának időpontja

    % 2. Belső eredmény-struktúra (res) összeállítása
    % Fontos: Minden rácspontban ugyanazokat a mezőket kell tartalmaznia!
    res = struct();
    res.agg      = agg;         % Éves összesített adatok (MWh, hatásfokok, stb.)
    res.profiles = prof;        % 24 órás átlagprofilok mátrixai (idő x év)
    res.degrad   = degrad;      % Kapacitásvesztés és ciklusszám adatsorok
    res.timeAxis = tAxis;       % Az alkalmazott időtengely (pl. 250-1200)

    % 3. Kiemelt (aggregált) mutatók számítása a könnyű elemzéshez
    % Ezek segítik a gyors kiértékelést anélkül, hogy az agg-ba bele kellene nézni
    
    % Átlagos Recovery Rate a teljes élettartam alatt
    if isfield(agg, 'recovery_rate')
        res.avg_recovery_rate = mean(agg.recovery_rate, 'omitnan'); 
    else
        res.avg_recovery_rate = NaN;
    end
    
    % Átlagos éves fajlagos visszanyert energia [h/év]
    if isfield(agg, 'spec_clip_rec_h')
        res.avg_spec_gain_h = mean(agg.spec_clip_rec_h, 'omitnan');
    else
        res.avg_spec_gain_h = NaN;
    end

    % Végső állapot mutatók (az utolsó szimulált év végén)
    if isfield(degrad, 'cycles_equiv_cum_y')
        res.total_cycles = degrad.cycles_equiv_cum_y(end);
    else
        res.total_cycles = 0;
    end

    if isfield(degrad, 'cap_retention_y')
        res.final_soh = degrad.cap_retention_y(end);
    else
        res.final_soh = 1.0;
    end

    % 4. Az összesített eredmények elhelyezése a sorban
    row.results = res;
end

function prof = init_profile_mats_(T, NY)
    % Profil-mátrixok (időindex × év) inicializálása nullákkal
    % T: időlépések száma egy napban (pl. 24h * 12 bin/h = 288)
    % NY: szimulált évek száma (élettartam)
    
    z = zeros(T, NY);
    prof = struct( ...
        'P_pv_sum',    z, ... % Átlagos PV termelés profilja
        'P_clip_raw', z, ... % Átlagos levágott energia profilja
        'P_clip_rec', z, ... % Átlagos visszanyert (töltött) energia profilja
        'P_ac_inv_out',   z, ... % Átlagos AC kimenő teljesítmény profilja
        'P_bess_ac_out',  z );   % Átlagos BESS kisütési profil
end

function save_results_to_vault(path, varName, S, sIdx, dcacT, rows)
    % Az eredmények visszamentése a .mat fájlba az új struktúra szerint
    T = struct2table(rows);
    
    % 1. Kiolvassuk a DC/AC rátákat a struktúra-tömbből
    % Mivel S.evaluations.systems(sIdx).results egy struct array, 
    % a [results.dcacratio] egy numerikus vektort ad vissza.
    dvec = [S.evaluations.systems(sIdx).results.dcacratio];
    
    % 2. Megkeressük a cél indexet
    dIdx = find(abs(dvec - dcacT) < 1e-9, 1, 'first');
    
    if isempty(dIdx)
        error('Hiba: A megadott DC/AC arány (%.2f) nem található a vaultban!', dcacT);
    end
    
    % 3. Adatok beillesztése
    % FIGYELEM: sima zárójelet () használunk a cella helyett!
    S.evaluations.systems(sIdx).results(dIdx).dccoupled_norm_results = T;
    
    % 4. Mentés a dinamikus változónévvel
    vars.(varName) = S;
    save(path, '-struct', 'vars', '-v7.3');
    
    fprintf('Eredmények sikeresen mentve a vaultba (%s -> %s).\n', varName, S.evaluations.systems(sIdx).name);
end

function s = sec2hms(sec)
    if ~isfinite(sec) || sec < 0
        s = '--:--:--';
        return;
    end
    hh = floor(sec/3600);
    mm = floor(mod(sec,3600)/60);
    ss = floor(mod(sec,60));
    s = sprintf('%02d:%02d:%02d', hh, mm, ss);
end