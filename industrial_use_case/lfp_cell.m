% function [out, state] = lfp_cell(P_req_cell, mode, params, dt_h, state)
%     % LFP_CELL
%     % ECM + hőmodell mintánként
%     % degradáció batch végén, összefüggő szakaszra
% 
%     M_CELL = 5.4;
%     CP     = 1100;
%     C_TH   = M_CELL * CP;
%     R_TH   = 4.0;
% 
%     SOC_MIN = 0.20;
%     SOC_MAX = 0.80;
% 
%     if strcmp(mode, 'init')
%         state = struct();
%         state.C_nom   = must(params, 'C_nom_Ah', 280);
%         state.V_nom   = must(params, 'V_nom', 3.2);
%         state.SOC     = must(params, 'initial_soc', 0.5);
%         state.T_cell  = must(params, 'initial_T', 25);
% 
%         E_cap_nom = state.C_nom * state.V_nom;
% 
%         state.Deg = deg_model_init( ...
%             E_cap_nom, ...
%             must(params, 'cap_floor_frac', 0.8));
% 
%         out = struct();
%         return;
%     end
% 
%     if ~strcmp(mode, 'run')
%         error('Unknown mode. Use ''init'' or ''run''.');
%     end
% 
%     N = length(P_req_cell);
%     dt_s = dt_h * 3600;
%     T_amb_vec = must(params, 'T_vec', 25 * ones(1, N));
% 
%     out = struct();
%     out.Ut           = zeros(1, N);
%     out.I_cell       = zeros(1, N);
%     out.SOC          = zeros(1, N);
%     out.T_cell       = zeros(1, N);
%     out.E_stored     = zeros(1, N);
%     out.E_discharged = zeros(1, N);
%     out.E_loss_joule = zeros(1, N);
%     out.E_loss_sat   = zeros(1, N);
%     out.E_loss_empty = zeros(1, N);
%     out.SOH          = zeros(1, N);
% 
%     soc_trace     = zeros(1, N + 1);
%     temp_trace    = zeros(1, N);
%     current_trace = zeros(1, N);
% 
%     curr_SOC  = state.SOC;
%     curr_T    = state.T_cell;
%     deg_state = state.Deg;
% 
%     soc_trace(1) = curr_SOC;
% 
%     for k = 1:N
%         C_act_Ah = state.C_nom * max(deg_state.SOH, 1e-9);
%         Voc_k    = LfpCellVoc(curr_SOC * 100, curr_T);
%         R0_k     = LfpCellR0(curr_SOC * 100, curr_T) / max(deg_state.SOH, 1e-9);
% 
%         P_k = P_req_cell(k);
%         discriminant = Voc_k^2 - 4 * R0_k * P_k;
% 
%         if discriminant < 0
%             I_actual = Voc_k / (2 * R0_k);
%         else
%             I_actual = (Voc_k - sqrt(discriminant)) / (2 * R0_k);
%         end
% 
%         e_loss_sat = 0;
%         e_loss_empty = 0;
% 
%         eta_c = 1.0;
%         if I_actual < 0
%             eta_c = 0.985;
%         end
% 
%         dAh_req = (I_actual * dt_s / 3600) * eta_c;
%         potential_SOC = curr_SOC - (dAh_req / max(C_act_Ah, 1e-9));
% 
%         if potential_SOC > SOC_MAX
%             dAh_allowed = (curr_SOC - SOC_MAX) * C_act_Ah;
%             I_actual = (dAh_allowed * 3600 / dt_s) / eta_c;
%             e_loss_sat = abs(P_k - (Voc_k - I_actual * R0_k) * I_actual) * dt_h;
% 
%         elseif potential_SOC < SOC_MIN
%             dAh_allowed = (curr_SOC - SOC_MIN) * C_act_Ah;
%             I_actual = (dAh_allowed * 3600 / dt_s) / eta_c;
%             e_loss_empty = abs(P_k - (Voc_k - I_actual * R0_k) * I_actual) * dt_h;
%         end
% 
%         ut_k = Voc_k - I_actual * R0_k;
%         p_loss_joule = I_actual^2 * R0_k;
% 
%         q_conv = (curr_T - T_amb_vec(k)) / R_TH;
%         curr_T = curr_T + ((p_loss_joule - q_conv) / C_TH) * dt_s;
% 
%         p_term = ut_k * I_actual;
%         if I_actual > 0
%             out.E_discharged(k) = p_term * dt_h;
%             out.E_stored(k) = 0;
%         else
%             out.E_discharged(k) = 0;
%             out.E_stored(k) = abs(p_term * dt_h);
%         end
% 
%         dSOC_actual = (I_actual * dt_s / (max(C_act_Ah, 1e-9) * 3600)) * eta_c;
%         curr_SOC = curr_SOC - dSOC_actual;
%         curr_SOC = min(max(curr_SOC, 0), 1);
% 
%         soc_trace(k + 1) = curr_SOC;
%         temp_trace(k) = curr_T;
%         current_trace(k) = I_actual;
% 
%         out.Ut(k)           = ut_k;
%         out.I_cell(k)       = I_actual;
%         out.SOC(k)          = curr_SOC;
%         out.T_cell(k)       = curr_T;
%         out.E_loss_joule(k) = p_loss_joule * dt_h;
%         out.E_loss_sat(k)   = e_loss_sat;
%         out.E_loss_empty(k) = e_loss_empty;
%     end
% 
%     % ------------------------------------------------------------
%     % DEGRADÁCIÓ: csak a teljes összefüggő batch végén
%     % ------------------------------------------------------------
%     deg_before = deg_state;
%     deg_state = deg_model_apply_batch_xu( ...
%         deg_state, soc_trace, temp_trace, current_trace, dt_h, state.C_nom);
% 
%     out.SOH(:) = deg_state.SOH;
% 
%     out.deg_info = struct();
%     out.deg_info.FD_before = deg_before.FD;
%     out.deg_info.FD_after  = deg_state.FD;
%     out.deg_info.dFD       = deg_state.FD - deg_before.FD;
%     out.deg_info.SOH_before = deg_before.SOH;
%     out.deg_info.SOH_after  = deg_state.SOH;
%     out.deg_info.dSOH       = deg_before.SOH - deg_state.SOH;
%     out.deg_info.sum_cycle_before = deg_before.sum_cycle;
%     out.deg_info.sum_cycle_after  = deg_state.sum_cycle;
%     out.deg_info.sum_cal_before   = deg_before.sum_cal;
%     out.deg_info.sum_cal_after    = deg_state.sum_cal;
% 
%     state.SOC    = curr_SOC;
%     state.T_cell = curr_T;
%     state.Deg    = deg_state;
% end
% % function [out, state] = lfp_cell(P_req_cell, mode, params, dt_h, state)
% %     % LFP_CELL - Teljesítmény-alapú ECM + Hőmodell + Korlátok
% %     % P_req_cell: Kért teljesítmény [W] (Negatív: töltés, Pozitív: kisütés)
% %     % mode: 'init' vagy 'run'
% %     % params: Struktúra (C_nom_Ah, initial_soc, T_vec [környezeti], stb.)
% % 
% %     % --- Bolun Xu (2018) Termikus paraméterek ---
% %     M_CELL = 5.4;           % [kg]
% %     CP     = 1100;          % [J/kgK]
% %     C_TH   = M_CELL * CP;   % [J/K]
% %     R_TH   = 4.0;           % [K/W]
% % 
% %     % --- Üzemeltetési tartomány (BESS standard) ---
% %     SOC_MIN = 0.20;
% %     SOC_MAX = 0.80;
% % 
% %     if strcmp(mode, 'init')
% %         % ==========================================
% %         % INICIALIZÁLÁS
% %         % ==========================================
% %         state = struct();
% %         state.C_nom    = must(params, 'C_nom_Ah', 280); 
% %         state.V_nom    = must(params, 'V_nom', 3.2);
% %         state.SOC      = must(params, 'initial_soc', 0.5);
% %         state.T_cell   = must(params, 'initial_T', 25);
% % 
% %         E_cap_nom      = state.C_nom * state.V_nom;
% %         state.Deg      = deg_model_init(E_cap_nom, must(params, 'cap_floor_frac', 0.8));
% %         out = struct(); return;
% % 
% %     elseif strcmp(mode, 'run')
% %         % ==========================================
% %         % SZIMULÁCIÓ (Teljesítmény vezérelt)
% %         % ==========================================
% %         N = length(P_req_cell);
% %         dt_s = dt_h * 3600; 
% %         T_amb_vec = must(params, 'T_vec', 25 * ones(1, N)); 
% % 
% %         % Preallokáció
% %         out.Ut = zeros(1,N); out.I_cell = zeros(1,N); out.SOC = zeros(1,N);
% %         out.T_cell = zeros(1,N); out.E_stored = zeros(1,N);
% %         out.E_discharged = zeros(1,N); out.E_loss_joule = zeros(1,N);
% %         out.E_loss_sat = zeros(1,N); out.E_loss_empty = zeros(1,N);
% % 
% %         curr_SOC  = state.SOC;
% %         curr_T    = state.T_cell; 
% %         deg_state = state.Deg;
% % 
% %         for k = 1:N
% %             % 1. Fizikai paraméterek lekérése
% %             C_act_Ah = state.C_nom * deg_state.SOH;
% %             Voc_k = LfpCellVoc(curr_SOC * 100, curr_T); 
% %             R0_k  = LfpCellR0(curr_SOC * 100, curr_T) / deg_state.SOH;
% % 
% %             % 2. Áram visszaszámítása a teljesítményből (Másodfokú megoldó)
% %             % P = (Voc - I*R0) * I  => R0*I^2 - Voc*I + P = 0
% %             P_k = P_req_cell(k);
% %             discriminant = Voc_k^2 - 4 * R0_k * P_k;
% % 
% %             if discriminant < 0
% %                 % Ha túl nagy a kért P, csak a fizikai maximumot adjuk le
% %                 I_actual = Voc_k / (2 * R0_k);
% %             else
% %                 % A kisebb gyök felel meg a stabil üzemi tartománynak
% %                 I_actual = (Voc_k - sqrt(discriminant)) / (2 * R0_k);
% %             end
% % 
% %             % 3. Korlátozások (20-80% SOC ablak)
% %             e_loss_sat = 0; e_loss_empty = 0;
% %             eta_c = 1.0; if I_actual < 0, eta_c = 0.985; end % Coulomb-eff.
% % 
% %             dAh_req = (I_actual * dt_s / 3600) * eta_c;
% %             potential_SOC = curr_SOC - (dAh_req / C_act_Ah);
% % 
% %             if potential_SOC > SOC_MAX
% %                 dAh_allowed = (curr_SOC - SOC_MAX) * C_act_Ah;
% %                 I_actual = (dAh_allowed * 3600 / dt_s) / eta_c;
% %                 e_loss_sat = abs(P_k - (Voc_k - I_actual*R0_k)*I_actual) * dt_h;
% %             elseif potential_SOC < SOC_MIN
% %                 dAh_allowed = (curr_SOC - SOC_MIN) * C_act_Ah;
% %                 I_actual = (dAh_allowed * 3600 / dt_s) / eta_c;
% %                 e_loss_empty = abs(P_k - (Voc_k - I_actual*R0_k)*I_actual) * dt_h;
% %             end
% % 
% %             % 4. Újrakalkulált kapocsfeszültség és Joule-hő
% %             ut_k = Voc_k - I_actual * R0_k;
% %             p_loss_joule = I_actual^2 * R0_k;
% % 
% %             % 5. Termikus frissítés (Bolun Xu)
% %             q_conv = (curr_T - T_amb_vec(k)) / R_TH;
% %             curr_T = curr_T + ((p_loss_joule - q_conv) / C_TH) * dt_s;
% % 
% %             % 6. Energetikai mérleg
% %             p_term = ut_k * I_actual;
% %             if I_actual > 0
% %                 out.E_discharged(k) = p_term * dt_h;
% %                 out.E_stored(k) = 0;
% %             else
% %                 out.E_discharged(k) = 0;
% %                 out.E_stored(k) = abs(p_term * dt_h);
% %             end
% % 
% %             % 7. Állapot frissítés
% %             dSOC_actual = (I_actual * dt_s / (C_act_Ah * 3600)) * eta_c;
% %             curr_SOC = curr_SOC - dSOC_actual;
% %             [deg_state, ~] = deg_model_step(deg_state, abs(dSOC_actual), curr_SOC, dt_h, curr_T);
% % 
% %             % Mentés
% %             out.Ut(k)           = ut_k;
% %             out.I_cell(k)       = I_actual;
% %             out.SOC(k)          = curr_SOC;
% %             out.T_cell(k)       = curr_T;
% %             out.E_loss_joule(k) = p_loss_joule * dt_h;
% %             out.E_loss_sat(k)   = e_loss_sat;
% %             out.E_loss_empty(k) = e_loss_empty;
% %             out.SOH(k)          = deg_state.SOH;
% %         end
% % 
% %         state.SOC = curr_SOC; state.T_cell = curr_T; state.Deg = deg_state;
% %     end
% % end
% 
% function Deg = deg_model_init(E_cap_nom, cap_floor_frac)
%     Deg = struct();
% 
%     Deg.sum_cycle = 0;
%     Deg.sum_cal   = 0;
%     Deg.FD        = 0;
%     Deg.SOH       = 1;
% 
%     Deg.E_cap_nom = E_cap_nom;
%     Deg.cap_floor = cap_floor_frac;
% 
%     Deg.fdod_a = 1.4e5;
%     Deg.fdod_b = -0.501;
%     Deg.fdod_c = -1.23e5;
% 
%     Deg.alpha_soc_cyc = 1.04;
%     Deg.alpha_T_cyc   = 0.0693;
%     Deg.alpha_C       = 0.263;
% 
%     Deg.alpha_soc_cal = 1.04;
%     Deg.alpha_T_cal   = 0.0693;
%     Deg.k_cal_ref_per_day = 2.7e-5;
% 
%     Deg.mix_beta = 121;
%     Deg.mix_w    = 0.0575;
% end
% 
% 
% function Deg = deg_model_apply_batch_xu(Deg, soc_trace, temp_trace, current_trace, dt_h, C_nom_Ah)
%     if isempty(soc_trace) || numel(soc_trace) < 2
%         Deg = deg_model_finalize_soh(Deg);
%         return;
%     end
% 
%     soc_mean_batch = mean(0.5 * (soc_trace(1:end-1) + soc_trace(2:end)));
%     T_mean_batch   = mean(temp_trace);
%     dt_total_h     = (numel(soc_trace) - 1) * dt_h;
% 
%     Deg = deg_model_calendar_batch_step(Deg, dt_total_h, soc_mean_batch, T_mean_batch);
% 
%     [ranges, means, counts, start_idx, end_idx] = xu_rainflow_cycles_builtin(soc_trace);
% 
%     for i = 1:numel(ranges)
%         dod      = max(ranges(i), 1e-6);
%         soc_mean = means(i);
%         count    = counts(i);
% 
%         if ~isnan(start_idx(i)) && ~isnan(end_idx(i))
%             s = max(1, min(numel(temp_trace), floor(start_idx(i))));
%             e = max(1, min(numel(temp_trace), ceil(end_idx(i))));
%             if e < s
%                 tmp = s; s = e; e = tmp;
%             end
% 
%             T_cycle = mean(temp_trace(s:e));
%             crate_mean = mean(abs(current_trace(s:e))) / max(C_nom_Ah, 1e-9);
%         else
%             T_cycle = T_mean_batch;
%             crate_mean = mean(abs(current_trace)) / max(C_nom_Ah, 1e-9);
%         end
% 
%         FT   = exp(Deg.alpha_T_cyc * (T_cycle - 25));
%         FSOC = exp(Deg.alpha_soc_cyc * (soc_mean - 0.5));
%         FC   = exp(Deg.alpha_C * (crate_mean - 1.0));
% 
%         denom = Deg.fdod_a * (dod ^ Deg.fdod_b) + Deg.fdod_c;
%         FDOD  = 1 / max(denom, 1e-12);
% 
%         FCYC_inc = count * FDOD * FSOC * FT * FC * dod;
%         Deg.sum_cycle = Deg.sum_cycle + FCYC_inc;
%     end
% 
%     Deg = deg_model_finalize_soh(Deg);
% end
% 
% function Deg = deg_model_calendar_batch_step(Deg, dt_total_h, soc_mean, T_C)
%     dt_day = dt_total_h / 24;
% 
%     FT   = exp(Deg.alpha_T_cal * (T_C - 25));
%     FSOC = exp(Deg.alpha_soc_cal * (soc_mean - 0.5));
% 
%     FCAL_inc = Deg.k_cal_ref_per_day * dt_day * FSOC * FT;
%     Deg.sum_cal = Deg.sum_cal + FCAL_inc;
% end
% 
% function Deg = deg_model_finalize_soh(Deg)
%     Deg.FD = Deg.sum_cycle + Deg.sum_cal;
% 
%     SOH = Deg.mix_w * exp(-Deg.mix_beta * Deg.FD) + ...
%           (1 - Deg.mix_w) * exp(-Deg.FD);
% 
%     Deg.SOH = min(1, max(0, SOH));
% end
% 
% function [ranges, means, counts, start_idx, end_idx] = xu_rainflow_cycles_builtin(sig)
%     try
%         rf = rainflow(sig);
% 
%         if istable(rf)
%             ranges = rf.Range(:).';
%             means  = rf.Mean(:).';
%             counts = rf.Count(:).';
% 
%             if all(ismember({'Start','End'}, rf.Properties.VariableNames))
%                 start_idx = rf.Start(:).';
%                 end_idx   = rf.End(:).';
%             else
%                 start_idx = nan(size(ranges));
%                 end_idx   = nan(size(ranges));
%             end
%         else
%             counts = rf(:,1).';
%             ranges = rf(:,2).';
%             means  = rf(:,3).';
% 
%             if size(rf,2) >= 5
%                 start_idx = rf(:,4).';
%                 end_idx   = rf(:,5).';
%             else
%                 start_idx = nan(size(ranges));
%                 end_idx = nan(size(ranges));
%             end
%         end
% 
%     catch
%         tp = turning_points(sig);
% 
%         if numel(tp) < 2
%             ranges = [];
%             means = [];
%             counts = [];
%             start_idx = [];
%             end_idx = [];
%             return;
%         end
% 
%         ranges = abs(diff(tp));
%         means = 0.5 * (tp(1:end-1) + tp(2:end));
%         counts = 0.5 * ones(size(ranges));
%         start_idx = nan(size(ranges));
%         end_idx = nan(size(ranges));
%     end
% end
% 
% function tp = turning_points(sig)
%     sig = sig(:).';
% 
%     if isempty(sig)
%         tp = [];
%         return;
%     end
% 
%     keep = [true, abs(diff(sig)) > 1e-12];
%     x = sig(keep);
% 
%     if numel(x) <= 2
%         tp = x;
%         return;
%     end
% 
%     tp = x(1);
%     for i = 2:(numel(x)-1)
%         d1 = x(i) - x(i-1);
%         d2 = x(i+1) - x(i);
%         if sign(d1) ~= sign(d2)
%             tp(end+1) = x(i); %#ok<AGROW>
%         end
%     end
%     tp(end+1) = x(end);
% end
% 
% function [Deg, out] = deg_model_step(Deg, dSoC, SOC_mean, dt_h, T_C)
% % Kiszámítja a degradációt a C-rate közvetlen hatása nélkül.
% % A magas áram hatása a T_C bemeneti paraméter megváltozásában tükröződik.
% 
%     % --- 1. Stressz Faktorok ---
%     DOD_s = max(dSoC, 1e-6); 
% 
%     % Hőmérsékleti faktor (T_C tartalmazza a C-rate okozta melegedést)
%     FT = exp(Deg.alpha_T * (T_C - 25)); 
% 
%     % SOC faktor
%     FSOC = exp(Deg.alpha_soc * (SOC_mean - 0.5));
% 
%     % DoD faktor (Ciklusmélység)
%     denom = (Deg.fdod_a * (DOD_s.^Deg.fdod_b) + Deg.fdod_c);
%     FDOD  = 1 ./ max(denom, 1e-12);
% 
%     % --- 2. Inkrementumok ---
%     % Ciklikus: Most már csak DoD, SOC és Hőmérséklet alapú
%     FCYC_inc = FDOD .* FSOC .* FT .* DOD_s;
% 
%     % Kalendáris: Idő, SOC és Hőmérséklet alapú
%     FCAL_inc = Deg.k_cal * (dt_h * 60*60) * FSOC * FT;
% 
%     % --- 3. Felhalmozás és SOH ---
%     Deg.sum_cycle = Deg.sum_cycle + FCYC_inc;
%     Deg.cal_sum   = Deg.cal_sum   + FCAL_inc;
%     Deg.FD        = Deg.sum_cycle + Deg.cal_sum;
% 
%     % Két-exponenciális SOH formula
%     SOH = Deg.mix_w * exp(-Deg.mix_beta * Deg.FD) + (1 - Deg.mix_w) * exp(-Deg.FD);
%     Deg.SOH = max(0, min(1, SOH));
% 
%     E_cap_eff = max(Deg.cap_floor * Deg.E_cap_nom, Deg.SOH * Deg.E_cap_nom);
% 
%     % --- 4. Kimenet ---
%     out = struct();
%     out.SOH        = Deg.SOH;
%     out.E_cap_eff  = E_cap_eff;
%     out.sum_cycle  = Deg.sum_cycle;
%     out.cal_sum    = Deg.cal_sum;
%     out.FD         = Deg.FD;
% end
% 
% function v = must(s, field, defaultVal), if isfield(s, field), v = s.(field); else, v = defaultVal; end, end
% 
% function Voc = LfpCellVoc(SoC, Temp)
%     % LFPCELLVOC Kiszámítja a nyitott áramköri feszültséget (Voc) 
%     % A tengelyek szigorúan növekvő (ascending) sorrendben vannak a griddedInterpolant miatt!
% 
%     persistent F;
% 
%     if isempty(F)
%         % NÖVEKVŐ TENGELYEK
%         soc_axis = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100]';
%         temp_axis = [-20, -10, 0, 10, 25, 35, 45];
% 
%         % Adatmátrix (Lookup Table)
%         % A mátrix sorai MEGFORDÍTVA, hogy kövessék a 0 -> 100% SoC növekedést!
%         voc_table = [
%             2.000, 2.000, 2.000, 2.000, 2.000, 2.000, 2.000; % 0%
%             2.955, 2.965, 2.980, 2.990, 3.000, 3.002, 3.005; % 5%
%             3.165, 3.175, 3.185, 3.195, 3.200, 3.201, 3.202; % 10%
%             3.205, 3.215, 3.225, 3.235, 3.240, 3.241, 3.242; % 15%
%             3.235, 3.245, 3.255, 3.265, 3.270, 3.271, 3.272; % 20%
%             3.250, 3.260, 3.270, 3.276, 3.280, 3.280, 3.281; % 25%
%             3.260, 3.270, 3.280, 3.286, 3.290, 3.290, 3.291; % 30%
%             3.265, 3.275, 3.285, 3.291, 3.295, 3.295, 3.296; % 35%
%             3.270, 3.280, 3.290, 3.296, 3.300, 3.300, 3.301; % 40%
%             3.275, 3.285, 3.295, 3.301, 3.305, 3.305, 3.306; % 45%
%             3.280, 3.290, 3.300, 3.306, 3.310, 3.310, 3.311; % 50%
%             3.282, 3.292, 3.302, 3.308, 3.312, 3.312, 3.313; % 55%
%             3.284, 3.294, 3.304, 3.310, 3.315, 3.315, 3.316; % 60%
%             3.287, 3.297, 3.307, 3.313, 3.318, 3.318, 3.319; % 65%
%             3.290, 3.300, 3.310, 3.316, 3.320, 3.320, 3.321; % 70%
%             3.292, 3.302, 3.312, 3.318, 3.322, 3.322, 3.323; % 75%
%             3.295, 3.305, 3.315, 3.321, 3.325, 3.325, 3.326; % 80%
%             3.298, 3.308, 3.318, 3.323, 3.327, 3.327, 3.328; % 85%
%             3.300, 3.310, 3.320, 3.325, 3.330, 3.330, 3.331; % 90%
%             3.325, 3.332, 3.338, 3.345, 3.350, 3.351, 3.352; % 95%
%             3.520, 3.545, 3.570, 3.585, 3.600, 3.600, 3.600  % 100%
%         ];
% 
%         F = griddedInterpolant({soc_axis, temp_axis}, voc_table, 'linear');
%     end
% 
%     Voc = F(SoC, Temp);
% end
% 
% function R0 = LfpCellR0(SoC, Temp)
%     % LFPCELLR0 - Belső ellenállás kikeresése (Ohm)
%     % A tengelyek szigorúan növekvő (ascending) sorrendben vannak a griddedInterpolant miatt!
% 
%     persistent F_r0;
% 
%     if isempty(F_r0)
%         % NÖVEKVŐ TENGELYEK
%         soc_axis = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100]';
%         temp_axis = [-20, -10, 0, 10, 25, 35, 45];
% 
%         % DUMMY LFP ADATOK (Ohm-ban megadva, 280Ah cellára)
%         % A mátrix sorai MEGFORDÍTVA, hogy kövessék a 0 -> 100% SoC növekedést!
%         base_r0 = [
%             0.0150, 0.0120, 0.0090, 0.0075, 0.0060, 0.0055, 0.0050; % 0%
%             0.0090, 0.0075, 0.0060, 0.0050, 0.0042, 0.0038, 0.0035; % 5%
%             0.0060, 0.0050, 0.0040, 0.0032, 0.0028, 0.0025, 0.0023; % 10%
%             0.0045, 0.0038, 0.0030, 0.0025, 0.0020, 0.0018, 0.0016; % 15%
%             0.0035, 0.0028, 0.0022, 0.0018, 0.0015, 0.0014, 0.0013; % 20%
%             0.0030, 0.0025, 0.0019, 0.0015, 0.0012, 0.0011, 0.0010; % 25%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 30%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 35%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 40%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 45%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 50%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 55%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 60%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 65%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 70%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 75%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 80%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 85%
%             0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009; % 90%
%             0.0030, 0.0025, 0.0019, 0.0015, 0.0012, 0.0011, 0.0010; % 95%
%             0.0035, 0.0028, 0.0022, 0.0018, 0.0015, 0.0014, 0.0013  % 100%
%         ];
% 
%         F_r0 = griddedInterpolant({soc_axis, temp_axis}, base_r0, 'linear');
%     end
% 
%     R0 = F_r0(SoC, Temp);
% end
% 

