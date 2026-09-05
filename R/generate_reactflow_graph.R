# R/generate_reactflow_graph.R
#
# PROTOTYPE -- an alternative pipeline graph rendered with React Flow instead of
# mermaid, written as a separate page so the two can be compared side by side.
# Nothing in the existing viewer changes.
#
# Why bother: mermaid.min.js is ~3.5 MB. React Flow v11 plus React and ReactDOM
# is ~300 KB, and brings draggable nodes, a minimap and real pan/zoom rather
# than a static SVG in a hand-rolled modal.
#
# What it costs: React Flow does no layout, so positions must be supplied. See
# dag_layout(). The approach is borrowed from dplyneage, which renders
# column-level lineage the same way.

#' Generate the React Flow pipeline graph page
#'
#' Writes `reactflow_graph.html` into `cfg$site_path`: an interactive,
#' pan-and-zoom rendering of the target DAG. Experimental, and not part of a
#' default [document_targets()] run.
#'
#' @param targets_data Output of [load_targets_data()].
#' @param cfg A site config list.
#' @param pkg_name Character. Project title.
#'
#' @return Path to `reactflow_graph.html`, invisibly.
#' @export
generate_reactflow_graph <- function(targets_data, cfg,
                                     pkg_name = "targets docs") {
  graph <- build_dag_graph(targets_data)

  tpl  <- .load_template("reactflow_graph.html")
  json <- jsonlite::toJSON(graph, auto_unbox = TRUE)
  # Escaped so the embedded JSON cannot terminate the script element early.
  json <- gsub("</script>", "<\\/script>", json, fixed = TRUE)

  html <- gsub("{{PKG_NAME}}",   pkg_name, tpl,  fixed = TRUE)
  html <- gsub("{{GRAPH_JSON}}", json,     html, fixed = TRUE)

  out <- file.path(cfg$site_path, "reactflow_graph.html")
  writeLines(html, out, useBytes = TRUE)
  message("React Flow graph written: ", out)
  invisible(out)
}
