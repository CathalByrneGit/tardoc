# R/target_facts.R
#
# One description of a target, shared by everything that renders one.
#
# Four places used to derive status independently -- the target page, the graph
# node, the search index and the analytics data -- and each did it as
# `if (is.na(error)) "uptodate" else "errored"`. That reads "did not error the
# last time it ran", which is not what "up to date" means to a reader: a target
# whose upstream changed an hour ago still claimed to be current. It also meant
# the graph's inspect panel showed a dozen fields the target's own page did not.

#' Classify a target's freshness
#'
#' Four states, in the order they are checked:
#'
#' \describe{
#'   \item{`errored`}{The last build recorded an error.}
#'   \item{`outdated`}{[targets::tar_outdated()] lists it -- its command, its
#'     dependencies or an upstream target changed since it was built.}
#'   \item{`uptodate`}{Built, current, no error.}
#'   \item{`unbuilt`}{No store, or no metadata row: never run.}
#' }
#'
#' @param name      Character. Target name.
#' @param meta      The `meta` tibble from [load_targets_data()].
#' @param outdated  Character vector of outdated target names, or `NULL` when
#'   the check was skipped or unavailable.
#' @param has_store Logical. Whether a `_targets` store was found.
#'
#' @return One of `"errored"`, `"outdated"`, `"uptodate"`, `"unbuilt"`.
#' @keywords internal
.target_status <- function(name, meta, outdated = NULL, has_store = TRUE) {
  row <- meta[meta$name == name, , drop = FALSE]

  # A pattern target's own row carries no `time` -- only its branches do -- so
  # a branched target that has run looks unbuilt unless its branches are
  # counted. Its errors live on the branch rows too: the parent stays NA while
  # a branch fails, and a target with a failed branch has not succeeded.
  kids <- if ("parent" %in% names(meta)) {
    meta[!is.na(meta$parent) & meta$parent == name, , drop = FALSE]
  } else {
    meta[0, , drop = FALSE]
  }

  own_error <- nrow(row) > 0 && "error" %in% names(row) && !is.na(row$error[1])
  kid_error <- nrow(kids) > 0 && "error" %in% names(kids) && any(!is.na(kids$error))
  if (own_error || kid_error) return("errored")

  has_time <- nrow(row) > 0 && "time" %in% names(row) && !is.na(row$time[1])
  built    <- has_store && (has_time || nrow(kids) > 0)
  if (!built) return("unbuilt")
  if (!is.null(outdated) && name %in% outdated) return("outdated")
  "uptodate"
}

#' Human-readable form of a status
#' @param status One of the values from [.target_status()].
#' @return A display string.
#' @keywords internal
.status_label <- function(status) {
  switch(status,
    errored  = "Errored",
    outdated = "Outdated",
    uptodate = "Up-to-date",
    unbuilt  = "Not built",
    status
  )
}

#' Everything known about one target
#'
#' The single source of truth behind the target's markdown page, its node and
#' inspect panel in the graph, the search index and the analytics tables. Any
#' field added here reaches all of them.
#'
#' @param name         Character. Target (or function) name.
#' @param targets_data Output of [load_targets_data()].
#' @param kind         Character. Vertex type (`stem`, `pattern`, `function`).
#'   Looked up from the network when `NULL`.
#'
#' @return A named list. Character fields are `""` when absent rather than
#'   `NA`, so templates can test them with `nzchar()`; numeric fields are `NA`.
#' @keywords internal
.target_facts <- function(name, targets_data, kind = NULL) {
  meta  <- targets_data$meta
  mrow  <- meta[meta$name == name, , drop = FALSE]
  frow  <- targets_data$manifest[targets_data$manifest$name == name, ,
                                 drop = FALSE]
  verts <- as.data.frame(targets_data$network$vertices,
                         stringsAsFactors = FALSE)
  vrow  <- verts[verts$name == name, , drop = FALSE]

  chr1 <- function(x) if (length(x) == 0 || is.na(x[1])) "" else as.character(x[1])
  fld  <- function(df, col) if (nrow(df) && col %in% names(df)) chr1(df[[col]]) else ""
  num1 <- function(df, col) {
    if (nrow(df) && col %in% names(df) && !is.na(df[[col]][1])) {
      as.numeric(df[[col]][1])
    } else {
      NA_real_
    }
  }

  if (is.null(kind)) kind <- fld(vrow, "type")
  if (!nzchar(kind)) kind <- "stem"

  status <- if (kind == "function") {
    "function"
  } else {
    .target_status(name, meta, targets_data$outdated, isTRUE(targets_data$has_store))
  }

  # Branching comes from the vertex type or the manifest's `pattern` -- the
  # target's own declaration, known without a store. meta$children is only ever
  # a count, never the signal: targets records branch names against a plain stem
  # that a pattern maps over.
  pattern  <- fld(frow, "pattern")
  branched <- kind == "pattern" || nzchar(pattern)
  n_branch <- num1(vrow, "branches")
  if (is.na(n_branch) && branched && nrow(mrow) && "children" %in% names(mrow)) {
    kids <- mrow$children[[1]]
    n_branch <- if (is.null(kids)) 0 else sum(!is.na(kids))
  }
  if (is.na(n_branch) || !branched) n_branch <- 0

  desc <- fld(frow, "description")
  if (!nzchar(desc)) desc <- fld(vrow, "description")

  secs  <- num1(vrow, "seconds"); if (is.na(secs))  secs  <- num1(mrow, "seconds")
  bytes <- num1(vrow, "bytes");   if (is.na(bytes)) bytes <- num1(mrow, "bytes")

  list(
    name         = name,
    kind         = kind,
    status       = status,
    status_label = .status_label(status),
    progress     = .last_run_progress(name, targets_data$progress),
    description  = desc,
    command      = fld(frow, "command"),
    pattern      = pattern,
    branched     = branched,
    n_branches   = as.integer(n_branch),
    error        = fld(mrow, "error"),
    warnings     = fld(mrow, "warnings"),
    format       = fld(frow, "format"),
    repository   = fld(frow, "repository"),
    iteration    = fld(frow, "iteration"),
    last_built   = if (nrow(mrow)) chr1(as.character(mrow$time)) else "",
    seconds      = secs,
    bytes        = bytes
  )
}

#' What the target did on the most recent `tar_make()`
#'
#' Distinct from status: "skipped" last run and "up to date" now are different
#' claims, and a target can be skipped by a run that never reached it.
#'
#' @param name     Character. Target name.
#' @param progress The `progress` tibble from [load_targets_data()], or `NULL`.
#' @return A string such as `"built"` or `"skipped"`, `""` when unknown.
#' @keywords internal
.last_run_progress <- function(name, progress) {
  if (is.null(progress) || !nrow(progress) ||
      !all(c("name", "progress") %in% names(progress))) {
    return("")
  }
  row <- progress[progress$name == name, , drop = FALSE]
  if (!nrow(row) || is.na(row$progress[1])) "" else as.character(row$progress[1])
}
