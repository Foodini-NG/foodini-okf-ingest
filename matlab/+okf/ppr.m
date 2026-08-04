function rows = ppr(ing, starts, varargin)
%PPR Exact power-iteration Personalized PageRank -- mirrors py graph.ppr.
%   ROWS = OKF.PPR(ING, STARTS, 'damping', 0.85, 'tol', 1e-12, ...
%                  'max_iter', 200, 'k', 20, 'weights', [])
%   Deterministic and bit-identical with the other bindings: edges iterate
%   in sorted (src, dst) index order, dangling mass and the L1 convergence
%   sum accumulate in ascending node index, and scores round half-even
%   (okf.round_dec -- NOT MATLAB round(), which is half-away-from-zero).
%   'k' <= 0 returns all positive-score rows.
opt = struct('damping', 0.85, 'tol', 1e-12, 'max_iter', 200, 'k', 20, 'weights', []);
for i = 1:2:numel(varargin)
    opt.(varargin{i}) = varargin{i + 1};
end
if ischar(starts)
    starts = {starts};
end

concepts = ing.bundle.concepts;  % sorted by path
n = numel(concepts);
paths = cell(1, n);
for i = 1:n
    paths{i} = concepts(i).path;
end
missing = {};
for j = 1:numel(starts)
    if ~any(strcmp(starts{j}, paths))
        missing{end + 1} = starts{j}; %#ok<AGROW>
    end
end
if ~isempty(missing)
    error('okf:ppr', 'start concept not found: %s', strjoin(missing, ', '));
end
weights = opt.weights;
if isempty(weights)
    weights = ones(1, numel(starts));
end
if numel(weights) ~= numel(starts) || any(weights < 0) || sum(weights) <= 0
    error('okf:ppr', 'weights must be non-negative, same length as start, positive sum');
end

% Distinct resolved links -> undirected edge index pairs, sorted rows.
pairs = zeros(0, 2);
for i = 1:numel(ing.links)
    l = ing.links(i);
    if ~l.resolved || strcmp(l.src_path, l.dst_path)
        continue;
    end
    si = find(strcmp(l.src_path, paths), 1);
    di = find(strcmp(l.dst_path, paths), 1);
    if isempty(si) || isempty(di)
        continue;
    end
    pairs(end + 1, :) = [si, di]; %#ok<AGROW>
    pairs(end + 1, :) = [di, si]; %#ok<AGROW>
end
edges = unique(pairs, 'rows');   % sorted (s, d) ascending -- the parity order
deg = zeros(1, n);
for e = 1:size(edges, 1)
    deg(edges(e, 1)) = deg(edges(e, 1)) + 1;
end

seed = zeros(1, n);
for j = 1:numel(starts)
    si = find(strcmp(starts{j}, paths), 1);
    seed(si) = seed(si) + weights(j);
end
tot = 0;
for i = 1:n
    tot = tot + seed(i);
end
for i = 1:n
    seed(i) = seed(i) / tot;
end

p = seed;
for iter = 1:opt.max_iter
    contrib = zeros(1, n);
    for e = 1:size(edges, 1)     % fixed sorted order -> deterministic fp
        s = edges(e, 1);
        d = edges(e, 2);
        if p(s) ~= 0
            contrib(d) = contrib(d) + p(s) / deg(s);
        end
    end
    dangling = 0;
    for i = 1:n
        if deg(i) == 0
            dangling = dangling + p(i);
        end
    end
    np = zeros(1, n);
    for i = 1:n
        np(i) = (1 - opt.damping) * seed(i) + opt.damping * (contrib(i) + dangling * seed(i));
    end
    delta = 0;
    for i = 1:n
        delta = delta + abs(np(i) - p(i));
    end
    p = np;
    if delta < opt.tol
        break;
    end
end

rows = struct('path', {}, 'score', {}, 'title', {}, 'reserved', {});
for i = 1:n                       % ascending path order -> stable tie order
    score = okf.round_dec(p(i), 10);
    if score > 0
        rows(end + 1) = struct('path', paths{i}, 'score', score, ...
                               'title', concepts(i).title, ...
                               'reserved', concepts(i).reserved); %#ok<AGROW>
    end
end
if ~isempty(rows)
    keymat = [-[rows.score]', (1:numel(rows))'];
    [~, ix] = sortrows(keymat);
    rows = rows(ix');
end
if opt.k > 0 && numel(rows) > opt.k
    rows = rows(1:opt.k);
end
end