function [out, state] = lfp_cell(P_req_cell, mode, params, dt_h, state)
    % LFP_CELL - Teljesítmény-alapú ECM + Hőmodell + Batch degradáció
    % P_req_cell: Kért teljesítmény [W] (Negatív: töltés, Pozitív: kisütés)
    % mode: 'init' vagy 'run'
    % params: Struktúra (C_nom_Ah, initial_soc, T_vec, stb.)
    %
    % FONTOS:
    % - az ECM, SoC és hőmodell időlépésenként fut
    % - a degradáció batch végén fut
    % - a ciklikus rész rainflow cycle counting alapján számolódik
    % - a naptári rész újrakalibrált marad

    % --- Bolun Xu (2018) Termikus paraméterek ---
    M_CELL = 5.4;           % [kg]
    CP     = 1100;          % [J/kgK]
    C_TH   = M_CELL * CP;   % [J/K]
    R_TH   = 4.0;           % [K/W]

    % --- Üzemeltetési tartomány ---
    SOC_MIN = must(params, 'SOC_MIN', 0.20);
    SOC_MAX = must(params, 'SOC_MAX', 0.80);

    if strcmp(mode, 'init')
        state = struct();
        state.C_nom    = must(params, 'C_nom_Ah', 280);
        state.V_nom    = must(params, 'V_nom', 3.2);
        state.SOC      = must(params, 'initial_soc', 0.5);
        state.T_cell   = must(params, 'initial_T', 25);

        E_cap_nom = state.C_nom * state.V_nom;

        state.Deg = deg_model_init( ...
            E_cap_nom, ...
            must(params, 'cap_floor_frac', 0.8));

        out = struct();
        return;

    elseif strcmp(mode, 'run')
        N = length(P_req_cell);
        dt_s = dt_h * 3600;
        T_amb_vec = must(params, 'T_vec', 25 * ones(1, N));
        force_const_cell_T = must(params, 'force_const_cell_T', false);

        out.Ut = zeros(1,N);
        out.I_cell = zeros(1,N);
        out.SOC = zeros(1,N);
        out.T_cell = zeros(1,N);
        out.E_stored = zeros(1,N);
        out.E_discharged = zeros(1,N);
        out.E_loss_joule = zeros(1,N);
        out.E_loss_sat = zeros(1,N);
        out.E_loss_empty = zeros(1,N);
        out.SOH = zeros(1,N);

        soc_trace = zeros(1, N+1);
        temp_trace = zeros(1, N);
        current_trace = zeros(1, N);

        curr_SOC  = state.SOC;
        curr_T    = state.T_cell;
        deg_state = state.Deg;

        soc_trace(1) = curr_SOC;

        for k = 1:N
            C_act_Ah = state.C_nom * deg_state.SOH;
            Voc_k = LfpCellVoc(curr_SOC * 100, curr_T);
            R0_k  = LfpCellR0(curr_SOC * 100, curr_T) / max(deg_state.SOH, 1e-6);

            % P = (Voc - I*R0)*I => R0*I^2 - Voc*I + P = 0
            P_k = P_req_cell(k);
            discriminant = Voc_k^2 - 4 * R0_k * P_k;

            if discriminant < 0
                I_actual = Voc_k / (2 * R0_k);
            else
                I_actual = (Voc_k - sqrt(discriminant)) / (2 * R0_k);
            end

            e_loss_sat = 0;
            e_loss_empty = 0;

            eta_c = 1.0;
            if I_actual < 0
                eta_c = 0.985;
            end

            dAh_req = (I_actual * dt_s / 3600) * eta_c;
            potential_SOC = curr_SOC - (dAh_req / max(C_act_Ah, 1e-9));

            if potential_SOC > SOC_MAX
                dAh_allowed = (curr_SOC - SOC_MAX) * C_act_Ah;
                I_actual = (dAh_allowed * 3600 / dt_s) / eta_c;
                e_loss_sat = abs(P_k - (Voc_k - I_actual * R0_k) * I_actual) * dt_h;

            elseif potential_SOC < SOC_MIN
                dAh_allowed = (curr_SOC - SOC_MIN) * C_act_Ah;
                I_actual = (dAh_allowed * 3600 / dt_s) / eta_c;
                e_loss_empty = abs(P_k - (Voc_k - I_actual * R0_k) * I_actual) * dt_h;
            end

            ut_k = Voc_k - I_actual * R0_k;
            p_loss_joule = I_actual^2 * R0_k;

            % q_conv = (curr_T - T_amb_vec(k)) / R_TH;
            % curr_T = curr_T + ((p_loss_joule - q_conv) / C_TH) * dt_s;

            if force_const_cell_T
                % Validation mode:
                % keep cell temperature fixed at the prescribed test temperature.
                curr_T = T_amb_vec(k);
            else
                % Normal electro-thermal simulation:
                q_conv = (curr_T - T_amb_vec(k)) / R_TH;
                curr_T = curr_T + ((p_loss_joule - q_conv) / C_TH) * dt_s;
            end

            p_term = ut_k * I_actual;
            if I_actual > 0
                out.E_discharged(k) = p_term * dt_h;
                out.E_stored(k) = 0;
            else
                out.E_discharged(k) = 0;
                out.E_stored(k) = abs(p_term * dt_h);
            end

            dSOC_actual = (I_actual * dt_s / (max(C_act_Ah, 1e-9) * 3600)) * eta_c;
            curr_SOC = curr_SOC - dSOC_actual;
            curr_SOC = min(max(curr_SOC, 0), 1);

            soc_trace(k+1) = curr_SOC;
            temp_trace(k) = curr_T;
            current_trace(k) = I_actual;

            out.Ut(k)           = ut_k;
            out.I_cell(k)       = I_actual;
            out.SOC(k)          = curr_SOC;
            out.T_cell(k)       = curr_T;
            out.E_loss_joule(k) = p_loss_joule * dt_h;
            out.E_loss_sat(k)   = e_loss_sat;
            out.E_loss_empty(k) = e_loss_empty;
        end

        deg_state = deg_model_apply_batch_xu( ...
            deg_state, soc_trace, temp_trace, current_trace, dt_h, state.C_nom);

        out.SOH(:) = deg_state.SOH;

        state.SOC = curr_SOC;
        state.T_cell = curr_T;
        state.Deg = deg_state;
    else
        error('Unknown mode. Use ''init'' or ''run''.');
    end
