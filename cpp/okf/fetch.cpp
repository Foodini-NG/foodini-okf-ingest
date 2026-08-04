// Bundle materialization -- mirrors py/okf/okf.py::fetch, descoped for C++:
// local dir, local tar archive (extracted via the system `tar`, present on
// Linux/macOS/Windows 10+ and all GitHub runners), or git URL via the `git`
// subprocess. Not supported (documented; use the R/Python binding): zip,
// remote http(s) archive download.

#include <array>
#include <cctype>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <regex>
#include <sstream>

#include "okf.hpp"

namespace fs = std::filesystem;

namespace okf {
namespace {

std::string strip_query(const std::string& s) {
    return s.substr(0, s.find_first_of("?#"));
}

std::string lower(std::string s) {
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

bool ends_with(const std::string& s, const std::string& suf) {
    return s.size() >= suf.size() && s.compare(s.size() - suf.size(), suf.size(), suf) == 0;
}

std::string source_kind(const std::string& source) {
    std::string s = strip_query(source);
    std::string ls = lower(s);
    if (ends_with(ls, ".zip")) {
        throw OkfError("zip fetch is not supported by the C++ binding (use tar.gz, "
                       "or the R/Python binding)");
    }
    if (ends_with(ls, ".tar.gz") || ends_with(ls, ".tgz") || ends_with(ls, ".tar") ||
        ends_with(ls, ".tar.bz2")) {
        return "tar";
    }
    static const std::regex re_forge(R"(^https?://(www\.)?(github|gitlab|bitbucket)\.)");
    if (ends_with(s, ".git") || source.rfind("git@", 0) == 0 ||
        std::regex_search(s, re_forge)) {
        return "git";
    }
    throw OkfError("cannot determine source kind (expected a dir, git URL, or tar): " + source);
}

// Reject archive members that would extract outside the target directory.
void assert_safe_member(const std::string& name) {
    std::string n = name;
    for (char& c : n) {
        if (c == '\\') c = '/';
    }
    bool bad = false;
    if (!n.empty() && n[0] == '/') bad = true;                        // absolute
    if (n.size() >= 2 && n[1] == ':') bad = true;                     // drive prefix
    std::stringstream ss(n);
    std::string seg;
    while (std::getline(ss, seg, '/')) {
        if (seg == "..") bad = true;
    }
    if (bad) throw OkfError("archive member escapes target dir (path traversal): " + name);
}

std::string shquote(const std::string& s) { return "\"" + s + "\""; }

// GNU tar treats "C:\..." -f arguments as remote host:path syntax; always run
// tar from the archive's own directory with a relative -f name.
std::string cd_prefix(const fs::path& dir) {
#ifdef _WIN32
    return "cd /d " + shquote(dir.string()) + " && ";
#else
    return "cd " + shquote(dir.string()) + " && ";
#endif
}

int run(const std::string& cmd) { return std::system(cmd.c_str()); }

// Run a command and capture stdout lines.
std::vector<std::string> run_lines(const std::string& cmd) {
#ifdef _WIN32
    FILE* pipe = _popen(cmd.c_str(), "r");
#else
    FILE* pipe = popen(cmd.c_str(), "r");
#endif
    if (!pipe) throw OkfError("cannot run: " + cmd);
    std::vector<std::string> lines;
    std::array<char, 4096> buf{};
    std::string cur;
    while (std::fgets(buf.data(), static_cast<int>(buf.size()), pipe)) {
        cur += buf.data();
        std::size_t nl;
        while ((nl = cur.find('\n')) != std::string::npos) {
            std::string line = cur.substr(0, nl);
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (!line.empty()) lines.push_back(line);
            cur.erase(0, nl + 1);
        }
    }
#ifdef _WIN32
    int rc = _pclose(pipe);
#else
    int rc = pclose(pipe);
#endif
    if (rc != 0) throw OkfError("command failed (" + std::to_string(rc) + "): " + cmd);
    return lines;
}

fs::path make_temp_dir() {
    auto ticks = std::chrono::steady_clock::now().time_since_epoch().count();
    fs::path d = fs::temp_directory_path() /
                 ("okf_cpp_" + std::to_string(static_cast<long long>(ticks)));
    fs::create_directories(d);
    return d;
}

std::string bundle_root(const fs::path& base, const std::string& subdir) {
    if (!subdir.empty()) return (base / subdir).string();
    fs::path cur = base;
    for (int hop = 0; hop < 6; ++hop) {
        bool has_md = false;
        std::vector<fs::path> dirs;
        for (const fs::directory_entry& e : fs::directory_iterator(cur)) {
            std::string name = e.path().filename().string();
            if (!name.empty() && name[0] == '.') continue;
            if (ends_with(lower(name), ".md")) has_md = true;
            if (e.is_directory()) dirs.push_back(e.path());
        }
        if (!has_md && dirs.size() == 1) cur = dirs[0];
        else break;
    }
    return cur.string();
}

}  // namespace

Fetched::~Fetched() {
    if (!tmp.empty()) {
        std::error_code ec;
        fs::remove_all(tmp, ec);
    }
}

Fetched fetch(const std::string& source, const std::string& subdir,
              const std::string& branch) {
    Fetched out;
    if (fs::is_directory(source)) {
        out.dir = fs::canonical(source).string();
        out.kind = "dir";
        return out;
    }
    std::string kind = source_kind(source);
    static const std::regex re_http(R"(^https?://)");
    if (std::regex_search(source, re_http) && kind != "git") {
        throw OkfError("remote archive download is not supported by the C++ binding; "
                       "fetch the archive locally first (git URLs are supported)");
    }
    fs::path tmp = make_temp_dir();
    out.tmp = tmp.string();
    fs::path base;
    if (kind == "git") {
        fs::path repo = tmp / "repo";
        std::string cmd = "git clone --depth 1 ";
        if (!branch.empty()) cmd += "--branch " + shquote(branch) + " ";
        cmd += shquote(source) + " " + shquote(repo.string());
#ifdef _WIN32
        cmd += " >NUL 2>&1";
#else
        cmd += " >/dev/null 2>&1";
#endif
        if (run(cmd) != 0) throw OkfError("git clone failed (is git installed?): " + source);
        base = repo;
    } else {
        fs::path ex = tmp / "x";
        fs::create_directories(ex);
        // Copy the archive next to the extraction dir and run tar with fully
        // RELATIVE paths: GNU tar reads drive-colon -f args as remote
        // host:path syntax, and msys tar mishandles drive-colon -C targets.
        fs::path src_abs = fs::absolute(source);
        std::string arch_name = src_abs.filename().string();
        fs::copy_file(src_abs, tmp / arch_name);
        // Pass 1: member listing -> traversal guard. Pass 2: extract.
        for (const std::string& name :
             run_lines(cd_prefix(tmp) + "tar -tf " + shquote(arch_name))) {
            assert_safe_member(name);
        }
        std::string cmd = cd_prefix(tmp) + "tar -xf " + shquote(arch_name) + " -C x";
        if (run(cmd) != 0) throw OkfError("tar extract failed: " + source);
        base = ex;
    }
    out.dir = bundle_root(base, subdir);
    out.kind = kind;
    return out;
}

}  // namespace okf
