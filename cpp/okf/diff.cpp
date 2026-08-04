// Deterministic concept-level diff — mirrors py/okf/diff.py. Pure hash/set
// comparison, all output sorted. Drift mode: diff(DiffSide::from_ingested(i),
// DiffSide::from_dir(d)) answers "what drifted since the ingest" catalog-free.

#include <map>

#include "okf.hpp"

namespace okf {
namespace {

struct ConceptMeta {
    std::optional<std::string> type, title;
    std::string content_hash;
};

struct State {
    std::map<std::string, ConceptMeta> concepts;
    std::set<std::pair<std::string, std::string>> edges, broken;
};

State state_from(const Bundle& b, const std::vector<Link>& lk) {
    State s;
    for (const Concept& c : b.concepts) {
        s.concepts[c.path] = ConceptMeta{c.type, c.title, c.content_hash};
    }
    for (const Link& l : lk) {
        if (l.resolved) s.edges.insert({l.src_path, l.dst_path.value_or("")});
        else s.broken.insert({l.src_path, l.dst_raw});
    }
    return s;
}

State bundle_state(const DiffSide& x) {
    if (x.ingested) return state_from(x.ingested->bundle, x.ingested->links);
    if (x.bundle) return state_from(*x.bundle, links(*x.bundle));
    if (x.dir) {
        Bundle b = read_bundle(*x.dir, "dir");
        return state_from(b, links(b));
    }
    throw OkfError("diff side must be a bundle dir, Bundle, or Ingested");
}

std::vector<FieldChange> field_diff(const State& sa, const State& sb,
                                    std::optional<std::string> ConceptMeta::* field) {
    std::vector<FieldChange> out;
    for (const auto& [path, ma] : sa.concepts) {
        auto it = sb.concepts.find(path);
        if (it == sb.concepts.end()) continue;
        const auto& va = ma.*field;
        const auto& vb = it->second.*field;
        if (va != vb) out.push_back(FieldChange{path, va, vb});
    }
    return out;
}

std::vector<EdgeDelta> pair_diff(const std::set<std::pair<std::string, std::string>>& a,
                                 const std::set<std::pair<std::string, std::string>>& b) {
    std::vector<EdgeDelta> out;
    for (const auto& pr : a) {
        if (!b.count(pr)) out.push_back(EdgeDelta{pr.first, pr.second});
    }
    return out;
}

}  // namespace

Diff diff(const DiffSide& a, const DiffSide& b) {
    State sa = bundle_state(a);
    State sb = bundle_state(b);

    Diff d;
    for (const auto& [path, meta] : sb.concepts) {
        if (!sa.concepts.count(path)) d.added.push_back(path);
    }
    for (const auto& [path, meta] : sa.concepts) {
        auto it = sb.concepts.find(path);
        if (it == sb.concepts.end()) d.removed.push_back(path);
        else if (meta.content_hash != it->second.content_hash) d.changed.push_back(path);
    }
    d.type_changed = field_diff(sa, sb, &ConceptMeta::type);
    d.retitled = field_diff(sa, sb, &ConceptMeta::title);
    d.links_added = pair_diff(sb.edges, sa.edges);
    d.links_removed = pair_diff(sa.edges, sb.edges);
    d.broken_added = pair_diff(sb.broken, sa.broken);
    d.broken_fixed = pair_diff(sa.broken, sb.broken);
    d.identical = d.added.empty() && d.removed.empty() && d.changed.empty() &&
                  d.type_changed.empty() && d.retitled.empty() && d.links_added.empty() &&
                  d.links_removed.empty() && d.broken_added.empty() && d.broken_fixed.empty();
    return d;
}

}  // namespace okf