end


function Deg = deg_model_init(E_cap_nom, cap_floor_frac)
    Deg = struct();

    % --- Állapotváltozók ---
    Deg.sum_cycle = 0;
    Deg.sum_cal   = 0;
    Deg.FD        = 0;
    Deg.SOH       = 1;

    % Deg.cycle_stress_scale = 0.67;
    Deg.cycle_stress_scale = 0.83;
    Deg.calendar_stress_scale = 2.65;

    % --- Rendszer paraméterek ---
    Deg.E_cap_nom = E_cap_nom;
    Deg.cap_floor = cap_floor_frac;

    % --- Xu-féle ciklikus stressz faktorok ---
    Deg.fdod_a = 1.4e5;
    Deg.fdod_b = -0.501;
    Deg.fdod_c = -1.23e5;

    Deg.alpha_soc_cyc = 1.04;
    Deg.alpha_T_cyc   = 0.0693;
    Deg.alpha_C       = 0.263;

    % --- Naptári rész ---
    Deg.alpha_soc_cal = 1.04;
    Deg.alpha_T_cal   = 0.0693;

    % Naptári újrakalibrálás marad
    Deg.k_cal_ref_per_day = 2.7e-5;

    % --- FD -> SOH leképezés ---
    % Deg.mix_beta  = 121;
    % Deg.mix_w     = 0.0575;

    Deg.mix_beta  = 60;
    Deg.mix_w     = 0.020;
    
    %batchek kozotti atmenetekhez eltaroljuk a felciklusokat kovetkezo
    %batchnek
    Deg.pending_soc     = [];
    Deg.pending_temp    = [];
    Deg.pending_current = [];

    % Minimum cycle depth to avoid counting numerical noise
    Deg.min_dod = 0.005;   % 0.5% SoC

    Deg.debug_cycle_count_total = 0;
    Deg.debug_dod_weighted_sum = 0;
    Deg.debug_soc_weighted_sum = 0;
