# R/run_history.R
#
# What changed since last time.
#
# tar_meta() reports the current state and nothing else: every docs build
# overwrote the previous figures, so "did that target get slower?" or "what
# actually rebuilt?" had no answer. A snapshot per build, appended to a small
# JSON file beside the docs, is enough to answer both -- and it lives in the
# site directory rather than the database, because document_targets() does not
# build a database and tier 1 is where most people read these docs.

#' Append a snapshot of the current run to the history file
#'
#' Writes `history.json` in `cfg$site_path`: one entry per docs build, each
#' recording every target's status, build time, runtime and size. Snapshots
#' are only appended when something actually differs from the previous one, so
#' repeated builds of an unchanged pipeline do not pad the file.
#'
#' @param targets_data Output of [load_targets_data()].
#' @param cfg A site config list.
#' @param max_runs Integer. How many snapshots to keep; the oldest are dropped.
#'
#' @return The full history, invisibly: a list of snapshots, oldest first.
#' @export
record_run_snapshot <- function(targets_data, cfg, max_runs = 50L) {
  path    <- file.path(cfg$site_path, "history.json")
  history <- read_run_history(cfg)

  snapshot <- list(
    recorded = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    targets  = .snapshot_targets(targets_data)
  )

  # An unchanged pipeline documented three times is one state, not three.
  # Compared on a normalised key rather than with identical(): the stored
  # snapshot has been through JSON, which turns a whole-number `bytes` into an
  # integer while the fresh one is a double, and identical() would never match.
  if (length(history) &&
      identical(.snapshot_key(history[[length(history)]]$targets),
                .snapshot_key(snapshot$targets))) {
    return(invisible(history))
  }

  history <- c(history, list(snapshot))
  if (length(history) > max_runs) {
    history <- history[seq(length(history) - max_runs + 1L, length(history))]
  }

  writeLines(jsonlite::toJSON(history, auto_unbox = TRUE, null = "null"), path)
  message("Run history: ", length(history),
          if (length(history) == 1) " snapshot" else " snapshots", " in ", path)
  invisible(history)
}

#' Read the recorded run history
#'
#' @param cfg A site config list.
#' @return A list of snapshots, oldest first; empty when there is no history
#'   file or it cannot be parsed.
#' @export
read_run_history <- function(cfg) {
  path <- file.path(cfg$site_path, "history.json")
  if (!file.exists(path)) return(list())
  tryCatch(
    jsonlite::fromJSON(path, simplifyDataFrame = FALSE),
    error = function(e) {
      message("Could not read run history (", conditionMessage(e),
              ") -- starting a new one.")
      list()
    }
  )
}

#' Compare the two most recent snapshots
#'
#' @param history A list of snapshots from [read_run_history()].
#' @param slower_by Numeric. Relative change in runtime counted as meaningful.
#'   Defaults to 0.25, i.e. a quarter slower or faster; anything smaller is
#'   noise on a re-run rather than a regression.
#'
#' @return `NULL` when there is nothing to compare, otherwise a list with
#'   `from`, `to` (the two timestamps) and character vectors `added`,
#'   `removed`, `rebuilt`, `status_changed`, `slower`, `faster`, `grew`,
#'   `shrank` -- each describing one target per element.
#' @export
diff_run_history <- function(history, slower_by = 0.25) {
  if (length(history) < 2) return(NULL)
  prev <- history[[length(history) - 1L]]
  curr <- history[[length(history)]]

  by_name <- function(snap) {
    out <- list()
    for (t in snap$targets) out[[t$name]] <- t
    out
  }
  a <- by_name(prev)
  b <- by_name(curr)

  added   <- setdiff(names(b), names(a))
  removed <- setdiff(names(a), names(b))
  shared  <- intersect(names(b), names(a))

  d <- list(
    from = prev$recorded, to = curr$recorded,
    added = added, removed = removed,
    rebuilt = character(), status_changed = character(),
    slower = character(), faster = character(),
    grew = character(), shrank = character()
  )

  for (n in shared) {
    old <- a[[n]]; new <- b[[n]]
    if (!identical(old$last_built, new$last_built)) d$rebuilt <- c(d$rebuilt, n)
    if (!identical(old$status, new$status)) {
      d$status_changed <- c(d$status_changed,
                            paste0(n, ": ", old$status, " -> ", new$status))
    }
    d$slower <- c(d$slower, .rel_change(n, old$seconds, new$seconds,
                                        slower_by, .fmt_seconds, TRUE))
    d$faster <- c(d$faster, .rel_change(n, old$seconds, new$seconds,
                                        slower_by, .fmt_seconds, FALSE))
    d$grew   <- c(d$grew,   .rel_change(n, old$bytes, new$bytes,
                                        slower_by, .fmt_bytes, TRUE))
    d$shrank <- c(d$shrank, .rel_change(n, old$bytes, new$bytes,
                                        slower_by, .fmt_bytes, FALSE))
  }
  d
}

# ---- private ----------------------------------------------------------------

#' One target's line in a snapshot
#' @param targets_data Output of [load_targets_data()].
#' @return A list of per-target lists.
#' @keywords internal
.snapshot_targets <- function(targets_data) {
  lapply(targets_data$target_names, function(n) {
    f <- .target_facts(n, targets_data)
    list(name = n, status = f$status, last_built = f$last_built,
         seconds = if (is.na(f$seconds)) NULL else f$seconds,
         bytes   = if (is.na(f$bytes))   NULL else f$bytes)
  })
}

#' A comparable form of a snapshot's targets
#'
#' Flattens each target to one string and sorts, so two snapshots compare
#' equal when they describe the same state regardless of how the numbers
#' survived a JSON round-trip.
#'
#' @param targets The `targets` element of a snapshot.
#' @return A sorted character vector.
#' @keywords internal
.snapshot_key <- function(targets) {
  if (!length(targets)) return(character())
  one <- function(t) {
    num <- function(v) if (is.null(v) || is.na(v)) "" else format(as.numeric(v))
    paste(t$name %||% "", t$status %||% "", t$last_built %||% "",
          num(t$seconds), num(t$bytes), sep = "|")
  }
  sort(vapply(targets, one, character(1)))
}

#' Describe a numeric change when it clears the threshold
#'
#' @param name Character. Target name.
#' @param old,new The previous and current values; either may be `NULL`.
#' @param threshold Numeric. Minimum relative change to report.
#' @param fmt A formatter, [.fmt_seconds()] or [.fmt_bytes()].
#' @param want_increase Logical. Report growth rather than reduction.
#' @return A one-element character vector, or `character()`.
#' @keywords internal
.rel_change <- function(name, old, new, threshold, fmt, want_increase) {
  if (is.null(old) || is.null(new)) return(character())
  old <- as.numeric(old); new <- as.numeric(new)
  if (is.na(old) || is.na(new) || old <= 0) return(character())
  rel <- (new - old) / old
  if (want_increase && rel < threshold)  return(character())
  if (!want_increase && rel > -threshold) return(character())
  paste0(name, ": ", fmt(old), " -> ", fmt(new),
         " (", if (rel > 0) "+" else "", round(rel * 100), "%)")
}
