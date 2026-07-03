# ============================================================================
# okf -- rank: Personalized PageRank over the concept graph.
#
# Ranks every concept by link-structure relevance to a start concept, using
# EXACT power iteration (not Monte-Carlo sampling): deterministic -- the same
# bundle and start always yield the same scores. The walk runs on the
# UNDIRECTED resolved-link graph (a page and the pages that cite it are
# mutually relevant, matching okf_context / okf_impact), with the classic
# teleport: with probability 1-damping the walker returns to `start`.
# Dangling mass (walker on an isolated node) also returns to `start`.
#
# This upgrades neighborhood selection from "everything at depth 1 is equal"
# (BFS) to relevance-weighted: hubs stop drowning out the pages that actually
# matter to the topic. okf_context(rank = "ppr") budget-fills by these scores.
#
# Mirrors py/okf/graph.py::ppr.
# ============================================================================

#' Personalized PageRank scores for the concept graph.
#'
#' Exact power-iteration PPR seeded at `start`, over the undirected
#' resolved-link graph. Deterministic: no sampling, fixed lexicographic node
#' order, scores rounded to 10 decimals. Reserved pages (index.md / log.md)
#' participate in the walk (they carry real link structure) but can be
#' filtered by the caller.
#'
#' @param con An open DuckDB connection to an okf catalog.
#' @param start Concept path to personalize on.
#' @param damping Continue-walk probability (teleport = 1 - damping).
#' @param tol L1 convergence tolerance.
#' @param max_iter Iteration cap.
#' @param k Return the top k concepts (Inf for all with score > 0).
#' @return A data.frame of `path`, `score`, `title`, `reserved`, sorted by
#'   score descending (ties broken by path).
#' @export
okf_rank <- function(con, start, damping = 0.85, tol = 1e-12,
                     max_iter = 200L, k = 20L) {
  cps <- DBI::dbGetQuery(con, "SELECT path, title, reserved FROM okf_concept ORDER BY path")
  lks <- DBI::dbGetQuery(con,
    "SELECT DISTINCT src_path, dst_path FROM okf_link WHERE resolved")
  nodes <- cps$path
  if (!(start %in% nodes)) stop("start concept not found: ", start)
  n <- length(nodes)
  idx <- stats::setNames(seq_len(n), nodes)

  # undirected, deduplicated, no self-loops
  ekey <- unique(c(paste(lks$src_path, lks$dst_path, sep = "\r"),
                   paste(lks$dst_path, lks$src_path, sep = "\r")))
  parts <- strsplit(ekey, "\r", fixed = TRUE)
  src <- vapply(parts, `[[`, "", 1); dst <- vapply(parts, `[[`, "", 2)
  keep <- src != dst & src %in% nodes & dst %in% nodes
  src_i <- unname(idx[src[keep]]); dst_i <- unname(idx[dst[keep]])
  deg <- tabulate(src_i, nbins = n)

  seed <- numeric(n); seed[idx[[start]]] <- 1
  p <- seed
  for (it in seq_len(max_iter)) {
    contrib <- numeric(n)
    if (length(src_i)) {
      w <- p[src_i] / deg[src_i]
      acc <- rowsum(w, dst_i)
      contrib[as.integer(rownames(acc))] <- acc[, 1]
    }
    dangling <- sum(p[deg == 0])
    np <- (1 - damping) * seed + damping * (contrib + dangling * seed)
    if (sum(abs(np - p)) < tol) { p <- np; break }
    p <- np
  }

  out <- data.frame(path = nodes, score = round(p, 10),
                    title = cps$title, reserved = as.logical(cps$reserved),
                    stringsAsFactors = FALSE)
  out <- out[out$score > 0, , drop = FALSE]
  out <- out[order(-out$score, out$path), , drop = FALSE]
  rownames(out) <- NULL
  utils::head(out, if (is.finite(k)) as.integer(k) else nrow(out))
}
