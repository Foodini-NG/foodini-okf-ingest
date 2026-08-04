function d = diff(a, b)
%DIFF Deterministic concept-level changelog -- mirrors py diff().
%   D = OKF.DIFF(A, B) where each side is a bundle directory path (char), a
%   bundle struct (okf.read_bundle), or an ingest struct (okf.ingest) -- the
%   latter is drift mode ("what changed since this ingest"), catalog-free.
%   Pure hash/set comparison, all output sorted by path.
sa = bundle_state(a);
sb = bundle_state(b);

ka = sort(keys(sa.concepts));
kb = sort(keys(sb.concepts));
d = struct();
d.added = setdiff(kb, ka);
d.removed = setdiff(ka, kb);
common = intersect(ka, kb);   % sorted
changed = {};
type_changed = {};
retitled = {};
for i = 1:numel(common)
    p = common{i};
    ca = sa.concepts(p);
    cb = sb.concepts(p);
    if ~strcmp(ca.content_hash, cb.content_hash)
        changed{end + 1} = p; %#ok<AGROW>
    end
    if ~strcmp(ca.type, cb.type)
        type_changed{end + 1} = struct('path', p, 'from', ca.type, 'to', cb.type); %#ok<AGROW>
    end
    if ~strcmp(ca.title, cb.title)
        retitled{end + 1} = struct('path', p, 'from', ca.title, 'to', cb.title); %#ok<AGROW>
    end
end
d.changed = changed;
d.type_changed = type_changed;
d.retitled = retitled;
d.links_added = pair_diff(sb.edges, sa.edges);
d.links_removed = pair_diff(sa.edges, sb.edges);
d.broken_added = pair_diff(sb.broken, sa.broken);
d.broken_fixed = pair_diff(sa.broken, sb.broken);
d.identical = isempty(d.added) && isempty(d.removed) && isempty(d.changed) && ...
              isempty(d.type_changed) && isempty(d.retitled) && ...
              isempty(d.links_added) && isempty(d.links_removed) && ...
              isempty(d.broken_added) && isempty(d.broken_fixed);
end

function s = bundle_state(x)
if ischar(x)
    bun = okf.read_bundle(x, 'dir');
    lk = okf.links(bun);
elseif isstruct(x) && isfield(x, 'summary')     % ingest struct (drift mode)
    bun = x.bundle;
    lk = x.links;
elseif isstruct(x) && isfield(x, 'concepts')    % bundle struct
    bun = x;
    lk = okf.links(bun);
else
    error('okf:diff', 'diff side must be a bundle dir, bundle struct, or ingest struct');
end
s = struct();
s.concepts = containers.Map('KeyType', 'char', 'ValueType', 'any');
for i = 1:numel(bun.concepts)
    c = bun.concepts(i);
    s.concepts(c.path) = struct('type', c.type, 'title', c.title, ...
                                'content_hash', c.content_hash);
end
s.edges = {};
s.broken = {};
for i = 1:numel(lk)
    if lk(i).resolved
        s.edges{end + 1} = [lk(i).src_path '|' lk(i).dst_path]; %#ok<AGROW>
    else
        s.broken{end + 1} = [lk(i).src_path '|' lk(i).dst_raw]; %#ok<AGROW>
    end
end
s.edges = unique(s.edges);
s.broken = unique(s.broken);
end

function out = pair_diff(a, b)
%PAIR_DIFF "src|dst" keys in A but not B, sorted, as structs.
delta = setdiff(a, b);   % sorted
out = {};
for i = 1:numel(delta)
    bar = find(delta{i} == '|', 1);
    out{end + 1} = struct('src_path', delta{i}(1:bar - 1), ...
                          'dst', delta{i}(bar + 1:end)); %#ok<AGROW>
end
end
