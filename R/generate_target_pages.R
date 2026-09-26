# R/generate_target_pages.R

#' Generate markdown pages for every target
#'
#' Writes one `.md` file per target into `cfg$targets_dir`. Each file contains
#' a mermaid local dependency diagram, command, status, and function links.
#' Only the region between `<!-- tardoc:generated -->` markers is overwritten
#' on re-runs -- any content outside those markers is preserved.
#'
#' @param targets_data Output of [load_targets_data()].
#' @param cfg          A site config list.
#'
#' @return A character vector of target names, invisibly.
#' @export
generate_all_target_pages <- function(targets_data, cfg) {
  for (target_name in targets_data$target_names) {
    message("Target: ", target_name)

    manifest_row <- dplyr::filter(targets_data$manifest, .data$name == target_name)
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
      target_name, .target_facts(target_name, targets_data),
      functions, dependency, repo_link
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

.build_target_generated_block <- function(target_name, facts,
                                          functions, dependency,
                                          repo_link = "") {
  fn_links <- if (nrow(functions) == 0) {
    "_No distinct functions identified._"
  } else {
    paste0("[`", functions$name, "`](../functions/", functions$name, ".md)",
           collapse = ", ")
  }

  paste0(
    "## Details\n\n",
    .facts_table(facts),
    .facts_sections(facts),
    "## Command\n\n",
    "```r\n", facts$command, "\n```\n\n",
    "## Functions called\n\n",
    fn_links, "\n\n",
    "## Local dependency graph\n\n",
    .local_mermaid(target_name, dependency), "\n",
    repo_link
  )
}

#' Render the details table shared with the graph's inspect panel
#'
#' The panel showed a dozen fields the page did not -- branching, warnings,
#' runtime, size, storage settings. Both now read the same [.target_facts()]
#' list, so a field added there appears in both places.
#'
#' Defaults are omitted: `repository: local` and `iteration: vector` are true
#' of nearly every target and would be noise on every page.
#'
#' @param facts A list from [.target_facts()].
#' @return A markdown table.
#' @keywords internal
.facts_table <- function(facts) {
  rows <- list(c("Status", facts$status_label))
  add  <- function(label, value) {
    if (nzchar(value)) rows[[length(rows) + 1L]] <<- c(label, value)
  }

  add("Last built", facts$last_built)
  add("Last run",   facts$progress)
  if (facts$branched) {
    add("Branching", paste0("`", facts$pattern, "`",
                            if (facts$n_branches > 0)
                              paste0(" &mdash; ", facts$n_branches, " branches")
                            else ""))
  }
  if (!is.na(facts$seconds)) add("Runtime", .fmt_seconds(facts$seconds))
  if (!is.na(facts$bytes))   add("Size",    .fmt_bytes(facts$bytes))
  add("Format", if (identical(facts$format, "rds")) "" else facts$format)
  add("Repository", if (identical(facts$repository, "local")) "" else facts$repository)
  add("Iteration",  if (identical(facts$iteration, "vector")) "" else facts$iteration)

  paste0(
    "| Field | Value |\n|---|---|\n",
    paste0("| **", vapply(rows, `[`, "", 1), "** | ",
           vapply(rows, `[`, "", 2), " |", collapse = "\n"),
    "\n\n"
  )
}

#' Error and warning sections, when there are any
#' @param facts A list from [.target_facts()].
#' @return A markdown string, empty when the target built cleanly.
#' @keywords internal
.facts_sections <- function(facts) {
  out <- ""
  if (nzchar(facts$error)) {
    out <- paste0(out, "## Error\n\n```\n", facts$error, "\n```\n\n")
  }
  # Warnings live in tar_meta() and previously surfaced nowhere at all: not on
  # this page, not in the search index, not in llms.txt.
  if (nzchar(facts$warnings)) {
    out <- paste0(out, "## Warnings\n\n```\n", facts$warnings, "\n```\n\n")
  }
  out
}

#' Format a duration the way the inspect panel does
#' @param s Numeric seconds.
#' @return A display string.
#' @keywords internal
.fmt_seconds <- function(s) {
  if (is.na(s)) return("")
  if (s < 1)    return(paste0(round(s * 1000), " ms"))
  if (s < 60)   return(paste0(signif(s, 3), " s"))
  paste0(floor(s / 60), "m ", round(s %% 60), "s")
}

#' Format a byte count the way the inspect panel does
#' @param b Numeric bytes.
#' @return A display string.
#' @keywords internal
.fmt_bytes <- function(b) {
  if (is.na(b)) return("")
  units <- c("B", "kB", "MB", "GB", "TB")
  i <- if (b <= 0) 1L else min(length(units), 1L + floor(log(b, 1000)))
  paste(signif(b / 1000^(i - 1), 3), units[i])
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
    # New file -- write header + generated block with empty notes section
    writeLines(paste0(
      header,
      generated_section
    ), path)
  } else {
    # Existing file -- replace only the generated block, preserve everything else
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
    # No markers found -- rewrite with header + generated block
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
