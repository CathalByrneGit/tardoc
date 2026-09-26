# R/target_branches.R
#
# Per-branch detail for dynamically branched targets.
#
# A node showing "200 branches" answers the wrong question. On a pipeline that
# maps over 200 files the thing a reader needs is *which* branch failed, and
# how the work is distributed across them. targets already records it:
# tar_meta() returns one row per branch, carrying that branch's own seconds,
# bytes, error and warnings, with `parent` naming the stem it belongs to.
# Branch names are content hashes (`chunk_d5a8af7b29af3a3e`), so they are
# indexed for display against the parent's ordered `children`.

#' Per-branch rows for one dynamic target
#'
#' @param name Character. The parent target's name.
#' @param meta The `meta` tibble from [load_targets_data()], which already
#'   contains branch rows -- `tar_meta()` returns them alongside stems.
#'
#' @return A data frame with one row per branch: `index`, `name`, `status`,
#'   `seconds`, `bytes`, `error`, `warnings`. Zero rows when the target is not
#'   branched or has never been built.
#' @keywords internal
.target_branches <- function(name, meta) {
  empty <- data.frame(
    index = integer(), name = character(), status = character(),
    seconds = numeric(), bytes = numeric(),
    error = character(), warnings = character(),
    stringsAsFactors = FALSE
  )
  if (is.null(meta) || !nrow(meta) || !"parent" %in% names(meta)) return(empty)

  rows <- meta[!is.na(meta$parent) & meta$parent == name, , drop = FALSE]
  if (!nrow(rows)) return(empty)

  # The parent's `children` gives branch order; tar_meta() rows do not
  # necessarily arrive in it, and "branch 3 of 200" is only meaningful against
  # the declared order.
  order_from <- .branch_order(name, meta)
  idx <- match(rows$name, order_from)
  if (anyNA(idx)) idx[is.na(idx)] <- seq_len(sum(is.na(idx))) + length(order_from)
  rows <- rows[order(idx), , drop = FALSE]

  col <- function(nm, default) {
    if (nm %in% names(rows)) rows[[nm]] else rep(default, nrow(rows))
  }
  err  <- as.character(col("error", NA_character_))
  warn <- as.character(col("warnings", NA_character_))

  data.frame(
    index    = seq_len(nrow(rows)),
    name     = as.character(rows$name),
    status   = ifelse(is.na(err), "uptodate", "errored"),
    seconds  = as.numeric(col("seconds", NA_real_)),
    bytes    = as.numeric(col("bytes", NA_real_)),
    error    = ifelse(is.na(err),  "", err),
    warnings = ifelse(is.na(warn), "", warn),
    stringsAsFactors = FALSE
  )
}

#' The parent's declared branch order
#' @param name Character. Parent target name.
#' @param meta The `meta` tibble.
#' @return A character vector of branch names, possibly empty.
#' @keywords internal
.branch_order <- function(name, meta) {
  prow <- meta[meta$name == name, , drop = FALSE]
  if (!nrow(prow) || !"children" %in% names(prow)) return(character())
  kids <- prow$children[[1]]
  if (is.null(kids)) character() else as.character(kids[!is.na(kids)])
}

#' Roll branch rows up into the numbers worth showing first
#'
#' @param branches A data frame from [.target_branches()].
#' @return A list with `n`, `n_errored`, `seconds`, `bytes`, and `slowest` --
#'   the index of the longest-running branch, or `NA`.
#' @keywords internal
.branch_summary <- function(branches) {
  if (!nrow(branches)) {
    return(list(n = 0L, n_errored = 0L, seconds = NA_real_, bytes = NA_real_,
                slowest = NA_integer_))
  }
  secs <- branches$seconds
  list(
    n         = nrow(branches),
    n_errored = sum(branches$status == "errored"),
    seconds   = if (all(is.na(secs))) NA_real_ else sum(secs, na.rm = TRUE),
    bytes     = if (all(is.na(branches$bytes))) NA_real_ else
                  sum(branches$bytes, na.rm = TRUE),
    slowest   = if (all(is.na(secs))) NA_integer_ else
                  branches$index[which.max(replace(secs, is.na(secs), -Inf))]
  )
}

#' Render the branches section of a target page
#'
#' Failed branches come first and in full; the rest are summarised. A target
#' mapping over 200 files should not put 200 rows on the page, but it must
#' never hide the three that failed.
#'
#' @param branches A data frame from [.target_branches()].
#' @param max_rows Integer. How many healthy branches to list.
#' @return A markdown string, empty when there are no branch rows.
#' @keywords internal
.branches_section <- function(branches, max_rows = 20L) {
  if (!nrow(branches)) return("")
  s <- .branch_summary(branches)

  head_line <- paste0(
    s$n, if (s$n == 1) " branch" else " branches",
    if (s$n_errored > 0) paste0(", **", s$n_errored, " errored**") else
      ", all built cleanly",
    if (!is.na(s$seconds)) paste0(" &mdash; ", .fmt_seconds(s$seconds),
                                  " total") else ""
  )

  failed  <- branches[branches$status == "errored", , drop = FALSE]
  healthy <- branches[branches$status != "errored", , drop = FALSE]
  shown   <- healthy[seq_len(min(nrow(healthy), max_rows)), , drop = FALSE]
  listed  <- rbind(failed, shown)

  rows <- paste0(
    "| ", listed$index, " | ", listed$status, " | ",
    vapply(listed$seconds, .fmt_seconds, ""), " | ",
    vapply(listed$bytes, .fmt_bytes, ""), " | ",
    ifelse(nzchar(listed$error), paste0("`", listed$error, "`"), ""), " |",
    collapse = "\n"
  )

  omitted <- nrow(healthy) - nrow(shown)
  paste0(
    "## Branches\n\n", head_line, "\n\n",
    "| # | Status | Runtime | Size | Error |\n|---:|---|---|---|---|\n",
    rows, "\n",
    if (omitted > 0)
      paste0("\n_", omitted, " further branches not listed._\n") else "",
    "\n"
  )
}
