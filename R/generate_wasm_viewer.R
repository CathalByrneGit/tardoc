# R/generate_wasm_viewer.R
#
# Tier 2 — self-contained WASM analytics viewer.
# Loads inst/templates/wasm_analytics.html and embeds the analytics dataset.
# Opens as file:// with no server: share, deploy to GitHub Pages, etc.

#' Generate the self-contained WASM analytics viewer
#'
#' Writes `wasm_analytics.html` into `cfg$site_path` using
#' `inst/templates/wasm_analytics.html`. All pipeline data is embedded
#' directly so the file opens as `file://` with no server required.
#'
#' @param analytics_data A list with `targets`, `functions`, `edges` (and
#'   optionally `function_calls`, `git_history`) from
#'   [.build_analytics_data()].
#' @param cfg            A site config list.
#' @param pkg_name       Character. Project title.
#'
#' @return Path to `wasm_analytics.html` invisibly.
#' @export
generate_wasm_viewer <- function(analytics_data, cfg, pkg_name = "targets docs") {
  tpl <- .load_template("wasm_analytics.html")

  # Embed the analytics data as a JS constant
  data_json <- jsonlite::toJSON(analytics_data, auto_unbox = TRUE)
  # Escape </script> so the embedded JSON cannot break the script tag
  data_json <- gsub("</script>", "<\\/script>", data_json, fixed = TRUE)

  html <- tpl
  html <- gsub("{{PKG_NAME}}",      pkg_name,                                     html, fixed = TRUE)
  html <- gsub("{{PKG_NAME_JSON}}", jsonlite::toJSON(pkg_name, auto_unbox = TRUE), html, fixed = TRUE)
  html <- gsub("{{ANALYTICS_DATA}}", data_json,                                   html, fixed = TRUE)

  out_path <- file.path(cfg$site_path, "wasm_analytics.html")
  writeLines(html, out_path, useBytes = TRUE)
  message("WASM viewer written: ", out_path)
  invisible(out_path)
}
