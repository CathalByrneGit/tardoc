# R/setup.R

#' Build a site config list
#'
#' All generated content goes into `site_dir` (default `"tardoc"`) inside the
#' project root. No renderer is required — output is plain markdown files plus
#' a self-contained HTML viewer.
#'
#' @param project_path Path to the targets project root. Default `"."`.
#' @param site_dir     Name of the output subfolder. Default `"tardoc"`.
#' @param repo_url     Base URL of the hosted repo, e.g.
#'   `"https://github.com/user/repo/blob/main/"`. Enables source links on
#'   function and target pages. Default `NULL`.
#'
#' @return A named list used as `cfg` throughout the package.
#' @export
build_site_config <- function(project_path = ".", site_dir = "tardoc",
                               repo_url = NULL) {
  project_path <- sub("/+$", "", normalizePath(project_path, mustWork = FALSE))
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
    r_scripts_dir   = file.path(project_path, "R"),
    repo_url        = if (!is.null(repo_url)) sub("/?$", "/", repo_url) else NULL
  )
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
