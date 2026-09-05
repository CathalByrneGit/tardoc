# R/shinylive_url.R
#
# PROTOTYPE -- embed a live, runnable Shiny app in generated documentation
# without hosting anything.
#
# Borrowed from blockr, whose vignettes do exactly this via roxy.shinylive: the
# app's source is LZ-compressed into a shinylive.io URL fragment and shown in an
# iframe. shinylive.io supplies the webR runtime, so the page carries only the
# URL.
#
# This matters because an earlier evaluation (on the claude/shinylive-evaluation
# branch) measured the self-hosted route -- shinylive::export() -- at 66-77 MB plus a
# server with cross-origin isolation headers, and recommended against it. The
# URL route has a different cost profile entirely: nothing to host, but the page
# needs internet access at view time and depends on a third-party site.

#' Encode a Shiny app into a shinylive.io URL
#'
#' Compresses app source into a URL fragment that shinylive.io expands and runs
#' in the browser. Nothing is hosted locally: the webR runtime and all R
#' packages are fetched by shinylive.io.
#'
#' @param files A named list or character vector of file contents, names being
#'   file names. A single unnamed string is treated as `app.R`.
#' @param mode `"app"` for a running app, `"editor"` to open the code editor.
#' @param header Logical. Show the shinylive header bar.
#'
#' @return A single URL string.
#' @export
#' @examples
#' shinylive_url("library(shiny)\nshinyApp(fluidPage('hi'), function(input, output) {})")
shinylive_url <- function(files, mode = c("app", "editor"), header = TRUE) {
  mode <- match.arg(mode)
  if (!requireNamespace("lzstring", quietly = TRUE)) {
    stop("'lzstring' is required: install.packages('lzstring')")
  }

  if (is.character(files) && is.null(names(files))) {
    if (length(files) != 1L) {
      stop("Unnamed `files` must be a single string, treated as app.R")
    }
    files <- stats::setNames(list(files), "app.R")
  }
  files <- as.list(files)
  if (is.null(names(files)) || any(!nzchar(names(files)))) {
    stop("`files` must be named with file names")
  }

  payload <- lapply(names(files), function(nm) {
    list(name = nm, content = paste(files[[nm]], collapse = "\n"), type = "text")
  })

  json <- jsonlite::toJSON(payload, auto_unbox = TRUE)
  code <- lzstring::compressToEncodedURIComponent(as.character(json))

  paste0("https://shinylive.io/r/", mode, "/",
         if (!header) "?h=0" else "", "#code=", code)
}

#' Build an iframe embedding a shinylive app
#'
#' Produces the HTML that documentation pages can carry: a link plus an iframe,
#' mirroring what `roxy.shinylive` emits.
#'
#' @param files Passed to [shinylive_url()].
#' @param height CSS height for the iframe.
#' @param ... Further arguments for [shinylive_url()].
#'
#' @return A single HTML string.
#' @export
shinylive_iframe <- function(files, height = "600px", ...) {
  url <- shinylive_url(files, ...)
  paste0(
    '<p><a href="', url, '" target="_blank" rel="noopener">Open in Shinylive</a></p>\n',
    '<iframe class="shinylive-frame" src="', url, '" ',
    'style="width:100%;height:', height, ';border:1px solid #313244;border-radius:8px" ',
    'loading="lazy" allow="cross-origin-isolated"></iframe>'
  )
}
