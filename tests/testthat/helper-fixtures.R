# tests/testthat/helper-fixtures.R

mock_cfg <- function(tmp = withr::local_tempdir(), site_dir = "tardoc") {
  site_path <- file.path(tmp, site_dir)
  list(
    project_path    = tmp,
    site_path       = site_path,
    targets_dir     = file.path(site_path, "targets"),
    functions_dir   = file.path(site_path, "functions"),
    notes_dir       = file.path(site_path, "notes"),
    notes_targets   = file.path(site_path, "notes", "targets"),
    notes_functions = file.path(site_path, "notes", "functions"),
    targets_store   = file.path(tmp, "_targets"),
    r_scripts_dir   = file.path(tmp, "R"),
    repo_url        = NULL
  )
}

mock_targets_data <- function(has_store = FALSE) {
  manifest <- dplyr::tibble(
    name        = c("raw_data", "clean_data", "model_fit", "report"),
    command     = c('read_csv("data/raw.csv")', "clean_raw(raw_data)",
                    "fit_model(clean_data)", "render_report(model_fit)"),
    pattern     = NA_character_,
    description = c("Raw sensor readings", "Cleaned data", NA_character_, "")
  )
  meta <- if (has_store) {
    dplyr::tibble(name = manifest$name, type = "stem",
                  time = as.character(Sys.time()), error = NA_character_,
                  bytes = c(1024, 2048, 4096, 512), format = "rds")
  } else {
    dplyr::tibble(name = manifest$name, type = "stem",
                  time = NA_character_, error = NA_character_,
                  bytes = NA_real_, format = NA_character_)
  }
  network <- list(
    vertices = dplyr::tibble(
      name   = c("raw_data","clean_data","model_fit","report",
                 "clean_raw","fit_model","render_report"),
      type   = c("stem","stem","stem","stem","function","function","function"),
      status = "uptodate", color = "grey"
    ),
    edges = dplyr::tibble(
      from = c("raw_data","clean_data","model_fit",
               "clean_raw","fit_model","render_report"),
      to   = c("clean_data","model_fit","report",
               "clean_data","model_fit","report")
    )
  )
  list(meta = meta, target_names = manifest$name, network = network,
       manifest = manifest, has_store = has_store)
}

write_mock_r_file <- function(dir, filename = "helpers.R") {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, filename)
  writeLines(c(
    "#' Add two numbers", "#'",
    "#' @param x A number.", "#' @param y A number.",
    "#' @return The sum.", "#' @export",
    "add <- function(x, y) x + y", "",
    "internal_helper <- function(x) x * 2"
  ), path)
  path
}
