function cfg = add_hybrid_evaluation_metrics_to_cfg(cfg)
% ADD_HYBRID_EVALUATION_METRICS_TO_CFG
%
% Hybrid AC+DC BESS specifikus summary metrikak hozzaadasa.
% Idempotens: ha egy metrika mar szerepel, nem adja hozza ujra.

    if ~isfield(cfg, 'output')
        cfg.output = struct();
    end

    if ~isfield(cfg.output, 'summaryMetrics') || isempty(cfg.output.summaryMetrics)
        cfg.output.summaryMetrics = struct('name', {}, 'source', {});
    end

    extraSummary = struct( ...
        'name', { ...
            'finalSoCDc', ...
            'finalSoCAc', ...
            'finalSoHDc', ...
            'finalSoHAc' ...
        }, ...
        'source', { ...
            'finalSoCDc', ...
            'finalSoCAc', ...
            'finalSoHDc', ...
            'finalSoHAc' ...
        });

    if isempty(cfg.output.summaryMetrics)
        existingNames = strings(0, 1);
    else
        existingNames = string({cfg.output.summaryMetrics.name});
    end

    for k = 1:numel(extraSummary)
        if ~any(existingNames == string(extraSummary(k).name))
            cfg.output.summaryMetrics(end+1) = extraSummary(k); %#ok<AGROW>
            existingNames(end+1) = string(extraSummary(k).name); %#ok<AGROW>
        end
    end
end