end


% function Deg = deg_model_apply_batch_xu(Deg, soc_trace, temp_trace, current_trace, dt_h, C_nom_Ah)
%     if isempty(soc_trace) || numel(soc_trace) < 2
%         Deg = deg_model_finalize_soh(Deg);
%         return;
%     end
% 
%     % -------------------------------------------------
%     % 1) Naptári öregedés
%     % -------------------------------------------------
%     soc_mean_batch = mean(0.5 * (soc_trace(1:end-1) + soc_trace(2:end)));
%     T_mean_batch = mean(temp_trace);
%     dt_total_h = (numel(soc_trace)-1) * dt_h;
% 
%     Deg = deg_model_calendar_batch_step(Deg, dt_total_h, soc_mean_batch, T_mean_batch);
% 
%     % -------------------------------------------------
%     % 2) Ciklikus öregedés - rainflow a teljes SoC-profilon
%     % -------------------------------------------------
%     [ranges, means, counts, start_idx, end_idx] = xu_rainflow_cycles_builtin(soc_trace);
% 
%     for i = 1:numel(ranges)
%         dod = max(ranges(i), 1e-6);
%         soc_mean = means(i);
%         count = counts(i);
% 
%         % ciklusonkenti atlaghomerseklet es atlagos C-rate
%         if ~isnan(start_idx(i)) && ~isnan(end_idx(i))
%             s = max(1, min(numel(temp_trace), floor(start_idx(i))));
%             e = max(1, min(numel(temp_trace), ceil(end_idx(i))));
%             if e < s
%                 tmp = s; s = e; e = tmp;
%             end
% 
%             T_cycle = mean(temp_trace(s:e));
%             crate_mean = mean(abs(current_trace(s:e))) / max(C_nom_Ah, 1e-9);
%         else
%             T_cycle = T_mean_batch;
%             crate_mean = mean(abs(current_trace)) / max(C_nom_Ah, 1e-9);
%         end
% 
%         FT   = exp(Deg.alpha_T_cyc * (T_cycle - 25));
%         FSOC = exp(Deg.alpha_soc_cyc * (soc_mean - 0.5));
%         FC   = exp(Deg.alpha_C * (crate_mean - 1.0));
% 
%         denom = Deg.fdod_a * (dod ^ Deg.fdod_b) + Deg.fdod_c;
%         FDOD  = 1 / max(denom, 1e-12);
% 
%         FCYC_inc = count * FDOD * FSOC * FT * FC ;
%         Deg.sum_cycle = Deg.sum_cycle + FCYC_inc;
%     end
% 
%     Deg = deg_model_finalize_soh(Deg);
% end

