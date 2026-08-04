function f = fetch(source, subdir, branch)
%FETCH Materialize a bundle from a dir, local tar/zip archive, or git URL.
%   F = OKF.FETCH(SOURCE[, SUBDIR[, BRANCH]]) returns a struct with fields
%   dir, kind, and cleanup (a function handle removing the temp dir; call it
%   when done -- okf.ingest does this automatically).
%
%   Archives extract via the untar/unzip builtins, which cannot list members
%   before extraction; instead extraction goes into a FRESH temp dir and
%   every returned path is verified to sit inside it afterwards (containment
%   check). Remote http(s) archive download is not supported (use the
%   R/Python binding).
if nargin < 2
    subdir = '';
end
if nargin < 3
    branch = '';
end
f = struct('dir', '', 'kind', '', 'cleanup', @() []);
if exist(source, 'dir') == 7
    old = cd(source);
    f.dir = pwd;
    cd(old);
    f.kind = 'dir';
    return;
end
kind = source_kind(source);
if ~isempty(regexp(source, '^https?://', 'once')) && ~strcmp(kind, 'git')
    error('okf:fetch', ['remote archive download is not supported by the MATLAB ' ...
                        'binding; fetch the archive locally first (git URLs are supported)']);
end
tmp = tempname();
mkdir(tmp);
f.cleanup = @() rm_rf(tmp);
try
    if strcmp(kind, 'git')
        repo = fullfile(tmp, 'repo');
        cmd = 'git clone --depth 1 ';
        if ~isempty(branch)
            cmd = [cmd '--branch "' branch '" '];
        end
        cmd = [cmd '"' source '" "' repo '"'];
        [rc, ~] = system(cmd);
        if rc ~= 0
            error('okf:fetch', 'git clone failed (is git installed?): %s', source);
        end
        base = repo;
    else
        ex = fullfile(tmp, 'x');
        mkdir(ex);
        if strcmp(kind, 'zip')
            extracted = unzip(source, ex);
        else
            extracted = untar(source, ex);
        end
        assert_contained(extracted, ex);
        base = ex;
    end
    f.dir = bundle_root(base, subdir);
    f.kind = kind;
catch err
    f.cleanup();
    rethrow(err);
end
end

function kind = source_kind(source)
s = regexprep(source, '[?#].*$', '');
ls = lower(s);
if okf.internal.ends_with(ls, '.zip')
    kind = 'zip';
elseif okf.internal.ends_with(ls, '.tar.gz') || okf.internal.ends_with(ls, '.tgz') || ...
       okf.internal.ends_with(ls, '.tar') || okf.internal.ends_with(ls, '.tar.bz2')
    kind = 'tar';
elseif okf.internal.ends_with(s, '.git') || strncmp(source, 'git@', 4) || ...
       ~isempty(regexp(s, '^https?://(www\.)?(github|gitlab|bitbucket)\.', 'once'))
    kind = 'git';
else
    error('okf:fetch', ...
          'cannot determine source kind (expected a dir, git URL, or tar/zip): %s', source);
end
end

function assert_contained(extracted, ex)
%ASSERT_CONTAINED Post-extraction traversal check: every extracted path must
%   sit inside the fresh extraction dir (untar/unzip give no pre-listing).
%   MATLAB untar returns absolute paths; Octave returns member-relative ones
%   -- reduce both to a path relative to EX and reject escapes.
old = cd(ex);
ex_abs = pwd;
cd(old);
prefix = [ex_abs filesep];
for i = 1:numel(extracted)
    p = extracted{i};
    is_abs = (numel(p) >= 2 && p(2) == ':') || (~isempty(p) && (p(1) == '/' || p(1) == '\'));
    if is_abs
        if strcmp(p, ex_abs) || strncmp(p, prefix, numel(prefix))
            rel = p(min(numel(prefix) + 1, numel(p) + 1):end);
        else
            rm_rf(ex_abs);
            error('okf:fetch', 'archive member escaped target dir (path traversal): %s', p);
        end
    else
        rel = p;
    end
    segs = strsplit(strrep(rel, '\', '/'), '/');
    if any(strcmp(segs, '..'))
        rm_rf(ex_abs);
        error('okf:fetch', 'archive member escaped target dir (path traversal): %s', p);
    end
end
end

function root = bundle_root(base, subdir)
if ~isempty(subdir)
    root = fullfile(base, subdir);
    return;
end
cur = base;
for hop = 1:6
    entries = dir(cur);
    has_md = false;
    dirs = {};
    for i = 1:numel(entries)
        name = entries(i).name;
        if strcmp(name, '.') || strcmp(name, '..') || name(1) == '.'
            continue;
        end
        if okf.internal.ends_with(lower(name), '.md')
            has_md = true;
        end
        if entries(i).isdir
            dirs{end + 1} = fullfile(cur, name); %#ok<AGROW>
        end
    end
    if ~has_md && numel(dirs) == 1
        cur = dirs{1};
    else
        break;
    end
end
root = cur;
end

function rm_rf(d)
if exist(d, 'dir') == 7
    try
        rmdir(d, 's');
    catch
    end
end
end
