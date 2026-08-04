function m = yaml_parse(txt)
%YAML_PARSE Minimal YAML-subset parser for OKF frontmatter.
%   M = OKF.YAML_PARSE(TXT) parses the frontmatter subset OKF uses into a
%   containers.Map (char keys; values are char, cell array of char, or []).
%
%   Supported (everything kept VERBATIM as text -- no date/number/bool
%   coercion, the cross-binding parity rule):
%     key: scalar                 (unquoted; may contain ':' as in URIs)
%     key: "quoted" / 'quoted'
%     key: [a, b, "c"]            (flow sequence)
%     key:                        (null)
%       - item                    (block sequence under a null-valued key)
%     # full-line comments; " #" starts a trailing comment after an
%     unquoted scalar
%   Out-of-subset constructs (nested maps, multi-line scalars, anchors)
%   raise an error -- the caller records the spec-sanctioned
%   yaml_parse_error finding.

lines = okf.internal.split_lines(txt);
m = containers.Map('KeyType', 'char', 'ValueType', 'any');
n = numel(lines);
i = 1;
while i <= n
    line = lines{i};
    stripped = strtrim(line);
    if isempty(stripped) || stripped(1) == '#'
        i = i + 1;
        continue;
    end
    if ~isempty(regexp(line, '^\s', 'once'))
        error('okf:yaml', 'unexpected indented line (out of subset): %s', line);
    end
    tok = regexp(line, '^([A-Za-z0-9_][A-Za-z0-9_.-]*):(.*)$', 'tokens', 'once');
    if isempty(tok)
        error('okf:yaml', 'not a key: value line (out of subset): %s', line);
    end
    key = tok{1};
    rest = strtrim(tok{2});
    if isempty(rest) || rest(1) == '#'
        % null value -- unless a block sequence follows
        [items, i] = block_seq(lines, i + 1);
        if isempty(items)
            m(key) = [];
        else
            m(key) = items;
        end
        continue;
    end
    if rest(1) == '['
        m(key) = flow_seq(rest, line);
    else
        m(key) = scalar_value(rest);
    end
    i = i + 1;
end
end

function [items, next_i] = block_seq(lines, i)
items = {};
next_i = i;
while next_i <= numel(lines)
    line = lines{next_i};
    s = strtrim(line);
    if isempty(s)
        next_i = next_i + 1;
        continue;
    end
    tok = regexp(line, '^\s+-\s+(.*)$', 'tokens', 'once');
    if isempty(tok)
        break;
    end
    items{end + 1} = scalar_value(strtrim(tok{1})); %#ok<AGROW>
    next_i = next_i + 1;
end
end

function items = flow_seq(rest, line)
close_br = find(rest == ']', 1, 'last');
if isempty(close_br)
    error('okf:yaml', 'unterminated flow sequence (out of subset): %s', line);
end
inner = strtrim(rest(2:close_br - 1));
items = {};
if isempty(inner)
    return;
end
% split on commas outside quotes
depth_q = '';
start = 1;
parts = {};
for k = 1:numel(inner)
    c = inner(k);
    if ~isempty(depth_q)
        if c == depth_q
            depth_q = '';
        end
    elseif c == '"' || c == ''''
        depth_q = c;
    elseif c == ','
        parts{end + 1} = inner(start:k - 1); %#ok<AGROW>
        start = k + 1;
    end
end
parts{end + 1} = inner(start:end);
for k = 1:numel(parts)
    items{end + 1} = scalar_value(strtrim(parts{k})); %#ok<AGROW>
end
end

function v = scalar_value(s)
if numel(s) >= 2 && s(1) == '"' && s(end) == '"'
    v = strrep(s(2:end - 1), '\"', '"');
    return;
end
if numel(s) >= 2 && s(1) == '''' && s(end) == ''''
    v = strrep(s(2:end - 1), '''''', '''');
    return;
end
% unquoted: strip a trailing comment (" #" with preceding whitespace)
cut = regexp(s, '\s#', 'once');
if ~isempty(cut)
    s = strtrim(s(1:cut - 1));
end
if strcmp(s, '~') || strcmpi(s, 'null')
    v = [];
else
    v = s;  % verbatim -- timestamps/numbers/bools stay text
end
end
