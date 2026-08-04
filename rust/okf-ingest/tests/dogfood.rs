//! Dogfood gate: the repo's own docs/okf-bundle must ingest clean (the
//! validate-strict half of CI's dogfood step; doctor stays R/Python-only).

use std::path::Path;

use okf_ingest::ingest;

#[test]
fn docs_bundle_is_conformant() {
    let bundle = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs/okf-bundle");
    let ing = ingest(bundle.to_str().unwrap()).unwrap();
    assert_eq!(
        ing.summary.errors, 0,
        "docs/okf-bundle has validation errors"
    );
    assert!(ing.summary.conformant, "docs/okf-bundle is not conformant");
    assert!(ing.summary.n_concepts > 0);
}