function idx = last_tail_start_index(sig)
% LAST_TAIL_START_INDEX
% Returns the start index of the last monotonic tail of the SoC profile.
%
% Example:
%   [0.2 0.8]           -> idx = 1
%   [0.2 0.8 0.2]       -> idx = 2
%   [0.2 0.8 0.2 0.6]   -> idx = 3
%
% The segment sig(idx:end) is carried to the next batch.

    sig = sig(:).';

    if numel(sig) <= 2
        idx = 1;
        return;
    end

    % Remove tiny repeated movements for sign detection
    d = diff(sig);

    last_nonzero = find(abs(d) > 1e-12, 1, 'last');

    if isempty(last_nonzero)
        idx = 1;
        return;
    end

    last_sign = sign(d(last_nonzero));

    idx = last_nonzero;

    for k = last_nonzero-1:-1:1
        if abs(d(k)) <= 1e-12
            idx = k;
            continue;
        end

        if sign(d(k)) == last_sign
            idx = k;
        else
            break;
        end
    end
end

function Deg = deg_model_apply_batch_xu(Deg, soc_trace, temp_trace, current_trace, dt_h, C_nom_Ah)

    is_final_batch = false;

    if isempty(soc_trace) || numel(soc_trace) < 2
        Deg = deg_model_finalize_soh(Deg);
        return;
    end

    soc_trace     = soc_trace(:).';
    temp_trace    = temp_trace(:).';
    current_trace = current_trace(:).';

    % -------------------------------------------------
    % 1) Calendar aging - timestep based, vectorized
    % -------------------------------------------------
    % Xu logika szerint a naptari oregedes idofuggo tag,
    % ahol a SoC es a homerseklet stresszfaktorkent szerepel.

    soc_mid = 0.5 * (soc_trace(1:end-1) + soc_trace(2:end));

    n_cal = min(numel(soc_mid), numel(temp_trace));
    soc_mid = soc_mid(1:n_cal);
    T_cal   = temp_trace(1:n_cal);

    dt_day = dt_h / 24;

    FSOC_cal = exp(Deg.alpha_soc_cal * (soc_mid - 0.5));
    FT_cal   = exp(Deg.alpha_T_cal   * (T_cal - 25));

    % FCAL_inc = Deg.k_cal_ref_per_day * dt_day * sum(FSOC_cal .* FT_cal);
    % Deg.sum_cal = Deg.sum_cal + FCAL_inc;

    FCAL_inc = Deg.calendar_stress_scale * ...
           Deg.k_cal_ref_per_day * dt_day * sum(FSOC_cal .* FT_cal);

    Deg.sum_cal = Deg.sum_cal + FCAL_inc;

    % -------------------------------------------------
    % 2) Prepend previous pending tail
    % -------------------------------------------------
    % A pending tail az elozo batch utolso monoton SoC-szakasza.
    % Ha folytatodik, nagyobb DoD lesz belole.
    % Ha megfordul, a rainflow felcikluskent/cikluskent szamolja.

    if isfield(Deg, 'pending_soc') && numel(Deg.pending_soc) >= 2 && ...
            abs(Deg.pending_soc(end) - soc_trace(1)) < 1e-9

        soc_rf     = [Deg.pending_soc, soc_trace(2:end)];
        temp_rf    = [Deg.pending_temp, temp_trace];
        current_rf = [Deg.pending_current, current_trace];

    else
        soc_rf     = soc_trace;
        temp_rf    = temp_trace;
        current_rf = current_trace;

        Deg.pending_soc     = [];
        Deg.pending_temp    = [];
        Deg.pending_current = [];
    end

    % Safety alignment
    n_int = numel(soc_rf) - 1;
    temp_rf    = temp_rf(1:min(numel(temp_rf), n_int));
    current_rf = current_rf(1:min(numel(current_rf), n_int));

    % -------------------------------------------------
    % 3) Split off the last monotonic tail, except at final batch
    % -------------------------------------------------
    % Normal batch:
    %   - az utolso monoton tail-t nem szamoljuk el most
    %   - elmentjuk a kovetkezo batch-hez
    %
    % Final batch:
    %   - mindent elszamolunk
    %   - pending torlodik

    if is_final_batch
        soc_count     = soc_rf;
        temp_count    = temp_rf;
        current_count = current_rf;

        Deg.pending_soc     = [];
        Deg.pending_temp    = [];
        Deg.pending_current = [];
    else
        tail_start = last_tail_start_index(soc_rf);

        soc_count = soc_rf(1:tail_start);

        n_count_int = max(0, numel(soc_count) - 1);
        temp_count    = temp_rf(1:min(numel(temp_rf), n_count_int));
        current_count = current_rf(1:min(numel(current_rf), n_count_int));

        % Store tail for next batch
        Deg.pending_soc = soc_rf(tail_start:end);

        t1 = tail_start;
        t2 = min(numel(temp_rf), numel(soc_rf) - 1);

        if t2 >= t1
            Deg.pending_temp    = temp_rf(t1:t2);
            Deg.pending_current = current_rf(t1:t2);
        else
            Deg.pending_temp    = [];
            Deg.pending_current = [];
        end

        % If the tail is numerically too small, do not carry it
        if numel(Deg.pending_soc) >= 2
            pending_range = max(Deg.pending_soc) - min(Deg.pending_soc);
            if isfield(Deg, 'min_dod') && pending_range < Deg.min_dod
                Deg.pending_soc     = [];
                Deg.pending_temp    = [];
                Deg.pending_current = [];
            end
        end
    end

    % -------------------------------------------------
    % 4) Cycle aging - rainflow only on the countable part
    % -------------------------------------------------
    [ranges, means, counts, start_idx, end_idx] = xu_rainflow_cycles_builtin(soc_count);

    if isempty(ranges)
        Deg = deg_model_finalize_soh(Deg);
        return;
    end

    T_mean_batch = mean(temp_trace);
    crate_mean_batch = mean(abs(current_trace)) / max(C_nom_Ah, 1e-9);

    for i = 1:numel(ranges)

        dod = max(ranges(i), 1e-6);

        if isfield(Deg, 'min_dod') && dod < Deg.min_dod
            continue;
        end

        soc_mean = means(i);
        count = counts(i);

        % Cycle-specific temperature and C-rate
        if ~isnan(start_idx(i)) && ~isnan(end_idx(i))

            a = min(round(start_idx(i)), round(end_idx(i)));
            b = max(round(start_idx(i)), round(end_idx(i)));

            s = max(1, min(numel(temp_count), a));
            e = max(1, min(numel(temp_count), b - 1));

            if e >= s
                T_cycle = mean(temp_count(s:e));
                crate_mean = mean(abs(current_count(s:e))) / max(C_nom_Ah, 1e-9);
            else
                T_cycle = T_mean_batch;
                crate_mean = crate_mean_batch;
            end
        else
            T_cycle = T_mean_batch;
            crate_mean = crate_mean_batch;
        end

        FT   = exp(Deg.alpha_T_cyc   * (T_cycle - 25));
        FSOC = exp(Deg.alpha_soc_cyc * (soc_mean - 0.5));
        FC   = exp(Deg.alpha_C       * (crate_mean - 1.0));

        denom = Deg.fdod_a * (dod ^ Deg.fdod_b) + Deg.fdod_c;
        FDOD  = 1 / max(denom, 1e-12);

        % DoD is already included through FDOD.
        FCYC_inc = Deg.cycle_stress_scale * count * FDOD * FSOC * FT * FC;

        Deg.sum_cycle = Deg.sum_cycle + FCYC_inc;
        Deg.debug_cycle_count_total = Deg.debug_cycle_count_total + count;
        Deg.debug_dod_weighted_sum = Deg.debug_dod_weighted_sum + count * dod;
        Deg.debug_soc_weighted_sum = Deg.debug_soc_weighted_sum + count * soc_mean;
    end
    if exist('ranges', 'var') && ~isempty(ranges)
        Deg.debug_last_dod_avg = mean(ranges);
        Deg.debug_last_mean_soc_avg = mean(means);
        Deg.debug_last_count_sum = sum(counts);
    else
        Deg.debug_last_dod_avg = NaN;
        Deg.debug_last_mean_soc_avg = NaN;
        Deg.debug_last_count_sum = 0;
    end

    Deg = deg_model_finalize_soh(Deg);
