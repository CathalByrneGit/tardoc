# R/source_extract.R
#
# Reading functions out of R files, verbatim.
#
# Function pages used to show `deparse(fun_obj)`, which is not the source --
# it is R's reconstruction of the parsed object. R discards comments at parse
# time, so every internal comment vanished, and deparse re-indents, re-quotes
# and re-wraps whatever survives. On a function whose body is three lines of
# code and four lines of explanation, the page showed the three lines.
#
# Getting them back needs no cleverness: parse(keep.source = TRUE) attaches a
# srcref to every expression, giving its exact line span in the file, and the
# original lines are right there to slice. That also removes the need to
# source() the file at all -- the old code executed a user's top-level script
# just to get a function object to deparse, and silently degraded to
# "# source unavailable" whenever that failed for want of a package.
#
# Three callers used to discover functions three different ways: a regex here,
# a parse in the search index, another parse for grouping. They now share this.

#' Every function defined at the top level of an R file
#'
#' Parsed, not sourced and not deparsed: the `text` is the file's own bytes
#' between the assignment's first and last line, so comments, blank lines and
#' the author's formatting all survive.
#'
#' @param path Path to an R file.
#'
#' @return A named list, one entry per function, each with `name`, `start`,
#'   `end` and `text`. Empty when the file defines no functions or cannot be
#'   parsed.
#' @keywords internal
.file_functions <- function(path) {
  exprs <- tryCatch(parse(path, keep.source = TRUE), error = function(e) NULL)
  if (is.null(exprs) || !length(exprs)) return(list())

  refs <- attr(exprs, "srcref")
  if (is.null(refs)) return(list())
  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) NULL)
  if (is.null(lines)) return(list())

  out <- list()
  for (i in seq_along(exprs)) {
    nm <- .assigned_function_name(exprs[[i]])
    if (is.null(nm)) next
    sr    <- refs[[i]]
    start <- sr[1L]
    end   <- sr[3L]
    if (is.na(start) || is.na(end) || start < 1 || end > length(lines)) next
    out[[nm]] <- list(
      name  = nm,
      start = as.integer(start),
      end   = as.integer(end),
      text  = paste(lines[start:end], collapse = "\n")
    )
  }
  out
}

#' Names of functions defined at the top level of an R file
#'
#' @param path Path to an R file.
#' @return A character vector of function names, possibly empty.
#' @keywords internal
.file_defines <- function(path) {
  # names(list()) is NULL, and callers are documented a character vector.
  nms <- names(.file_functions(path))
  if (is.null(nms)) character() else nms
}

#' The name a top-level expression assigns a function to
#'
#' Recognises `<-`, `=` and `<<-`, and both `function(x)` and the `\(x)`
#' shorthand. Anything else -- a value, a call, a function assigned into a
#' list element -- is not a top-level function definition.
#'
#' @param e A parsed expression.
#' @return The name as a string, or `NULL`.
#' @keywords internal
.assigned_function_name <- function(e) {
  if (!is.call(e) || length(e) < 3) return(NULL)
  op <- as.character(e[[1]])[1]
  if (!op %in% c("<-", "=", "<<-")) return(NULL)
  if (!is.name(e[[2]])) return(NULL)

  value <- e[[3]]
  if (!is.call(value)) return(NULL)
  if (!as.character(value[[1]])[1] %in% c("function", "\\")) return(NULL)

  as.character(e[[2]])
}
