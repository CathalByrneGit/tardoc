# R/generate_notes.R

#' Initialise note stub files for targets and functions
#'
#' Creates empty note files under `cfg$notes_targets` and
#' `cfg$notes_functions` for any target or function that does not already
#' have one. Existing note files are **never** touched -- they are
#' entirely user-owned.
#'
#' Note files live at:
#' - `tardoc/notes/index.md` -- the project overview, shown on the viewer's
#'   home page under the title
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
  index_path <- file.path(cfg$notes_dir, "index.md")
  if (!file.exists(index_path)) writeLines(.overview_stub(), index_path)

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

#' Read the project overview note
#'
#' The home-page counterpart of [read_note()]: `notes/index.md`, which is
#' yours to write and is never overwritten. Returns the empty string when it
#' is missing or still only the stub's comments.
#'
#' @param cfg A site config list.
#'
#' @return Character string (possibly empty).
#' @export
read_overview <- function(cfg) {
  path <- file.path(cfg$notes_dir, "index.md")
  if (!file.exists(path)) return("")
  # Notes are UTF-8 text. Say so, or readLines() returns bytes of unknown
  # encoding that a non-UTF-8 native locale (Windows) will reinterpret.
  content <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"),
                   collapse = "\n")
  trimws(content)
}

# ---- private ----------------------------------------------------------------

.overview_stub <- function() {
  paste0(
    "<!-- Project overview: shown on the viewer's home page, under the title. -->\n",
    "<!-- This file is yours -- tardoc will never overwrite it. -->\n",
    "<!-- What is this pipeline for, who owns it, what should a newcomer read first? -->\n\n"
  )
}

.note_stub <- function(type, name) {
  paste0(
    "<!-- Notes for ", type, ": ", name, " -->\n",
    "<!-- This file is yours -- tardoc will never overwrite it. -->\n",
    "<!-- Add context, decisions, links, or anything useful. -->\n\n"
  )
}