end



function Deg = deg_model_calendar_batch_step(Deg, dt_total_h, soc_mean, T_C)
    dt_day = dt_total_h / 24;

    FT   = exp(Deg.alpha_T_cal * (T_C - 25));
    FSOC = exp(Deg.alpha_soc_cal * (soc_mean - 0.5));

    FCAL_inc = Deg.k_cal_ref_per_day * dt_day * FSOC * FT;
    Deg.sum_cal = Deg.sum_cal + FCAL_inc;
end


function Deg = deg_model_finalize_soh(Deg)
    Deg.FD = Deg.sum_cycle + Deg.sum_cal;

    SOH = Deg.mix_w * exp(-Deg.mix_beta * Deg.FD) + ...
          (1 - Deg.mix_w) * exp(-Deg.FD);

    Deg.SOH = min(1, max(0, SOH));
end


function [ranges, means, counts, start_idx, end_idx] = xu_rainflow_cycles_builtin(sig)
% MATLAB rainflow alapú cycle counting.
% Ha a MATLAB table tartalmaz Start/End indexet, azt is visszaadjuk.

    sig = sig(:).';

    if numel(sig) < 2
        ranges = [];
        means = [];
        counts = [];
        start_idx = [];
        end_idx = [];
        return;
    end

    if numel(sig) == 2
        ranges = abs(sig(2) - sig(1));
        means  = 0.5 * (sig(1) + sig(2));
        counts = 0.5;
        start_idx = 1;
        end_idx = 2;
        return;
    end

    try
        rf = rainflow(sig);

        if istable(rf)
            ranges = rf.Range(:).';
            means  = rf.Mean(:).';
            counts = rf.Count(:).';

            if all(ismember({'Start','End'}, rf.Properties.VariableNames))
                start_idx = rf.Start(:).';
                end_idx   = rf.End(:).';
            else
                start_idx = nan(size(ranges));
                end_idx   = nan(size(ranges));
            end
        else
            % régebbi MATLAB formatum: [count range mean start end]
            counts = rf(:,1).';
            ranges = rf(:,2).';
            means  = rf(:,3).';

            if size(rf,2) >= 5
                start_idx = rf(:,4).';
                end_idx   = rf(:,5).';
            else
                start_idx = nan(size(ranges));
                end_idx   = nan(size(ranges));
            end
        end

    catch
        tp = turning_points(sig);

        if numel(tp) < 2
            ranges = [];
            means = [];
            counts = [];
            start_idx = [];
            end_idx = [];
            return;
        end

        ranges = abs(diff(tp));
        means = 0.5 * (tp(1:end-1) + tp(2:end));
        counts = 0.5 * ones(size(ranges));
        start_idx = nan(size(ranges));
        end_idx = nan(size(ranges));
    end
