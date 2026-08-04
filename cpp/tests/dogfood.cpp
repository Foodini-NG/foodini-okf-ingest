// Dogfood gate: the repo's own docs/okf-bundle must ingest clean.
// Usage: dogfood_cpp <path-to-docs/okf-bundle>

#include <iostream>

#include "../okf/okf.hpp"

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "usage: dogfood_cpp <bundle-dir>\n";
        return 2;
    }
    okf::Ingested ing = okf::ingest(argv[1]);
    if (ing.summary.errors != 0 || !ing.summary.conformant || ing.summary.n_concepts == 0) {
        std::cout << "FAIL: errors=" << ing.summary.errors
                  << " conformant=" << ing.summary.conformant
                  << " n_concepts=" << ing.summary.n_concepts << "\n";
        return 1;
    }
    std::cout << "PASS — dogfood bundle conformant (" << ing.summary.n_concepts
              << " concepts)\n";
    return 0;
}
