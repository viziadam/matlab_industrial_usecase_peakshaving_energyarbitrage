function evalResult = run_evaluation(mode)
% RUN_EVALUATION
%
% Mentett AC/DC szimulacios eredmenyekbol ujrageneralja a dolgozati
% kiertekeleseket a megadott mukodesi modra.
%
% Hasznalat:
%   run_evaluation()
%   run_evaluation("peak_only")
%   run_evaluation("energy_only")
%   run_evaluation("combined")
%   run_evaluation("all")
%
% Fontos:
%   Ez a fuggveny nem futtatja ujra a teljes candidate szimulaciot.
%   Csak a results/<mode>/results_dc_<mode>.mat es
%   results/<mode>/results_ac_<mode>.mat fajlokbol dolgozik.

    if nargin < 1 || strlength(string(mode)) == 0
        mode = "combined";
    end

    mode = lower(string(mode));
    basePath = fileparts(mfilename('fullpath'));

    if mode == "all"
        modesToRun = ["peak_only", "energy_only", "combined"];

        evalResult = struct();

        for k = 1:numel(modesToRun)
            currentMode = modesToRun(k);
            evalResult.(char(currentMode)) = local_run_single_mode(basePath, currentMode);
        end

        return;
    end

    evalResult = local_run_single_mode(basePath, mode);
end


function result = local_run_single_mode(basePath, mode)

    allowedModes = ["peak_only", "energy_only", "combined"];

    if ~any(mode == allowedModes)
        error('Invalid evaluation mode: %s', mode);
    end

    cfg = create_configurations(basePath);
    cfg.dispatch.objectiveMode = mode;

    result = struct();
    result.mode = mode;

    fprintf('\n====================================================\n');
    fprintf('EVALUATION MODE: %s\n', mode);
    fprintf('====================================================\n');

    % ------------------------------------------------------------------
    % Altalanos AC/DC osszehasonlito kiertekeles
    % ------------------------------------------------------------------
    result.compareResult = compare_ac_dc_results_for_mode(cfg, mode);

    % ------------------------------------------------------------------
    % Modspecifikus dolgozati kiertekelesek
    % ------------------------------------------------------------------
    if mode == "energy_only"
        result.thesisEvaluation = run_energy_only_thesis_evaluation(basePath);
    elseif mode == "combined"
        result.thesisEvaluation = run_combined_thesis_evaluation(basePath);
    else
        result.thesisEvaluation = [];
    end
end
