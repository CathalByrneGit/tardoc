# R/utf8.R
#
# Text in, text out, always UTF-8.
#
# Everything tardoc reads and writes is UTF-8: source files, notes, descriptions,
# the HTML it builds. R, though, assumes the *native* encoding unless told, and on
# a machine whose native encoding is not UTF-8 (Windows before R 4.2, a bare
# container, a CI image with LANG unset) a plain readLines() returns bytes it
# cannot interpret and a plain writeLines() "translates" what it holds. The
# result was not a quiet glitch: an em dash in a project title or a note became
# "<e2><80><94>", or the build stopped on "unable to translate ... to UTF-8".
# One definition of how files are read and written, used everywhere, keeps that
# out of the code that has no business knowing.

#' Read a UTF-8 text file as lines
#'
#' Marks the strings as UTF-8 rather than re-encoding them, which is what they
#' already are, and drops a byte-order mark if an editor added one.
#'
#' @param path File to read.
#' @return A character vector, one element per line.
#' @noRd
.read_lines_utf8 <- function(path) {
  x <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (length(x)) x[1] <- sub("^\ufeff", "", x[1])
  x
}

#' Read a UTF-8 text file as one string
#'
#' @param path File to read.
#' @return A single string, lines joined by newlines.
#' @noRd
.read_text_utf8 <- function(path) {
  paste(.read_lines_utf8(path), collapse = "\n")
}

#' Write text to a file as UTF-8
#'
#' `useBytes = TRUE` writes the string's bytes as they are instead of translating
#' them to the native encoding first, which is where non-ASCII text was lost.
#'
#' @param text A character vector (or a `jsonlite` JSON string).
#' @param path File to write.
#' @return Invisibly `NULL`.
#' @noRd
.write_lines_utf8 <- function(text, path) {
  writeLines(enc2utf8(as.character(text)), path, useBytes = TRUE)
}

# Text arriving from targets (descriptions, commands, paths) carries no
# encoding mark. In a non-UTF-8 locale R then treats its bytes as native and
# escapes them (`<e2><80><94>`) the moment anything converts them. Mark
# anything that is valid UTF-8 as such; leave the rest alone.
.mark_utf8 <- function(x) {
  if (is.data.frame(x)) {
    x[] <- lapply(x, .mark_utf8)
    return(x)
  }
  if (is.list(x) && !is.object(x)) return(lapply(x, .mark_utf8))
  if (is.character(x)) {
    todo <- Encoding(x) == "unknown" & !is.na(x) & validUTF8(x)
    if (any(todo)) Encoding(x)[todo] <- "UTF-8"
  }
  x
}
