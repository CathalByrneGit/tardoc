# R/setup.R

#' Build a site config list
#'
#' All generated content goes into `site_dir` (default `"tardoc"`) inside the
#' project root. No renderer is required -- output is plain markdown files plus
#' a self-contained HTML viewer.
#'
#' @param project_path Path to the targets project root. Default `"."`.
#' @param site_dir     Name of the output subfolder. Default `"tardoc"`.
#' @param repo_url     Base URL of the hosted repo, e.g.
#'   `"https://github.com/user/repo/blob/main/"`. Enables source links on
#'   function and target pages. Default `NULL`.
#' @param code_dirs    Where the project's function code lives: directories
#'   (searched recursively) and/or individual files, relative to
#'   `project_path` or absolute. `NULL` (the default) reads them from the
#'   `tar_source()` calls in `_targets.R`, so `tar_source("code")` is enough;
#'   with none found it falls back to `"R"`. Only `.R` and `.r` files are read.
#'
#' @return A named list used as `cfg` throughout the package. `r_scripts_dir`
#'   holds the resolved code locations -- a character vector, one or many.
#' @export
build_site_config <- function(project_path = ".", site_dir = "tardoc",
                               repo_url = NULL, code_dirs = NULL) {
  # winslash = "/" so every derived path uses one separator on all platforms:
  # these paths end up inside SQL string literals, JSON and HTML, and
  # file.path() would otherwise mix "\\" and "/" on Windows.
  project_path <- sub("/+$", "",
                      normalizePath(project_path, winslash = "/", mustWork = FALSE))
  site_path    <- file.path(project_path, site_dir)

  list(
    project_path    = project_path,
    site_path       = site_path,
    targets_dir     = file.path(site_path, "targets"),
    functions_dir   = file.path(site_path, "functions"),
    notes_dir       = file.path(site_path, "notes"),
    notes_targets   = file.path(site_path, "notes", "targets"),
    notes_functions = file.path(site_path, "notes", "functions"),
    targets_store   = file.path(project_path, "_targets"),
    r_scripts_dir   = .resolve_code_dirs(project_path, code_dirs),
    repo_url        = if (!is.null(repo_url)) sub("/?$", "/", repo_url) else NULL
  )
}

.resolve_code_dirs <- function(project_path, code_dirs = NULL) {
  dirs <- if (is.null(code_dirs)) .detect_code_dirs(project_path) else code_dirs
  dirs <- as.character(dirs)
  abs  <- ifelse(grepl("^([A-Za-z]:)?[/\\\\~]", dirs), dirs, file.path(project_path, dirs))
  unique(sub("/+$", "", normalizePath(abs, winslash = "/", mustWork = FALSE)))
}

#' Where `_targets.R` says the project's code lives
#'
#' Reads the `tar_source()` calls in `_targets.R` -- the idiom for loading a
#' project's functions -- and returns the paths they name, so a project that
#' keeps its code in `code/` or `src/helpers.R` is documented without being
#' told. Only literal paths are understood (a string, `c(...)` of strings, or
#' `file.path()` of strings); anything computed is skipped rather than guessed
#' at, and `_targets.R` is parsed, never run.
#'
#' @param project_path Project root.
#' @return Character vector of paths relative to the project; `"R"` when
#'   `_targets.R` names none that exist.
#' @keywords internal
.detect_code_dirs <- function(project_path) {
  file <- file.path(project_path, "_targets.R")
  exprs <- if (file.exists(file)) {
    tryCatch(parse(file, keep.source = FALSE), error = function(e) NULL)
  }
  found <- character()
  safe  <- list2env(list(c = c, file.path = file.path, paste0 = paste0), parent = emptyenv())

  walk <- function(e) {
    if (!is.call(e)) return()
    fn <- e[[1]]
    name <- if (is.name(fn)) as.character(fn) else if (is.call(fn) && length(fn) == 3L &&
      is.name(fn[[3]])) as.character(fn[[3]]) else ""
    if (identical(name, "tar_source")) {
      args  <- as.list(e)[-1]
      named <- names(args) %||% rep("", length(args))
      arg <- if ("files" %in% named) args[["files"]] else if (any(named == "")) args[[which(named == "")[1]]] else "R"
      val <- tryCatch(eval(arg, safe), error = function(err) NULL)
      if (is.character(val)) found <<- c(found, val)
    }
    for (a in as.list(e)) walk(a)
  }
  for (e in exprs) walk(e)

  found <- unique(found[nzchar(found)])
  found <- found[file.exists(file.path(project_path, found)) | file.exists(found)]
  if (length(found)) found else "R"
}

#' Create all required output directories
#'
#' @param cfg A site config list produced by [build_site_config()].
#' @return `cfg` invisibly.
#' @export
setup_site_dirs <- function(cfg) {
  dirs <- c(
    cfg$targets_dir,
    cfg$functions_dir,
    cfg$notes_targets,
    cfg$notes_functions
  )
  for (d in dirs) dir.create(d, showWarnings = FALSE, recursive = TRUE)
  message("Directories ready under: ", cfg$site_path)
  invisible(cfg)
}
