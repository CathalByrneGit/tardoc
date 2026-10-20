# R/generate_viewer.R

#' Generate a self-contained HTML viewer
#'
#' Writes `viewer.html` into `cfg$site_path` by loading
#' `inst/templates/viewer.html` and substituting data placeholders.
#' No R string escaping -- the template is plain HTML with real JavaScript.
#'
#' @param targets_data   Output of [load_targets_data()].
#' @param function_names Character vector of function names.
#' @param cfg            A site config list.
#' @param pkg_name       Character. Site title shown in the viewer header.
#' @param group_by       Passed to [target_groups()]. When a grouping is
#'   found the overview offers a **group** toggle; the flat graph remains the
#'   default view.
#'
#' @return Path to `viewer.html` invisibly.
#' @export
generate_viewer <- function(targets_data, function_names, cfg,
                            pkg_name = "targets docs",
                            group_by = "auto") {
  tpl <- .load_template("viewer.html")

  target_pages <- lapply(targets_data$target_names, function(name) {
    path <- file.path(cfg$targets_dir, paste0(name, ".md"))
    list(
      name    = name,
      type    = "targets",
      content = if (file.exists(path))
        paste(readLines(path, warn = FALSE), collapse = "\n") else "",
      notes   = read_note(name, "targets", cfg)
    )
  })

  function_pages <- lapply(function_names, function(name) {
    path <- file.path(cfg$functions_dir, paste0(name, ".md"))
    list(
      name    = name,
      type    = "functions",
      content = if (file.exists(path))
        paste(readLines(path, warn = FALSE), collapse = "\n") else "",
      notes   = read_note(name, "functions", cfg)
    )
  })

  pages_json <- jsonlite::toJSON(c(target_pages, function_pages), auto_unbox = TRUE)
  index_json <- if (file.exists(file.path(cfg$site_path, "search_index.json")))
    paste(readLines(file.path(cfg$site_path, "search_index.json"),
                    warn = FALSE), collapse = "\n")
  else "{}"

  html <- tpl
  html <- gsub("{{PKG_NAME}}",      pkg_name,                                     html, fixed = TRUE)
  html <- gsub("{{PKG_NAME_JSON}}", jsonlite::toJSON(pkg_name, auto_unbox = TRUE), html, fixed = TRUE)
  html <- gsub("{{PAGES_JSON}}",    pages_json,                                   html, fixed = TRUE)
  html <- gsub("{{INDEX_JSON}}",    index_json,                                   html, fixed = TRUE)
  html <- gsub("{{OVERVIEW_JSON}}",
               gsub("</script>", "<\\/script>",
                    jsonlite::toJSON(read_overview(cfg), auto_unbox = TRUE),
                    fixed = TRUE),
               html, fixed = TRUE)

  # Pipeline overview graph. Positions are computed here because React Flow
  # does no layout of its own.
  grouping <- target_groups(targets_data, cfg, method = group_by)
  if (length(grouping$groups)) {
    message("Grouping: ", grouping$method, " (",
            length(unique(grouping$groups)), " groups, score ",
            round(grouping$score, 2), ")")
  }
  graph   <- build_dag_graph(targets_data, groups = grouping$groups)
  graph$grouping_method <- grouping$method
  profile <- pipeline_profile(targets_data)

  # Mark the critical path on the nodes so the graph can highlight it without
  # recomputing anything in the browser.
  on_path <- profile$critical_path
  graph$nodes <- lapply(graph$nodes, function(n) {
    n$on_critical_path <- n$id %in% on_path
    n
  })

  esc <- function(x) gsub("</script>", "<\\/script>", x, fixed = TRUE)
  html <- gsub("{{GRAPH_JSON}}",
               esc(jsonlite::toJSON(graph, auto_unbox = TRUE)), html, fixed = TRUE)
  html <- gsub("{{PROFILE_JSON}}",
               esc(jsonlite::toJSON(.as_arrays(profile, "critical_path"),
                                    auto_unbox = TRUE)),
               html, fixed = TRUE)
  html <- gsub("{{HISTORY_JSON}}",
               esc(jsonlite::toJSON(
                 .history_payload(read_run_history(cfg)), auto_unbox = TRUE,
                 null = "null", na = "null")),
               html, fixed = TRUE)

  html <- gsub("{{COVERAGE_JSON}}",
               esc(jsonlite::toJSON(
                 .doc_coverage(target_pages, function_pages), auto_unbox = TRUE)),
               html, fixed = TRUE)

  out_path <- file.path(cfg$site_path, "viewer.html")
  writeLines(html, out_path, useBytes = TRUE)
  message("Viewer written: ", out_path)
  invisible(out_path)
}

# ---- private ----------------------------------------------------------------

