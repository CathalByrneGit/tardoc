# R/generate_target_pages.R

#' Generate markdown pages for every target
#'
#' Writes one `.md` file per target into `cfg$targets_dir`. Each file contains
#' a mermaid local dependency diagram, command, status, and function links.
#' Only the region between `<!-- tardoc:generated -->` markers is overwritten
#' on re-runs — any content outside those markers is preserved.
#'
#' @param targets_data Output of [load_targets_data()].
#' @param cfg          A site config list.
#'
#' @return A character vector of target names, invisibly.
#' @export
generate_all_target_pages <- function(targets_data, cfg) {
  for (target_name in targets_data$target_names) {
    message("Target: ", target_name)

    target_meta  <- dplyr::filter(targets_data$meta, .data$name == target_name)
    manifest_row <- dplyr::filter(targets_data$manifest, .data$name == target_name)
    command_str  <- dplyr::pull(manifest_row, "command")
    description  <- .pull_description(manifest_row)

    dependency <- get_target_network_dependencies(
      target_name,
      network_data   = targets_data$network,
      max_depth_up   = 2,
      max_depth_down = 2
    )

    functions <- dplyr::filter(
      targets_data$meta,
      .data$type == "function",
      .data$name %in% dependency$upstream
    )

    repo_link       <- .target_repo_link(target_name, cfg)
    generated_block <- .build_target_generated_block(
      target_name, target_meta, command_str, functions, dependency, repo_link
    )

    out_path <- file.path(cfg$targets_dir, paste0(target_name, ".md"))
    .write_generated_md(out_path, paste0("# Target: ", target_name), description, generated_block)
  }

  message(length(targets_data$target_names), " target pages written.")
  invisible(targets_data$target_names)
}

# ---- private ----------------------------------------------------------------

.pull_description <- function(manifest_row) {
  if (!"description" %in% names(manifest_row)) return(NA_character_)
  val <- dplyr::pull(manifest_row, "description")
  if (length(val) == 0 || is.na(val) || nchar(trimws(val)) == 0) NA_character_ else val
}

.build_target_generated_block <- function(target_name, target_meta,
                                           command_str, functions, dependency,
                                           repo_link = "") {
  status <- if (is.na(target_meta$error)) "Up-to-date" else target_meta$error

  fn_links <- if (nrow(functions) == 0) {
    "_No distinct functions identified._"
  } else {
    paste0("[`", functions$name, "`](../functions/", functions$name, ".md)",
           collapse = ", ")
  }

  mermaid <- .local_mermaid(target_name, dependency)

  paste0(
    "## Details\n\n",
    "| Field | Value |\n",
    "|---|---|\n",
    "| **Status** | ", status, " |\n",
    "| **Last built** | ", as.character(target_meta$time), " |\n\n",
    "## Command\n\n",
    "```r\n", command_str, "\n```\n\n",
    "## Functions called\n\n",
    fn_links, "\n\n",
    "## Local dependency graph\n\n",
    mermaid, "\n",
    repo_link
  )
}

#' Generate a mermaid graph string for local dependencies (2 hops)
#' @keywords internal
.local_mermaid <- function(target_name, dependency) {
  edges <- dependency$edges

    init_dir <- r"(%%{init:{'theme':'dark','themeVariables':{'lineColor':'#a6adc8','edgeLabelBackground':'#1e1e2e'}}}%%)"
  if (nrow(edges) == 0) {
    return(paste0("```mermaid\n", init_dir, "\ngraph LR\n    ", target_name, "\n```"))
  }

  # Style the focal target differently
  node_styles <- paste0(
    "    style ", target_name,
    " fill:#6b48cc,color:#fff,stroke:#4a32a0\n"
  )

  edge_lines <- paste0("    ", edges$from, " --> ", edges$to, collapse = "\n")
  paste0("```mermaid\n", init_dir, "\ngraph LR\n", edge_lines, "\n", node_styles, "```")
}

#' Write or update a target markdown file
#'
#' If the file already exists, only the region between the
#' `<!-- tardoc:generated -->` markers is replaced. Content outside those
#' markers (including any user notes) is preserved.
#'
#' @keywords internal
.write_generated_md <- function(path, title_line, description,
                                 generated_block) {
  header <- paste0(
    title_line, "\n\n",
    if (!is.na(description)) paste0("> ", description, "\n\n") else ""
  )

  generated_section <- paste0(
    "<!-- tardoc:generated -->\n",
    generated_block,
    "<!-- tardoc:end -->\n"
  )

  if (!file.exists(path)) {
    # New file — write header + generated block with empty notes section
    writeLines(paste0(
      header,
      generated_section
    ), path)
  } else {
    # Existing file — replace only the generated block, preserve everything else
    existing <- paste(readLines(path, warn = FALSE), collapse = "\n")
    new_content <- .replace_generated_block(existing, header, generated_section)
    writeLines(new_content, path)
  }
}

#' Replace generated block in existing file content
#' @keywords internal
.replace_generated_block <- function(existing, header, generated_section) {
  start_tag <- "<!-- tardoc:generated -->"
  end_tag   <- "<!-- tardoc:end -->"

  has_start <- grepl(start_tag, existing, fixed = TRUE)
  has_end   <- grepl(end_tag,   existing, fixed = TRUE)

  if (has_start && has_end) {
    # Replace between the markers
    before <- sub(paste0("(?s)", start_tag, ".*?", end_tag),
                  paste0(start_tag, "\n__BLOCK__\n", end_tag),
                  existing, perl = TRUE)
    gsub("__BLOCK__", trimws(sub("<!-- tardoc:generated -->\n", "",
                                  sub("\n<!-- tardoc:end -->", "",
                                      generated_section, fixed = TRUE),
                                  fixed = TRUE)),
         before, fixed = TRUE)
  } else {
    # No markers found — rewrite with header + generated block
    paste0(header, generated_section)
  }
}

# ---- repo / line-number helpers ---------------------------------------------

#' Find the line number of a target definition in _targets.R
#'
#' Searches for `tar_target(NAME` or `tar_target(\n  NAME` patterns.
#'
#' @param target_name Character.
#' @param targets_file Path to `_targets.R`.
#' @return Integer line number, or `NULL` if not found.
#' @keywords internal
.find_target_line <- function(target_name, targets_file) {
  if (!file.exists(targets_file)) return(NULL)
  lines   <- readLines(targets_file, warn = FALSE)
  pattern <- paste0("tar_target\\s*\\(\\s*", target_name, "\\b")
  hits    <- grep(pattern, lines, perl = TRUE)
  if (length(hits) == 0) return(NULL)
  hits[1L]
}

#' Build a repo link to the target's definition in _targets.R
#' @keywords internal
.target_repo_link <- function(target_name, cfg) {
  if (is.null(cfg$repo_url)) return("")
  line <- .find_target_line(target_name,
                             file.path(cfg$project_path, "_targets.R"))
  href <- paste0(cfg$repo_url, "_targets.R",
                 if (!is.null(line)) paste0("#L", line) else "")
  paste0("\n[View definition in `_targets.R`](", href, ")\n")
}
