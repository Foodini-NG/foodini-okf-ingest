function out = validate(b)
%VALIDATE OKF validation rules -- mirrors py validate() verbatim.
%   Permissive: recommended-field issues warn; only unparseable frontmatter
%   or a missing type are errors.
out = struct('path', {}, 'severity', {}, 'rule', {}, 'message', {});
    function add(path, sev, rule, msg)
        out(end + 1) = struct('path', path, 'severity', sev, ...
                              'rule', rule, 'message', msg);
    end
for i = 1:numel(b.concepts)
    c = b.concepts(i);
    if c.reserved
        continue;
    end
    if ~isempty(c.parse_error)
        add(c.path, 'error', 'frontmatter_unparseable', ...
            sprintf('no parseable frontmatter (%s)', c.parse_error));
        continue;
    end
    if isempty(c.type)
        add(c.path, 'error', 'missing_type', 'frontmatter has no non-empty type');
    end
    if isempty(c.title)
        add(c.path, 'warn', 'missing_title', 'recommended field title absent');
    end
    if isempty(c.description)
        add(c.path, 'warn', 'missing_description', 'recommended field description absent');
    end
    if isempty(c.timestamp)
        add(c.path, 'warn', 'missing_timestamp', 'recommended field timestamp absent');
    elseif isempty(regexp(c.timestamp, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$', 'once'))
        add(c.path, 'warn', 'timestamp_not_iso8601', ...
            sprintf('timestamp not ISO-8601: %s', c.timestamp));
    end
end
lk_all = okf.links(b);
for i = 1:numel(lk_all)
    if ~lk_all(i).resolved
        add(lk_all(i).src_path, 'warn', 'broken_link', ...
            sprintf('unresolved link: %s', lk_all(i).dst_raw));
    end
end
% orphan concepts: non-reserved, parseable, no inbound link
inbound = {};
for i = 1:numel(lk_all)
    if lk_all(i).resolved
        inbound{end + 1} = lk_all(i).dst_path; %#ok<AGROW>
    end
end
for i = 1:numel(b.concepts)
    c = b.concepts(i);
    if c.reserved || ~isempty(c.parse_error)
        continue;
    end
    if ~any(strcmp(c.path, inbound))
        add(c.path, 'warn', 'orphan', 'no inbound links (orphan concept)');
    end
end
end
