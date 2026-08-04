function out = seeds(ing, query, k)
%SEEDS Deterministic lexical seed selection -- mirrors py graph.seeds.
%   +3 per distinct query token in the title, +2 in the description or tags
%   (JSON text), +1 in the body; non-reserved concepts in path order; sort
%   by (-score, path); top k (default 5).
if nargin < 3
    k = 5;
end
stop = {'the', 'and', 'for', 'are', 'was', 'were', 'with', 'that', 'this', ...
        'from', 'how', 'what', 'when', 'where', 'which', 'does', 'did', ...
        'can', 'could', 'should', 'would', 'will', 'has', 'have', 'had', ...
        'not', 'its', 'our', 'your', 'their', 'about', 'into', 'over', ...
        'under', 'why', 'who', 'whom'};
toks = regexp(lower(query), '[a-z0-9]+', 'match');
toks = unique(toks);  % sorted + deduped
keep = true(1, numel(toks));
for i = 1:numel(toks)
    if numel(toks{i}) < 3 || any(strcmp(toks{i}, stop))
        keep(i) = false;
    end
end
toks = toks(keep);

out = struct('path', {}, 'score', {}, 'title', {});
for i = 1:numel(ing.bundle.concepts)   % path order -> stable tie order
    c = ing.bundle.concepts(i);
    if c.reserved
        continue;
    end
    ttl = lower(c.title);
    dsc = lower(c.description);
    if isempty(c.tags)
        tgs = '';
    else
        tgs = lower(jsonencode(c.tags));
    end
    bod = lower(c.body);
    sc = 0;
    for j = 1:numel(toks)
        t = toks{j};
        if ~isempty(strfind(ttl, t)) %#ok<STREMP>
            sc = sc + 3;
        end
        if ~isempty(strfind(dsc, t)) || ~isempty(strfind(tgs, t)) %#ok<STREMP>
            sc = sc + 2;
        end
        if ~isempty(strfind(bod, t)) %#ok<STREMP>
            sc = sc + 1;
        end
    end
    if sc > 0
        out(end + 1) = struct('path', c.path, 'score', sc, 'title', c.title); %#ok<AGROW>
    end
end
% sort by (-score, original order == path order): explicit two-key sortrows
if ~isempty(out)
    keymat = [-[out.score]', (1:numel(out))'];
    [~, ix] = sortrows(keymat);
    out = out(ix');
end
if numel(out) > k
    out = out(1:k);
end
end
