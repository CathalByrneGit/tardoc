# R/generate_notes.R

#' Initialise note stub files for targets and functions
#'
#' Creates empty note files under `cfg$notes_targets` and
#' `cfg$notes_functions` for any target or function that does not already
#' have one. Existing note files are **never** touched — they are
#' entirely user-owned.
#'
#' Note files live at:
#' - `tardoc/notes/targets/TARGET_NAME.md`
#' - `tardoc/notes/functions/FUNCTION_NAME.md`
#'
#' @param target_names  Character vector of target names.
#' @param function_names Character vector of function names.
#' @param cfg           A site config list.
#'
#' @return Invisibly `NULL`.
#' @export
generate_notes <- function(target_names, function_names, cfg) {
  for (name in target_names) {
    path <- file.path(cfg$notes_targets, paste0(name, ".md"))
    if (!file.exists(path)) {
      writeLines(.note_stub("target", name), path)
    }
  }

  for (name in function_names) {
    path <- file.path(cfg$notes_functions, paste0(name, ".md"))
    if (!file.exists(path)) {
      writeLines(.note_stub("function", name), path)
    }
  }

  message("Notes stubs ready under: ", cfg$notes_dir)
  invisible(NULL)
}

#' Read a note file, returning empty string if not found
#'
#' @param name Character. Target or function name.
#' @param type One of `"targets"` or `"functions"`.
#' @param cfg  A site config list.
#'
#' @return Character string (possibly empty).
#' @export
read_note <- function(name, type = c("targets", "functions"), cfg) {
  type <- match.arg(type)
  dir  <- if (type == "targets") cfg$notes_targets else cfg$notes_functions
  path <- file.path(dir, paste0(name, ".md"))
  if (!file.exists(path)) return("")
  content <- paste(readLines(path, warn = FALSE), collapse = "\n")
  trimws(content)
}

# ---- private ----------------------------------------------------------------

.note_stub <- function(type, name) {
  paste0(
    "<!-- Notes for ", type, ": ", name, " -->\n",
    "<!-- This file is yours — tardoc will never overwrite it. -->\n",
    "<!-- Add context, decisions, links, or anything useful. -->\n\n"
  )
}
