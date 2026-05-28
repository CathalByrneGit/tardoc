# R/generate_llms_txt.R

#' Generate an llms.txt file for LLM consumption
#'
#' Writes a plain markdown file at the package root that summarises the entire
#' targets project in a format any LLM can read directly — no HTML parsing or
#' indexing required. Follows the llmstxt.org convention.
#'
#' @param targets_data  Output of [load_targets_data()].
#' @param cfg           A site config list.
#' @param project_title Character. Title shown at the top of the file.
#' @param project_desc  Character. One-paragraph description of the project.
#'
#' @return Path to `llms.txt` invisibly.
#' @export
generate_llms_txt <- function(targets_data,
                              cfg,
                              project_title = "Targets project",
                              project_desc  = "") {

  target_section   <- .llms_targets_section(targets_data)
  function_section <- .llms_functions_section(cfg)

  content <- paste0(
    "# ", project_title, "\n\n",
    if (nchar(trimws(project_desc)) > 0) paste0("> ", project_desc, "\n\n") else "",
    "This file is intended for LLM consumption. It summarises the targets\n",
    "pipeline and R functions in plain text.\n\n",
    "---\n\n",
    target_section,
    "---\n\n",
    function_section
  )

  out_path <- file.path(cfg$project_path, "llms.txt")
  writeLines(content, out_path)
  message("llms.txt written: ", out_path)
  invisible(out_path)
}

# ---- private ----------------------------------------------------------------

.llms_targets_section <- function(targets_data) {
  lines <- "## Targets\n\n"

  for (target_name in targets_data$target_names) {
    manifest_row <- dplyr::filter(targets_data$manifest, .data$name == target_name)
    command_str  <- dplyr::pull(manifest_row, "command")
    description  <- .pull_description(manifest_row)

    dep <- get_target_network_dependencies(
      target_name,
      network_data   = targets_data$network,
      max_depth_up   = 1,
      max_depth_down = 1
    )

    upstream   <- if (length(dep$upstream)   > 0) paste(dep$upstream,   collapse = ", ") else "none"
    downstream <- if (length(dep$downstream) > 0) paste(dep$downstream, collapse = ", ") else "none"

    lines <- paste0(lines,
                    "### ", target_name, "\n\n",
                    if (!is.na(description)) paste0("> ", description, "\n\n") else "",
                    "- **Upstream:** ",   upstream,   "\n",
                    "- **Downstream:** ", downstream, "\n\n",
                    "**Command:**\n\n",
                    "```r\n", command_str, "\n```\n\n"
    )
  }

  lines
}

.llms_functions_section <- function(cfg) {
  r_files <- list.files(cfg$r_scripts_dir, pattern = "\\.R$", full.names = TRUE)
  lines   <- "## Functions\n\n"

  for (file in r_files) {
    func_env <- new.env(parent = globalenv())  # globalenv so base functions like <- are available
    source(file, local = func_env)

    for (func_name in ls(func_env)) {
      # suppressWarnings: NULL return for undocumented functions is expected
      docs <- suppressWarnings(get_fn_docs(func_name, file))

      short_desc <- if (!is.null(docs)) {
        .extract_description(docs)
      } else {
        "_No documentation._"
      }

      lines <- paste0(lines,
                      "### `", func_name, "`\n\n",
                      "Defined in: `", basename(file), "`\n\n",
                      short_desc, "\n\n"
      )
    }
  }

  lines
}

.extract_description <- function(docs_md) {
  lines     <- strsplit(docs_md, "\n")[[1]]
  in_desc   <- FALSE
  desc_lines <- character()

  for (line in lines) {
    if (grepl("^##\\s+Description", line, ignore.case = TRUE)) {
      in_desc <- TRUE
      next
    }
    if (in_desc) {
      if (grepl("^##", line)) break
      desc_lines <- c(desc_lines, line)
    }
  }

  result <- trimws(paste(desc_lines, collapse = "\n"))
  if (nchar(result) == 0) "_No description._" else result
}
