# tests/testthat/helper-fixtures.R

# Delegate to the real builder rather than hand-rolling the same list: a
# hand-rolled fixture kept unnormalised Windows paths and disagreed with
# production over path separators.
mock_cfg <- function(tmp = withr::local_tempdir(), site_dir = "tardoc") {
  build_site_config(tmp, site_dir)
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

# Shape produced by .build_analytics_data() and consumed by the WASM viewer.
mock_analytics_data <- function(td = mock_targets_data()) {
  list(
    pkg_name  = "Test pipeline",
    targets   = lapply(td$target_names, function(tn) list(
      name = tn, description = "", command = "f()", status = "uptodate",
      last_built = "", n_upstream = 0L, n_downstream = 0L, notes = "",
      upstream = list(), downstream = list()
    )),
    functions = list(),
    edges     = lapply(seq_len(nrow(td$network$edges)), function(i) list(
      from = td$network$edges$from[i], to = td$network$edges$to[i]
    ))
  )
}
