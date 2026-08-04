// Deterministic graph ranking — mirrors py/okf/graph.py::seeds/ppr.
//
// Floating-point parity depends on accumulation ORDER (pinned here: edges in
// sorted (src,dst) index order; dangling mass and the L1 convergence sum in
// ascending node index) and on the build NEVER enabling fast-math or FMA
// contraction (CMake sets -ffp-contract=off / /fp:precise).

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <regex>

#include "okf.hpp"

namespace okf {
namespace {

// Fixed stopword list — byte-for-byte OKF_STOPWORDS of py/okf/graph.py (37).
const std::set<std::string>& stopwords() {
    static const std::set<std::string> sw = {
        "the",   "and",   "for",   "are",   "was",   "were",  "with",  "that",
        "this",  "from",  "how",   "what",  "when",  "where", "which", "does",
        "did",   "can",   "could", "should", "would", "will",  "has",   "have",
        "had",   "not",   "its",   "our",   "your",  "their", "about", "into",
        "over",  "under", "why",   "who",   "whom"};
    return sw;
}

std::string lower_ascii(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

}  // namespace

double round_dec(double x, int digits) {
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.*f", digits, x);
    return std::strtod(buf, nullptr);
}

std::vector<Seed> seeds(const Ingested& ing, const std::string& query, std::size_t k) {
    static const std::regex re_token("[a-z0-9]+");
    std::string q = lower_ascii(query);
    std::set<std::string> toks;
    for (auto it = std::sregex_iterator(q.begin(), q.end(), re_token);
         it != std::sregex_iterator(); ++it) {
        std::string t = it->str();
        if (t.size() >= 3 && !stopwords().count(t)) toks.insert(t);
    }
    std::vector<Seed> out;
    for (const Concept& c : ing.bundle.concepts) {
        if (c.reserved) continue;
        std::string ttl = lower_ascii(c.title.value_or(""));
        std::string dsc = lower_ascii(c.description.value_or(""));
        std::string tgs = c.tags.is_null() ? "" : lower_ascii(c.tags.dump());
        std::string bod = lower_ascii(c.body);
        long sc = 0;
        for (const std::string& t : toks) {
            if (ttl.find(t) != std::string::npos) sc += 3;
            if (dsc.find(t) != std::string::npos || tgs.find(t) != std::string::npos) sc += 2;
            if (bod.find(t) != std::string::npos) sc += 1;
        }
        if (sc > 0) out.push_back(Seed{c.path, static_cast<double>(sc), c.title});
    }
    std::sort(out.begin(), out.end(), [](const Seed& a, const Seed& b) {
        if (a.score != b.score) return a.score > b.score;
        return a.path < b.path;
    });
    if (out.size() > k) out.resize(k);
    return out;
}

std::vector<RankRow> ppr(const Ingested& ing, const std::vector<std::string>& starts,
                         const PprOptions& opts) {
    const std::vector<Concept>& concepts = ing.bundle.concepts;  // sorted by path
    std::map<std::string, std::size_t> idx;
    for (std::size_t i = 0; i < concepts.size(); ++i) idx[concepts[i].path] = i;

    std::string missing;
    for (const std::string& s : starts) {
        if (!idx.count(s)) missing += (missing.empty() ? "" : ", ") + s;
    }
    if (!missing.empty()) throw OkfError("start concept not found: " + missing);
    std::vector<double> weights = opts.weights;
    if (weights.empty()) weights.assign(starts.size(), 1.0);
    double wsum = 0.0;
    bool wneg = false;
    for (double w : weights) {
        wsum += w;
        if (w < 0.0) wneg = true;
    }
    if (weights.size() != starts.size() || wneg || wsum <= 0.0) {
        throw OkfError("weights must be non-negative, same length as start, positive sum");
    }

    const std::size_t n = concepts.size();
    // Distinct resolved links -> undirected edge set; std::set iterates in
    // sorted (s,d) order — Python's sorted(edges) for free.
    std::set<std::pair<std::size_t, std::size_t>> edges;
    for (const Link& l : ing.links) {
        if (!l.resolved || !l.dst_path) continue;
        if (l.src_path == *l.dst_path) continue;
        auto si = idx.find(l.src_path);
        auto di = idx.find(*l.dst_path);
        if (si == idx.end() || di == idx.end()) continue;
        edges.insert({si->second, di->second});
        edges.insert({di->second, si->second});
    }
    std::vector<std::size_t> deg(n, 0);
    for (const auto& e : edges) ++deg[e.first];

    std::vector<double> seed(n, 0.0);
    for (std::size_t j = 0; j < starts.size(); ++j) seed[idx[starts[j]]] += weights[j];
    double tot = 0.0;
    for (std::size_t i = 0; i < n; ++i) tot += seed[i];
    for (std::size_t i = 0; i < n; ++i) seed[i] /= tot;

    std::vector<double> p = seed;
    for (int iter = 0; iter < opts.max_iter; ++iter) {
        std::vector<double> contrib(n, 0.0);
        for (const auto& e : edges) {  // fixed order -> deterministic fp
            if (p[e.first] != 0.0) {
                contrib[e.second] += p[e.first] / static_cast<double>(deg[e.first]);
            }
        }
        double dangling = 0.0;
        for (std::size_t i = 0; i < n; ++i) {
            if (deg[i] == 0) dangling += p[i];
        }
        std::vector<double> np(n, 0.0);
        for (std::size_t i = 0; i < n; ++i) {
            np[i] = (1.0 - opts.damping) * seed[i] +
                    opts.damping * (contrib[i] + dangling * seed[i]);
        }
        double delta = 0.0;
        for (std::size_t i = 0; i < n; ++i) delta += std::abs(np[i] - p[i]);
        p = std::move(np);
        if (delta < opts.tol) break;
    }

    std::vector<RankRow> rows;
    for (std::size_t i = 0; i < n; ++i) {
        double score = round_dec(p[i], 10);
        if (score > 0.0) {
            rows.push_back(RankRow{concepts[i].path, score, concepts[i].title,
                                   concepts[i].reserved});
        }
    }
    std::sort(rows.begin(), rows.end(), [](const RankRow& a, const RankRow& b) {
        if (a.score != b.score) return a.score > b.score;
        return a.path < b.path;
    });
    if (opts.k > 0 && rows.size() > static_cast<std::size_t>(opts.k)) rows.resize(opts.k);
    return rows;
}

}  // namespace okf
