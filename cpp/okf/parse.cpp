// Frontmatter parsing + body normalization — mirrors py/okf/okf.py::parse_file.
//
// Parity notes:
// - Lines split like Python splitlines() / R readLines(): EOL stripped
//   (including a trailing newline, and the CR of CRLF), so the body — and
//   therefore content_hash — is byte-identical across bindings.
// - YAML via rapidyaml: scalars are raw text (no implicit typing at parse
//   time), so `timestamp: 2026-06-22T00:00:00Z` stays a verbatim string with
//   no custom-loader work, and `okf_version: 0.1` keeps its "0.1" text.
//   Frontmatter scalars therefore land in JSON as strings (semantically
//   equal, not byte-locked — see docs/ARCHITECTURE.md).

#include <mutex>

#include <ryml.hpp>
#include <ryml_std.hpp>

#include "okf.hpp"
#include "sha1.hpp"

namespace okf {
namespace {

std::vector<std::string> split_lines(const std::string& text) {
    std::vector<std::string> lines;
    std::size_t start = 0;
    while (start <= text.size()) {
        std::size_t nl = text.find('\n', start);
        if (nl == std::string::npos) {
            if (start < text.size()) lines.push_back(text.substr(start));
            break;
        }
        std::string line = text.substr(start, nl - start);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        lines.push_back(std::move(line));
        start = nl + 1;
    }
    return lines;
}

bool is_fence(const std::string& line) {  // ^---\s*$
    if (line.rfind("---", 0) != 0) return false;
    return line.find_first_not_of(" \t\f\v\r", 3) == std::string::npos;
}

bool is_blank(const std::string& line) {
    return line.find_first_not_of(" \t\f\v\r") == std::string::npos;
}

std::string join(const std::vector<std::string>& lines, std::size_t from, std::size_t to) {
    std::string out;
    for (std::size_t i = from; i < to; ++i) {
        if (i > from) out.push_back('\n');
        out += lines[i];
    }
    return out;
}

// rapidyaml aborts on parse errors by default; route errors into exceptions
// once, process-wide.
void install_ryml_error_handler() {
    static std::once_flag flag;
    std::call_once(flag, [] {
        ryml::Callbacks cb = ryml::get_callbacks();
        cb.m_error = [](const char* msg, std::size_t len, ryml::Location, void*) {
            throw std::runtime_error(std::string(msg, len));
        };
        ryml::set_callbacks(cb);
    });
}

json yaml_to_json(ryml::ConstNodeRef n) {
    if (n.is_map()) {
        json obj = json::object();
        for (ryml::ConstNodeRef ch : n.children()) {
            std::string key(ch.key().str, ch.key().len);
            obj[key] = yaml_to_json(ch);
        }
        return obj;
    }
    if (n.is_seq()) {
        json arr = json::array();
        for (ryml::ConstNodeRef ch : n.children()) arr.push_back(yaml_to_json(ch));
        return arr;
    }
    if (!n.has_val() || n.val_is_null()) return nullptr;
    return std::string(n.val().str, n.val().len);
}

}  // namespace

Parsed parse_text(const std::string& text) {
    install_ryml_error_handler();
    std::vector<std::string> raw = split_lines(text);
    std::string txt = join(raw, 0, raw.size());
    std::size_t i = 0;
    while (i < raw.size() && is_blank(raw[i])) ++i;
    if (i >= raw.size() || !is_fence(raw[i])) {
        return Parsed{nullptr, txt, std::string("no_frontmatter")};
    }
    std::size_t opn = i, close = raw.size();
    for (std::size_t j = opn + 1; j < raw.size(); ++j) {
        if (is_fence(raw[j])) { close = j; break; }
    }
    if (close == raw.size()) {
        return Parsed{nullptr, txt, std::string("unclosed_frontmatter")};
    }
    std::string fm = join(raw, opn + 1, close);
    std::string body = close + 1 < raw.size() ? join(raw, close + 1, raw.size()) : "";
    json meta = nullptr;
    try {
        ryml::Tree tree = ryml::parse_in_arena(ryml::to_csubstr(fm));
        ryml::ConstNodeRef root = tree.rootref();
        if (root.is_map()) meta = yaml_to_json(root);
    } catch (const std::exception&) {
        meta = nullptr;
    }
    if (!meta.is_object()) {
        return Parsed{nullptr, std::move(body), std::string("yaml_parse_error")};
    }
    return Parsed{std::move(meta), std::move(body), std::nullopt};
}

std::string content_hash(const std::string& body) { return detail::sha1_hex(body); }

}  // namespace okf
