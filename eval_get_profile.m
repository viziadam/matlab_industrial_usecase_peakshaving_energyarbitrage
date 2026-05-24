function s = eval_get_profile(evalOutOrData, coupling, profileName, opts)
% EVAL_GET_PROFILE
% Dynamically extract one candidateProfiles field for one coupling.
%
% Example:
%   out = evaluation_energy_only(cfg);
%   s = eval_get_profile(out, "dc", "meanSoC");
%   imagesc(s.profileMatrix)
%
% Output:
%   s.xCandidate      candidate x-axis, default BESS_PV_ratio
%   s.profileMatrix   nCandidate x nTimeStep profile matrix
%   s.table           filtered/sorted candidate table

    if nargin < 4 || isempty(opts)
        opts = struct();
    end

    opts = local_set_default(opts, 'xField', "BESS_PV_ratio");
    opts = local_set_default(opts, 'onlyValid', true);
    opts = local_set_default(opts, 'sortByX', true);

    data = local_get_data(evalOutOrData);
    coupling = lower(string(coupling));
    profileName = char(profileName);
    xField = char(opts.xField);

    if ~isfield(data, char(coupling))
        error('Missing coupling data: %s', coupling);
    end

    item = data.(char(coupling));

    if ~isfield(item, 'candidateTable')
        error('Missing candidateTable for coupling: %s', coupling);
    end

    if ~isfield(item, 'candidateProfiles')
        error('Missing candidateProfiles for coupling: %s', coupling);
    end

    if ~isfield(item.candidateProfiles, profileName)
        error('Missing profile field: %s', profileName);
    end

    T = item.candidateTable;
    P = item.candidateProfiles.(profileName);

    if size(P, 1) ~= height(T)
        error('Profile matrix row count does not match candidateTable height.');
    end

    mask = true(height(T), 1);

    if opts.onlyValid
        if ismember('wasSimulated', T.Properties.VariableNames)
            mask = mask & logical(T.wasSimulated);
        end

        if ismember('hasError', T.Properties.VariableNames)
            mask = mask & ~logical(T.hasError);
        end
    end

    T = T(mask, :);
    P = P(mask, :);

    if ~ismember(xField, T.Properties.VariableNames)
        error('Missing xField: %s', xField);
    end

    if opts.sortByX
        [T, order] = sortrows(T, xField);
        P = P(order, :);
    end

    s = struct();
    s.coupling = coupling;
    s.profileName = string(profileName);
    s.xField = string(xField);
    s.xCandidate = T.(xField);
    s.profileMatrix = P;
    s.table = T;
    s.label = upper(coupling) + " - " + string(profileName);
end


function data = local_get_data(evalOutOrData)
    if isfield(evalOutOrData, 'data')
        data = evalOutOrData.data;
    else
        data = evalOutOrData;
    end
end


function S = local_set_default(S, fieldName, defaultValue)
    if ~isfield(S, fieldName) || isempty(S.(fieldName))
        S.(fieldName) = defaultValue;
    end
end
