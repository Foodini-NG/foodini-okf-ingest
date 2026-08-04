function lines = split_lines(txt)
%SPLIT_LINES Python-splitlines()-style split (the parity normalization).
%   Splits on \n, strips a trailing CR from each line (CRLF), and drops the
%   phantom empty element a trailing newline would produce -- matching
%   Python splitlines(), R readLines(), Rust str::lines().
if isempty(txt)
    lines = {};
    return;
end
lines = strsplit(txt, sprintf('\n'), 'CollapseDelimiters', false);
if ~isempty(lines) && isempty(lines{end}) && txt(end) == sprintf('\n')
    lines(end) = [];
end
for i = 1:numel(lines)
    if ~isempty(lines{i}) && lines{i}(end) == sprintf('\r')
        lines{i} = lines{i}(1:end - 1);
    end
end
end
