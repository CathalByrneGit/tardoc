# R/target_outputs.R
#
# Publishing what a target produced.
#
# A report target -- tar_render(), tar_quarto(), or any hand-written target that
# writes an HTML or PDF -- is `format = "file"`, and its value is the list of
# files it made: for tar_render, the rendered report, its source .Rmd and the
# `<name>_files/` folder beside it. `tar_meta(fields = "path")` returns that
# list without loading anything. So a report is not a special case of R
# Markdown; it is a file target whose paths include something a browser opens,
# and the same code covers all of them.
#
# Opt-in, because a report can hold data its authors never meant to put on a
# public Pages site, and the Pages workflow publishes the whole docs folder.

.report_exts <- function() c("html", "htm", "pdf")

#' Which targets produced something a browser can open
#'
#' A candidate is a target with `format = "file"` that has built without error
#' and whose recorded paths include an `.html`, `.htm` or `.pdf` that exists
#' inside the project. Paths pointing outside the project are ignored: a file
#' target may name any path, and copying `/etc/...` into a docs folder that gets
#' published is not something a documentation tool should do on a target's say-so.
#'
#' @param targets_data Output of [load_targets_data()].
#' @param cfg A site config list.
#' @return A named list, one element per candidate, each with `file` (the
#'   output, relative to the project), `dirs` (directories among the target's
#'   paths -- the `_files` folder -- relative to the project) and `status`.
#' @keywords internal
.report_candidates <- function(targets_data, cfg) {
  meta <- targets_data$meta
  if (!all(c("path", "format") %in% names(meta))) return(list())

  root <- normalizePath(cfg$project_path, winslash = "/", mustWork = FALSE)
  inside <- function(p) {
    full <- normalizePath(file.path(root, p), winslash = "/", mustWork = FALSE)
    startsWith(full, paste0(root, "/")) && file.exists(full)
  }

  out <- list()
  for (i in seq_len(nrow(meta))) {
    nm <- meta$name[i]
    if (!meta$format[i] %in% c("file", "file_fast")) next
    status <- .target_status(nm, meta, targets_data$outdated, isTRUE(targets_data$has_store))
    if (!status %in% c("uptodate", "outdated")) next

    paths <- as.character(unlist(meta$path[i]))
    paths <- paths[!is.na(paths) & nzchar(paths)]
    paths <- paths[vapply(paths, inside, logical(1))]
    ext   <- tolower(tools::file_ext(paths))
    files <- paths[ext %in% .report_exts() & !dir.exists(file.path(root, paths))]
    if (!length(files)) next

    # Prefer HTML over PDF when a render made both: it opens in a tab with its
    # figures, and a PDF of the same report is a download.
    files <- files[order(match(tolower(tools::file_ext(files)), .report_exts()))]
    out[[nm]] <- list(
      file   = files[1],
      dirs   = paths[dir.exists(file.path(root, paths))],
      status = status
    )
  }
  out
}

#' Resolve the `reports` argument to target names
#'
#' @param reports `FALSE`, `TRUE`, or a character vector of target names.
#' @param candidates Output of [.report_candidates()].
#' @param target_names All target names, to catch a name that does not exist.
#' @return A character vector of target names to publish.
#' @keywords internal
.reports_selected <- function(reports, candidates, target_names) {
  if (isFALSE(reports) || is.null(reports)) return(character())
  if (isTRUE(reports)) return(names(candidates))
  if (!is.character(reports)) {
    stop("`reports` must be TRUE, FALSE or a character vector of target names.",
         call. = FALSE)
  }
  unknown <- setdiff(reports, target_names)
  if (length(unknown)) {
    warning("`reports` names no such target: ", paste(unknown, collapse = ", "),
            call. = FALSE)
  }
  skipped <- setdiff(intersect(reports, target_names), names(candidates))
  if (length(skipped)) {
    message("Not published (no built, error-free HTML/PDF output): ",
            paste(skipped, collapse = ", "))
  }
  intersect(reports, names(candidates))
}

#' Copy chosen targets' outputs into the docs folder
#'
#' Each goes to `reports/<target>/` with its supporting directories beside it,
#' so a report that is not self-contained still finds its figures. The
#' directory is cleared first, and `reports/` as a whole is cleared on every
#' run -- but only once tardoc has marked it as its own, so turning `reports`
#' off removes what an earlier run published instead of leaving it online, and
#' a folder that happens to be called `reports` is never touched.
#'
#' @param targets_data Output of [load_targets_data()].
#' @param cfg A site config list.
#' @param reports `FALSE`, `TRUE`, or target names. See [document_targets()].
#' @param warn_mb Numeric. Total size above which to warn.
#' @return `targets_data` with `reports`: a named list, one element per
#'   published target, each with `href` (relative to the docs folder), `type`,
#'   `bytes` and `stale`.
#' @keywords internal
.publish_reports <- function(targets_data, cfg, reports = FALSE, warn_mb = 25) {
  dest   <- file.path(cfg$site_path, "reports")
  marker <- file.path(dest, ".tardoc-reports")
  if (file.exists(marker)) unlink(dest, recursive = TRUE)

  cand   <- .report_candidates(targets_data, cfg)
  chosen <- .reports_selected(reports, cand, targets_data$target_names)
  targets_data$reports <- list()
  if (!length(chosen)) return(targets_data)

  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  writeLines("Written by tardoc. Cleared on every document_targets() run.", marker)

  root <- normalizePath(cfg$project_path, winslash = "/", mustWork = FALSE)
  for (nm in chosen) {
    cd  <- cand[[nm]]
    out <- file.path(dest, nm)
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    file.copy(file.path(root, cd$file), file.path(out, basename(cd$file)), overwrite = TRUE)
    for (d in cd$dirs) {
      file.copy(file.path(root, d), out, recursive = TRUE, overwrite = TRUE)
    }
    files <- list.files(out, recursive = TRUE, full.names = TRUE)
    targets_data$reports[[nm]] <- list(
      href  = paste0("reports/", nm, "/", basename(cd$file)),
      type  = tolower(tools::file_ext(cd$file)),
      bytes = sum(file.size(files)),
      stale = identical(cd$status, "outdated")
    )
  }

  total <- sum(vapply(targets_data$reports, `[[`, numeric(1), "bytes"))
  message("Published ", length(chosen), " report",
          if (length(chosen) != 1) "s", " (", .fmt_bytes(total), "): ",
          paste(chosen, collapse = ", "))
  if (total > warn_mb * 1e6) {
    warning("Published reports total ", .fmt_bytes(total), ". They are copied ",
            "into the docs folder, so they are committed and deployed with it; ",
            "name the targets you want in `reports =` to publish fewer.",
            call. = FALSE)
  }
  targets_data
}

#' The "Output" section of a target page
#'
#' Markdown, so the link works on GitHub as well as in the viewer, which
#' restyles it as a button.
#'
#' @param name Target name.
#' @param report An element of `targets_data$reports`, or `NULL`.
#' @return A string, `""` when the target has no published output.
#' @keywords internal
.output_section <- function(name, report) {
  if (is.null(report)) return("")
  label <- switch(report$type, pdf = "Open PDF", "Open report")
  paste0(
    "## Output\n\n",
    "[", label, "](../", report$href, ")",
    " (", .fmt_bytes(report$bytes), ")\n\n",
    if (isTRUE(report$stale)) {
      "_Out of date: this target's inputs changed after it was built._\n\n"
    } else ""
  )
}