end


function tp = turning_points(sig)
    sig = sig(:).';

    if isempty(sig)
        tp = [];
        return;
    end

    keep = [true, abs(diff(sig)) > 1e-12];
    x = sig(keep);

    if numel(x) <= 2
        tp = x;
        return;
    end

    tp = x(1);
    for i = 2:(numel(x)-1)
        d1 = x(i) - x(i-1);
        d2 = x(i+1) - x(i);
        if sign(d1) ~= sign(d2)
            tp(end+1) = x(i); %#ok<AGROW>
        end
    end
    tp(end+1) = x(end);
end


function v = must(s, field, defaultVal)
    if isfield(s, field)
        v = s.(field);
    else
        v = defaultVal;
    end
end


function Voc = LfpCellVoc(SoC, Temp)
    persistent F;

    if isempty(F)
        soc_axis = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100]';
        temp_axis = [-20, -10, 0, 10, 25, 35, 45];

        voc_table = [
            2.000, 2.000, 2.000, 2.000, 2.000, 2.000, 2.000;
            2.955, 2.965, 2.980, 2.990, 3.000, 3.002, 3.005;
            3.165, 3.175, 3.185, 3.195, 3.200, 3.201, 3.202;
            3.205, 3.215, 3.225, 3.235, 3.240, 3.241, 3.242;
            3.235, 3.245, 3.255, 3.265, 3.270, 3.271, 3.272;
            3.250, 3.260, 3.270, 3.276, 3.280, 3.280, 3.281;
            3.260, 3.270, 3.280, 3.286, 3.290, 3.290, 3.291;
            3.265, 3.275, 3.285, 3.291, 3.295, 3.295, 3.296;
            3.270, 3.280, 3.290, 3.296, 3.300, 3.300, 3.301;
            3.275, 3.285, 3.295, 3.301, 3.305, 3.305, 3.306;
            3.280, 3.290, 3.300, 3.306, 3.310, 3.310, 3.311;
            3.282, 3.292, 3.302, 3.308, 3.312, 3.312, 3.313;
            3.284, 3.294, 3.304, 3.310, 3.315, 3.315, 3.316;
            3.287, 3.297, 3.307, 3.313, 3.318, 3.318, 3.319;
            3.290, 3.300, 3.310, 3.316, 3.320, 3.320, 3.321;
            3.292, 3.302, 3.312, 3.318, 3.322, 3.322, 3.323;
            3.295, 3.305, 3.315, 3.321, 3.325, 3.325, 3.326;
            3.298, 3.308, 3.318, 3.323, 3.327, 3.327, 3.328;
            3.300, 3.310, 3.320, 3.325, 3.330, 3.330, 3.331;
            3.325, 3.332, 3.338, 3.345, 3.350, 3.351, 3.352;
            3.520, 3.545, 3.570, 3.585, 3.600, 3.600, 3.600
        ];

        F = griddedInterpolant({soc_axis, temp_axis}, voc_table, 'linear');
    end

    Voc = F(SoC, Temp);