#' Load a template from inst/templates/
#' @keywords internal
.load_template <- function(filename) {
  path <- system.file("templates", filename, package = "tardoc")
  if (!nzchar(path)) {
    # devtools::load_all() fallback -- look relative to package root
    candidates <- c(
      file.path("inst", "templates", filename),
      file.path(find.package("tardoc", quiet = TRUE), "inst", "templates", filename)
    )
    path <- Filter(file.exists, candidates)[1]
    if (is.na(path) || !nzchar(path))
      stop("Template not found: inst/templates/", filename)
  }
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

#' Shape the run history for the viewer
#'
#' Only the diff and the timestamps are embedded -- the full snapshots can run
#' to fifty copies of every target and the page has no use for them.
#'
#' @param history A list from [read_run_history()].
#' @return A list with `runs` (timestamps, newest last) and `diff`.
#' @keywords internal
.history_payload <- function(history) {
  diff <- diff_run_history(history)
  if (!is.null(diff)) {
    diff <- .as_arrays(diff, c("added", "removed", "rebuilt", "status_changed",
                               "slower", "faster", "grew", "shrank"))
  }
  list(
    runs   = I(vapply(history, function(h) h$recorded %||% "", character(1))),
    diff   = diff,
    series = .history_series(history)
  )
}

#' Each target's own build history, for the sparklines on its page
#'
#' A snapshot is taken whenever anything in the pipeline differs, so a target
#' that was not rebuilt repeats the same figures across several of them. Only
#' real builds are kept -- one point per distinct `last_built` -- and only for
#' targets with at least two, since one point is not a trend. Arrays are
#' parallel: the nth entry of `t`, `s` and `b` describe the nth build.
#'
#' @param history A list from [read_run_history()].
#' @param max_points Integer. Most recent builds kept per target.
#' @return A named list, one element per target with two or more builds, each
#'   with `t` (build time), `s` (seconds) and `b` (bytes); `NULL` when none.
#' @keywords internal
.history_series <- function(history, max_points = 30L) {
  per <- list()
  for (snap in history) {
    for (t in snap$targets) {
      if (is.null(t$last_built) || is.na(t$last_built) || !nzchar(t$last_built)) next
      nm   <- t$name
      seen <- per[[nm]]$t
      if (!is.null(seen) && t$last_built %in% seen) next
      per[[nm]]$t <- c(seen, t$last_built)
      per[[nm]]$s <- c(per[[nm]]$s, if (is.null(t$seconds)) NA_real_ else as.numeric(t$seconds))
      per[[nm]]$b <- c(per[[nm]]$b, if (is.null(t$bytes))   NA_real_ else as.numeric(t$bytes))
    }
  }
  per <- Filter(function(x) length(x$t) >= 2L, per)
  if (!length(per)) return(NULL)
  lapply(per, function(x) {
    keep <- utils::tail(seq_along(x$t), max_points)
    list(t = I(x$t[keep]), s = I(signif(x$s[keep], 4)), b = I(x$b[keep]))
  })
}

#' Which targets and functions lack documentation
#'
#' What the reader sees is what counts. A target is described when its page
#' carries a description line under the title -- from `description =` in
#' `_targets.R` or written there by `llm = TRUE` -- and a function is
#' documented unless its page holds the no-roxygen placeholder.
#'
#' @param target_pages,function_pages The page lists built in
#'   [generate_viewer()].
#' @return A list with `targets` and `functions`, each holding `total` and the
#'   names that are `missing`.
#' @keywords internal
.doc_coverage <- function(target_pages, function_pages) {
  described <- function(content) {
    lines <- strsplit(content, "\n", fixed = TRUE)[[1]]
    # Title, blank line, then "> description" when there is one.
    length(lines) >= 3L && startsWith(lines[3L], "> ")
  }
  nm <- function(pages, keep) {
    I(as.character(unlist(lapply(pages[!keep], `[[`, "name"))))
  }
  t_ok <- vapply(target_pages,   function(p) described(p$content), logical(1))
  f_ok <- vapply(function_pages, function(p) !grepl(.NO_ROXYGEN, p$content, fixed = TRUE),
                 logical(1))
  list(
    targets   = list(total = length(target_pages),   missing = nm(target_pages, t_ok)),
    functions = list(total = length(function_pages), missing = nm(function_pages, f_ok))
  )
}

#' Keep named fields as JSON arrays
#'
#' `auto_unbox = TRUE` turns a length-1 vector into a bare value, so a diff
#' naming a single rebuilt target reached the page as a string and the code
#' iterating it failed. `I()` marks these as arrays whatever their length.
#'
#' @param x A list.
#' @param fields Character vector of names to protect.
#' @return `x`, with those elements wrapped in [I()].
#' @keywords internal
.as_arrays <- function(x, fields) {
  for (f in intersect(fields, names(x))) {
    if (!is.null(x[[f]])) x[[f]] <- I(as.character(x[[f]]))
  }
  x
}
