function tf = ends_with(s, suf)
%ENDS_WITH Portable endsWith (avoids the MATLAB-only string functions).
tf = numel(s) >= numel(suf) && strcmp(s(end - numel(suf) + 1:end), suf);
end