end


function R0 = LfpCellR0(SoC, Temp)
    persistent F_r0;

    if isempty(F_r0)
        soc_axis = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100]';
        temp_axis = [-20, -10, 0, 10, 25, 35, 45];

        base_r0 = [
            0.0150, 0.0120, 0.0090, 0.0075, 0.0060, 0.0055, 0.0050;
            0.0090, 0.0075, 0.0060, 0.0050, 0.0042, 0.0038, 0.0035;
            0.0060, 0.0050, 0.0040, 0.0032, 0.0028, 0.0025, 0.0023;
            0.0045, 0.0038, 0.0030, 0.0025, 0.0020, 0.0018, 0.0016;
            0.0035, 0.0028, 0.0022, 0.0018, 0.0015, 0.0014, 0.0013;
            0.0030, 0.0025, 0.0019, 0.0015, 0.0012, 0.0011, 0.0010;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0028, 0.0023, 0.0017, 0.0014, 0.0010, 0.0009, 0.0009;
            0.0030, 0.0025, 0.0019, 0.0015, 0.0012, 0.0011, 0.0010;
            0.0035, 0.0028, 0.0022, 0.0018, 0.0015, 0.0014, 0.0013
        ];

        F_r0 = griddedInterpolant({soc_axis, temp_axis}, base_r0, 'linear');
    end

    R0 = F_r0(SoC, Temp);
end

