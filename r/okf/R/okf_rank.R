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
#' @param start Concept path(s) to personalize on. A vector spreads the
#'   teleport across several seeds (see `weights`) -- this is how
#'   [okf_context()] serves free-text queries via [okf_seeds()].
#' @param damping Continue-walk probability (teleport = 1 - damping).
#' @param tol L1 convergence tolerance.
#' @param max_iter Iteration cap.
#' @param k Return the top k concepts (Inf for all with score > 0).
#' @param weights Optional non-negative weights for multiple `start` seeds
#'   (normalized internally; default equal).
#' @return A data.frame of `path`, `score`, `title`, `reserved`, sorted by
#'   score descending (ties broken by path).
#' @export
okf_rank <- function(con, start, damping = 0.85, tol = 1e-12,
                     max_iter = 200L, k = 20L, weights = NULL) {
  cps <- DBI::dbGetQuery(con, "SELECT path, title, reserved FROM okf_concept ORDER BY path")
  lks <- DBI::dbGetQuery(con,
    "SELECT DISTINCT src_path, dst_path FROM okf_link WHERE resolved")
  nodes <- cps$path
  missing <- setdiff(start, nodes)
  if (length(missing)) stop("start concept not found: ", paste(missing, collapse = ", "))
  if (is.null(weights)) weights <- rep(1, length(start))
  if (length(weights) != length(start) || any(weights < 0) || sum(weights) <= 0)
    stop("weights must be non-negative, same length as start, with positive sum")
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

  seed <- numeric(n)
  for (j in seq_along(start)) seed[idx[[start[j]]]] <- seed[idx[[start[j]]]] + weights[j]
  seed <- seed / sum(seed)
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

# Fixed stopword set, duplicated verbatim in py/okf/graph.py -- keep in sync.
OKF_STOPWORDS <- c("the", "and", "for", "are", "was", "were", "with", "that",
                   "this", "from", "how", "what", "when", "where", "which",
                   "does", "did", "can", "could", "should", "would", "will",
                   "has", "have", "had", "not", "its", "our", "your", "their",
                   "about", "into", "over", "under", "why", "who", "whom")

#' Deterministic lexical seed selection for a free-text query.
#'
#' Tokenizes `query` (lowercase alphanumeric runs, length >= 3, fixed stopword
#' list) and scores every non-reserved concept by simple term presence:
#' +3 per distinct token found in the title, +2 in the description or tags,
#' +1 in the body.
#' No embeddings, no model -- the same query always yields the same seeds.
#' Feed the result to [okf_rank()] as multi-seed personalization (done for you
#' by `okf_context(query = ...)`).
#'
#' @param con An open DuckDB connection to an okf catalog.
#' @param query Free-text query.
#' @param k Number of seed concepts to return.
#' @return A data.frame of `path`, `score`, `title` for concepts with score >
#'   0, sorted by score descending (ties by path); zero rows if nothing
#'   matches.
#' @export
okf_seeds <- function(con, query, k = 5L) {
  toks <- regmatches(tolower(query), gregexpr("[a-z0-9]+", tolower(query)))[[1]]
  toks <- sort(unique(toks[nchar(toks) >= 3 & !(toks %in% OKF_STOPWORDS)]))
  cps <- DBI::dbGetQuery(con, paste(
    "SELECT path, title, description, tags, body FROM okf_concept",
    "WHERE reserved = FALSE ORDER BY path"))
  if (!length(toks) || !nrow(cps)) {
    return(data.frame(path = character(0), score = numeric(0),
                      title = character(0), stringsAsFactors = FALSE))
  }
  score <- vapply(seq_len(nrow(cps)), function(i) {
    ttl <- tolower(cps$title[i] %||% ""); tgs <- tolower(cps$tags[i] %||% "")
    dsc <- tolower(cps$description[i] %||% ""); bod <- tolower(cps$body[i] %||% "")
    s <- 0
    for (t in toks) {
      if (!is.na(ttl) && grepl(t, ttl, fixed = TRUE)) s <- s + 3
      if ((!is.na(dsc) && grepl(t, dsc, fixed = TRUE)) ||
          (!is.na(tgs) && grepl(t, tgs, fixed = TRUE))) s <- s + 2
      if (!is.na(bod) && grepl(t, bod, fixed = TRUE)) s <- s + 1
    }
    s
  }, numeric(1))
  out <- data.frame(path = cps$path, score = score, title = cps$title,
                    stringsAsFactors = FALSE)
  out <- out[out$score > 0, , drop = FALSE]
  out <- out[order(-out$score, out$path), , drop = FALSE]
  rownames(out) <- NULL
  utils::head(out, as.integer(k))
}
