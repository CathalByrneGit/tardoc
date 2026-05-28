# R/generate_analytics_viewer.R
#
# Tier 3/4 analytics viewer. Loads inst/templates/analytics.html and
# substitutes the project title. Quack/LLM tokens are injected later by
# inject_quack_session() when view_tardoc_db() starts a session.
# All JavaScript lives in the template — no R string escaping required.

#' Generate the server analytics viewer template
#'
#' Writes `analytics.html` into `cfg$site_path` using
#' `inst/templates/analytics.html`. This file is a server template:
#' open it via `view_tardoc_db()`, not directly in a browser.
#'
#' @param cfg      A site config list.
#' @param pkg_name Character. Project title shown in the viewer header.
#'
#' @return Path to `analytics.html` invisibly.
#' @export
generate_analytics_viewer <- function(cfg, pkg_name = "targets docs") {
  tpl  <- .load_template("analytics.html")
  html <- gsub("{{PKG_NAME}}", pkg_name, tpl, fixed = TRUE)

  out_path <- file.path(cfg$site_path, "analytics.html")
  writeLines(html, out_path, useBytes = TRUE)
  message("Analytics viewer written: ", out_path)
  invisible(out_path)
}

#' Inject Quack session credentials into the analytics template
#'
#' Reads `analytics.html`, replaces the placeholder tokens with live values,
#' and writes `_session_analytics.html` — the file served at
#' `http://localhost:<port>` by [view_tardoc_db()].
#'
#' @param cfg         A site config list.
#' @param token       Quack authentication token.
#' @param quack_port  Port the Quack server is listening on.
#' @param has_faiss   Logical. Whether the FAISS index was built.
#' @param llm_enabled Logical. Whether an LLM chat backend is available.
#'
#' @return Path to `_session_analytics.html` invisibly.
#' @export
inject_quack_session <- function(cfg, token, quack_port,
                                  has_faiss = FALSE, llm_enabled = FALSE) {
  tpl  <- file.path(cfg$site_path, "analytics.html")
  if (!file.exists(tpl))
    stop("analytics.html not found. Run document_targets() first.")

  html <- paste(readLines(tpl, warn = FALSE), collapse = "\n")
  html <- gsub("__QUACK_TOKEN__", token,                    html, fixed = TRUE)
  html <- gsub("__QUACK_PORT__",  as.character(quack_port), html, fixed = TRUE)
  html <- gsub("__HAS_FAISS__",   tolower(has_faiss),       html, fixed = TRUE)
  html <- gsub("__LLM_ENABLED__", tolower(llm_enabled),     html, fixed = TRUE)

  out <- file.path(cfg$site_path, "_session_analytics.html")
  writeLines(html, out, useBytes = TRUE)
  invisible(out)
}
