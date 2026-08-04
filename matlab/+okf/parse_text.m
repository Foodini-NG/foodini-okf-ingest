function p = parse_text(txt)
%PARSE_TEXT Frontmatter + body from raw text -- mirrors py parse_file.
%   P = OKF.PARSE_TEXT(TXT) returns a struct with fields:
%     meta  -- containers.Map of frontmatter (or [])
%     body  -- normalized body text (EOLs stripped like Python splitlines)
%     err   -- '' | 'no_frontmatter' | 'unclosed_frontmatter' | 'yaml_parse_error'
raw = okf.internal.split_lines(txt);
full_txt = strjoin(raw, sprintf('\n'));
i = 1;
while i <= numel(raw) && isempty(strtrim(raw{i}))
    i = i + 1;
end
if i > numel(raw) || ~is_fence(raw{i})
    p = struct('meta', [], 'body', full_txt, 'err', 'no_frontmatter');
    return;
end
opn = i;
close_i = 0;
for j = opn + 1:numel(raw)
    if is_fence(raw{j})
        close_i = j;
        break;
    end
end
if close_i == 0
    p = struct('meta', [], 'body', full_txt, 'err', 'unclosed_frontmatter');
    return;
end
fm = strjoin(raw(opn + 1:close_i - 1), sprintf('\n'));
if close_i < numel(raw)
    body = strjoin(raw(close_i + 1:end), sprintf('\n'));
else
    body = '';
end
try
    meta = okf.yaml_parse(fm);
catch
    meta = [];
end
% An empty map is what PyYAML returns as None (empty / comment-only
% frontmatter) -> the same yaml_parse_error.
if ~isa(meta, 'containers.Map') || meta.Count == 0
    p = struct('meta', [], 'body', body, 'err', 'yaml_parse_error');
    return;
end
p = struct('meta', meta, 'body', body, 'err', '');
end

function tf = is_fence(line)
tf = ~isempty(regexp(line, '^---\s*$', 'once'));
end
