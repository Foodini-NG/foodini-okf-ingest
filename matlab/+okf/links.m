function out = links(b)
%LINKS All internal links of a bundle with resolution status.
%   Mirrors py links(): markdown links (externals skipped) then wikilinks,
%   per concept in path order. Rows: src_path, dst_raw, dst_path ('' if
%   unresolved), resolved.
idx = wiki_index(b.concepts);
out = struct('src_path', {}, 'dst_raw', {}, 'dst_path', {}, 'resolved', {});
for i = 1:numel(b.concepts)
    c = b.concepts(i);
    for j = 1:numel(c.links_raw)
        raw = c.links_raw{j};
        if is_external(raw)
            continue;
        end
        dst = resolve_link(raw, c.path, b.known);
        out(end + 1) = struct('src_path', c.path, 'dst_raw', raw, ...
                              'dst_path', dst, 'resolved', ~isempty(dst)); %#ok<AGROW>
    end
    for j = 1:numel(c.wikilinks_raw)
        raw = c.wikilinks_raw{j};
        dst = resolve_wiki(raw, idx, b.known);
        out(end + 1) = struct('src_path', c.path, 'dst_raw', raw, ...
                              'dst_path', dst, 'resolved', ~isempty(dst)); %#ok<AGROW>
    end
end
end

function idx = wiki_index(concepts)
%WIKI_INDEX lowercased id/alias/title/stem -> path; ambiguous keys dropped.
kinds = {'id', 'alias', 'title', 'stem'};
idx = struct();
amb = struct();
for k = 1:4
    idx.(kinds{k}) = containers.Map('KeyType', 'char', 'ValueType', 'char');
    amb.(kinds{k}) = {};
end
    function add(kind, key, path)
        key = lower(strtrim(key));
        if isempty(key)
            return;
        end
        m = idx.(kind);
        if isKey(m, key) && ~strcmp(m(key), path)
            amb.(kind){end + 1} = key;
        end
        m(key) = path;  % containers.Map is a handle; mutation sticks
    end
for i = 1:numel(concepts)
    c = concepts(i);
    fm = c.frontmatter;
    if isa(fm, 'containers.Map')
        if isKey(fm, 'id') && ischar(fm('id'))
            add('id', fm('id'), c.path);
        end
        if isKey(fm, 'aliases') && iscell(fm('aliases'))
            al = fm('aliases');
            for j = 1:numel(al)
                if ischar(al{j})
                    add('alias', al{j}, c.path);
                end
            end
        end
    end
    if ~isempty(c.title)
        add('title', c.title, c.path);
    end
    slash = find(c.path == '/', 1, 'last');
    if isempty(slash)
        base = c.path;
    else
        base = c.path(slash + 1:end);
    end
    dot = find(base == '.', 1, 'last');
    if isempty(dot)
        stem = base;
    else
        stem = base(1:dot - 1);
    end
    add('stem', stem, c.path);
end
for k = 1:4
    m = idx.(kinds{k});
    dropped = amb.(kinds{k});
    for j = 1:numel(dropped)
        if isKey(m, dropped{j})
            remove(m, dropped{j});
        end
    end
end
end

function dst = resolve_wiki(raw, idx, known)
hash_i = find(raw == '#', 1);
if ~isempty(hash_i)
    raw = raw(1:hash_i - 1);
end
ref = strtrim(raw);
dst = '';
if isempty(ref)
    return;
end
if any(strcmp(ref, known))
    dst = ref;
    return;
end
if numel(ref) >= 3 && strcmp(ref(end - 2:end), '.md')
    cand = ref;
else
    cand = [ref '.md'];
end
if any(strcmp(cand, known))
    dst = cand;
    return;
end
lref = lower(ref);
kinds = {'id', 'alias', 'title', 'stem'};
for k = 1:4
    m = idx.(kinds{k});
    if isKey(m, lref)
        dst = m(lref);
        return;
    end
end
end

function dst = resolve_link(raw, src_rel, known)
hash_i = find(raw == '#', 1);
if ~isempty(hash_i)
    t = raw(1:hash_i - 1);
else
    t = raw;
end
if ~isempty(t) && t(1) == '/'
    cand = t(2:end);
else
    slash = find(src_rel == '/', 1, 'last');
    if isempty(slash)
        cand = t;
    else
        cand = [src_rel(1:slash) t];
    end
end
cand = norm_path(cand);
if any(strcmp(cand, known))
    dst = cand;
else
    dst = '';
end
end

function p = norm_path(p)
p = strrep(p, '\', '/');
segs = strsplit(p, '/', 'CollapseDelimiters', false);
out = {};
for i = 1:numel(segs)
    s = segs{i};
    if isempty(s) || strcmp(s, '.')
        continue;
    elseif strcmp(s, '..')
        if ~isempty(out)
            out(end) = []; %#ok<AGROW>
        end
    else
        out{end + 1} = s; %#ok<AGROW>
    end
end
p = strjoin(out, '/');
end

function tf = is_external(raw)
hash_i = find(raw == '#', 1);
if ~isempty(hash_i)
    raw = raw(1:hash_i - 1);
end
tf = ~isempty(regexp(raw, '^[a-zA-Z][a-zA-Z0-9+.-]*:', 'once'));
end
