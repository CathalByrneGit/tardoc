# R/moxygenise.R

#' Generate Rd documentation from roxygen comments (whole directory)
#'
#' @param codepath Character. Path to directory containing R source files.
#' @param manpath  Character. Path to directory where `.Rd` files will be saved.
#' @return Invisibly `NULL`.
#' @export
moxygenise <- function(codepath, manpath) {
  .write_rd(.dir_to_rd(codepath), manpath)
}

#' Generate Rd documentation from a single R script
#'
#' @param file    Character. Path to a single `.R` source file.
#' @param manpath Character. Path to directory where `.Rd` files will be saved.
#' @return Invisibly `NULL`.
#' @export
moxygenise_file <- function(file, manpath) {
  .write_rd(.file_to_rd(normalizePath(file, mustWork = TRUE)), manpath)
}

#' Get roxygen docs for a single function as a markdown string
#'
#' Nothing is written to disk. The result can be embedded directly into a
#' vignette string, printed, or passed to any downstream function.
#'
#' @param fn_name Character. Function name (without `.Rd`).
#' @param file    Character. Path to the `.R` file that defines `fn_name`.
#' @return A markdown string, or `NULL` (with a warning) if not found.
#' @export
get_fn_docs <- function(fn_name, file) {
  rd_codes <- .file_to_rd(normalizePath(file, mustWork = TRUE))

  target <- paste0(fn_name, ".Rd")
  if (!target %in% names(rd_codes)) {
    warning(
      "'", fn_name, "' has no roxygen docs in ", basename(file), ". ",
      "Available: ", paste(names(rd_codes), collapse = ", ")
    )
    return(NULL)
  }

  # Write to a temp file so Rd2md::read_rdfile() can parse it properly
  tmp <- tempfile(fileext = ".Rd")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(rd_codes[[target]], tmp)

  rd <- Rd2md::read_rdfile(tmp)
  Rd2md::as_markdown(rd)
}

# ---- private ----------------------------------------------------------------

.list_r_files <- function(path) {
  path <- normalizePath(path, mustWork = TRUE)
  file.path(path, list.files(path, pattern = "\\.R$", recursive = TRUE))
}

.file_to_rd <- function(file) {
  env    <- roxygen2::env_file(file)
  blocks <- roxygen2::parse_file(file, env)
  topics <- roxygen2::roclet_process(roxygen2::rd_roclet(), blocks, env, dirname(file))
  purrr::flatten(lapply(topics, format))
}

.dir_to_rd <- function(codepath) {
  purrr::flatten(lapply(.list_r_files(codepath), .file_to_rd))
}

.write_rd <- function(rd_codes, manpath) {
  mapply(function(text, topic) {
    message("  Rd: ", topic)
    writeLines(text, file.path(manpath, topic))
  }, rd_codes, names(rd_codes))
  invisible(NULL)
}
