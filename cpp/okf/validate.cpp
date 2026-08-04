// OKF validation rules — mirrors py/okf/okf.py::validate verbatim.
// Permissive consumption: recommended-field issues are warnings; only
// unparseable frontmatter / missing type are errors.

#include <regex>

#include "okf.hpp"

namespace okf {

std::vector<Finding> validate(const Bundle& b) {
    static const std::regex re_iso(R"(^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$)");
    std::vector<Finding> out;
    auto add = [&out](const std::string& path, const char* sev, const char* rule,
                      const std::string& msg) {
        out.push_back(Finding{path, sev, rule, msg});
    };

    for (const Concept& c : b.concepts) {
        if (c.reserved) continue;
        if (c.parse_error) {
            add(c.path, "error", "frontmatter_unparseable",
                "no parseable frontmatter (" + *c.parse_error + ")");
            continue;
        }
        if (!c.type || c.type->empty()) {
            add(c.path, "error", "missing_type", "frontmatter has no non-empty type");
        }
        if (!c.title) add(c.path, "warn", "missing_title", "recommended field title absent");
        if (!c.description) {
            add(c.path, "warn", "missing_description", "recommended field description absent");
        }
        if (!c.timestamp) {
            add(c.path, "warn", "missing_timestamp", "recommended field timestamp absent");
        } else if (!std::regex_match(*c.timestamp, re_iso)) {
            add(c.path, "warn", "timestamp_not_iso8601",
                "timestamp not ISO-8601: " + *c.timestamp);
        }
    }

    std::vector<Link> lk_all = links(b);
    for (const Link& lk : lk_all) {
        if (!lk.resolved) {
            add(lk.src_path, "warn", "broken_link", "unresolved link: " + lk.dst_raw);
        }
    }

    // orphan concepts: non-reserved, parseable, no inbound link
    std::set<std::string> inbound;
    for (const Link& lk : lk_all) {
        if (lk.dst_path) inbound.insert(*lk.dst_path);
    }
    for (const Concept& c : b.concepts) {
        if (c.reserved || c.parse_error) continue;
        if (!inbound.count(c.path)) {
            add(c.path, "warn", "orphan", "no inbound links (orphan concept)");
        }
    }
    return out;
}

}  // namespace okf
