# R/pipeline_profile.R
#
# Where the time and the space go.
#
# tar_meta() has carried `seconds` and `bytes` all along and nothing did
# anything with them beyond printing one target's figure on its own page. Two
# questions they answer well: which targets dominate a run, and which chain of
# them sets the pipeline's floor. The second is the critical path -- no amount
# of parallelism makes a run shorter than its longest dependency chain, so it
# is the only ranking that tells you where optimising actually pays.

#' Longest-duration path through the pipeline
#'
#' The chain of targets whose runtimes sum to the largest total. Since every
#' target on it waits for the one before, its total is a lower bound on the
#' wall-clock time of a full rebuild however many workers you give it.
#'
#' Targets with no recorded runtime count as zero rather than dropping out, so
#' a partially built pipeline still returns a sensible path.
#'
#' @param nodes A data frame or list with `name` and `seconds`.
#' @param edges A data frame with `from` and `to`.
#'
#' @return A character vector of target names, ordered from root to leaf.
#'   Empty when there are no nodes.
#' @export
#' @examples
#' critical_path(
#'   nodes = data.frame(name = c("a", "b", "c"), seconds = c(1, 10, 2)),
#'   edges = data.frame(from = c("a", "a"), to = c("b", "c"))
#' )
critical_path <- function(nodes, edges) {
  name <- as.character(nodes$name)
  if (!length(name)) return(character())

  secs <- as.numeric(nodes$seconds %||% rep(0, length(name)))
  secs[is.na(secs)] <- 0
  names(secs) <- name

  from <- as.character(edges$from %||% character())
  to   <- as.character(edges$to   %||% character())
  keep <- from %in% name & to %in% name
  parents <- split(from[keep], factor(to[keep], levels = name))

  # Longest path by weight, resolved in the same order dag_layout() settles
  # depth: a node is ready once every parent has a total.
  best  <- stats::setNames(rep(NA_real_, length(name)), name)
  len   <- stats::setNames(rep(NA_integer_, length(name)), name)
  via   <- stats::setNames(rep(NA_character_, length(name)), name)
  repeat {
    progressed <- FALSE
    for (n in name) {
      if (!is.na(best[[n]])) next
      p <- parents[[n]]
      if (length(p) == 0) {
        best[[n]] <- secs[[n]]
        len[[n]]  <- 1L
        progressed <- TRUE
      } else if (all(!is.na(best[p]))) {
        top <- p[.argmax2(best[p], len[p])]
        best[[n]] <- best[[top]] + secs[[n]]
        len[[n]]  <- len[[top]] + 1L
        via[[n]]  <- top
        progressed <- TRUE
      }
    }
    if (!anyNA(best) || !progressed) break
  }
  # A cyclic edge list would leave nodes unresolved; drop them rather than loop.
  if (anyNA(best)) { best[is.na(best)] <- -Inf; len[is.na(len)] <- 0L }
  if (all(!is.finite(best))) return(character())

  node <- name[.argmax2(best, len)]
  path <- node
  while (!is.na(via[[node]])) {
    node <- via[[node]]
    path <- c(node, path)
  }
  path
}

#' Summarise where a pipeline spends its time and space
#'
#' @param targets_data Output of [load_targets_data()].
#' @param top Integer. How many targets to rank.
#'
#' @return A list with `total_seconds`, `total_bytes`, `slowest`, `largest`,
#'   `critical_path` (names) and `critical_seconds` (their total). `slowest`
#'   and `largest` are data frames of `name` and the measure, already ordered.
#' @export
pipeline_profile <- function(targets_data, top = 10L) {
  graph <- build_dag_graph(targets_data, include_functions = FALSE)
  if (!length(graph$nodes)) {
    return(list(total_seconds = 0, total_bytes = 0,
                slowest = .profile_empty("seconds"),
                largest = .profile_empty("bytes"),
                critical_path = character(), critical_seconds = 0))
  }

  pick <- function(field) {
    vapply(graph$nodes, function(n) {
      v <- n[[field]]
      if (is.null(v) || is.na(v)) NA_real_ else as.numeric(v)
    }, numeric(1))
  }
  nm    <- vapply(graph$nodes, function(n) n$id, character(1))
  secs  <- pick("seconds")
  bytes <- pick("bytes")

  edges <- data.frame(
    from = vapply(graph$edges, function(e) e$source, character(1)),
    to   = vapply(graph$edges, function(e) e$target, character(1)),
    stringsAsFactors = FALSE
  )
  path <- critical_path(data.frame(name = nm, seconds = secs), edges)

  list(
    total_seconds    = sum(secs,  na.rm = TRUE),
    total_bytes      = sum(bytes, na.rm = TRUE),
    slowest          = .profile_rank(nm, secs,  "seconds", top),
    largest          = .profile_rank(nm, bytes, "bytes",   top),
    critical_path    = path,
    critical_seconds = sum(secs[match(path, nm)], na.rm = TRUE)
  )
}

# ---- private ----------------------------------------------------------------

#' Rank targets by a measure, dropping the ones with nothing recorded
#' @param nm Character vector of names.
#' @param value Numeric vector of the measure.
#' @param field Character. Column name for the measure.
#' @param top Integer. How many rows to keep.
#' @return A two-column data frame, ordered descending.
#' @keywords internal
.profile_rank <- function(nm, value, field, top) {
  ok <- !is.na(value) & value > 0
  if (!any(ok)) return(.profile_empty(field))
  out <- data.frame(name = nm[ok], v = value[ok], stringsAsFactors = FALSE)
  out <- out[order(-out$v), , drop = FALSE]
  out <- out[seq_len(min(nrow(out), top)), , drop = FALSE]
  names(out)[2] <- field
  rownames(out) <- NULL
  out
}

#' Zero-row frame with the right shape
#' @param field Character. Measure column name.
#' @return An empty data frame.
#' @keywords internal
.profile_empty <- function(field) {
  out <- data.frame(name = character(), v = numeric(), stringsAsFactors = FALSE)
  names(out)[2] <- field
  out
}

#' Index of the maximum, ties broken by a second vector
#'
#' Targets with no recorded runtime weigh nothing, so a sink downstream of the
#' heaviest chain ties with its own parent. Without a tie-break the path stops
#' at the last target that actually cost something, which reads as a chain
#' that mysteriously does not reach the end of the pipeline. Preferring the
#' longer chain carries it through to the sink.
#'
#' @param primary Numeric vector to maximise.
#' @param secondary Numeric vector used only on ties.
#' @return An integer index.
#' @keywords internal
.argmax2 <- function(primary, secondary) {
  best <- which(primary == max(primary))
  if (length(best) == 1L) return(best)
  best[which.max(secondary[best])]
}
