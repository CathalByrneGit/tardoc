# R/generate_function_pages.R

#' Generate markdown pages for every R function
#'
#' Writes one `.md` file per function into `cfg$functions_dir`. Roxygen docs
#' and source code are inside the `<!-- tardoc:generated -->` block and
#' updated on every run.
#'
#' @param cfg A site config list.
#' @return A character vector of function names, invisibly.
#' @export
generate_all_function_pages <- function(cfg) {
  r_files    <- list.files(cfg$r_scripts_dir, pattern = "\\.R$", full.names = TRUE)
  func_names <- character()

  for (file in r_files) {
    # One parse gives both the names and their verbatim source. This used to
    # be a regex for discovery plus a source() and deparse() for the body:
    # the regex only matched `name <- function` at column one, and deparse
    # showed R's reconstruction of the parsed object, which has had every
    # comment stripped out of it. Parsing also means no user code is run.
    defs <- .file_functions(file)

    for (func_name in names(defs)) {
      message("  Function: ", func_name)

      fun_code <- defs[[func_name]]$text

      docs_md <- suppressWarnings(get_fn_docs(func_name, file))
      if (is.null(docs_md)) docs_md <- "_No roxygen documentation found._"

      repo_href <- .function_repo_link(func_name, file, cfg)

      source_section <- if (!is.null(repo_href)) {
        paste0(
          "## Source\n\n",
          "Defined in [`", basename(file), "`](", repo_href, ")\n"
        )
      } else {
        paste0(
          "## Source\n\n",
          "Defined in `", basename(file), "`\n\n",
          "```r\n", fun_code, "\n```\n"
        )
      }

      generated_block <- paste0(
        "## Documentation\n\n",
        docs_md, "\n\n",
        source_section
      )

      out_path <- file.path(cfg$functions_dir, paste0(func_name, ".md"))
      .write_generated_md(
        path             = out_path,
        title_line       = paste0("# Function: `", func_name, "`"),
        description      = NA_character_,
        generated_block  = generated_block
      )

      func_names <- c(func_names, func_name)
    }
  }

  message(length(func_names), " function pages written.")
  invisible(func_names)
}

# ---- repo / line-number helpers ---------------------------------------------

#' Find the line where a function is defined in an R file
#' @keywords internal
.find_function_line <- function(func_name, r_file) {
  if (!file.exists(r_file)) return(NULL)
  lines   <- readLines(r_file, warn = FALSE)
  pattern <- paste0("^", func_name, "\\s*(<-|=)\\s*function")
  hits    <- grep(pattern, lines, perl = TRUE)
  if (length(hits) == 0) return(NULL)
  hits[1L]
}

#' Build a repo source link for a function
#' @keywords internal
.function_repo_link <- function(func_name, r_file, cfg) {
  if (is.null(cfg$repo_url)) return(NULL)
  rel  <- paste0("R/", basename(r_file))
  line <- .find_function_line(func_name, r_file)
  href <- paste0(cfg$repo_url, rel,
                 if (!is.null(line)) paste0("#L", line) else "")
  href
}
