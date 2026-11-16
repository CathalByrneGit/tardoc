# R/generate_analytics_data.R

#' Generate the analytics dataset for the DuckDB WASM viewer
#'
#' Writes `tardoc_analytics.json` into `cfg$site_path`. This is a richer
#' dataset than `search_index.json` -- it includes the full edge list (for
#' graph traversal), notes content, and all fields needed for SQL analytics.
#' The DuckDB WASM analytics viewer loads this file and ingests it into
#' in-browser tables.
#'
#' @param targets_data   Output of [load_targets_data()].
#' @param function_names Character vector of function names.
#' @param cfg            A site config list.
#'
#' @return Path to `tardoc_analytics.json` invisibly.
#' @export
generate_analytics_data <- function(targets_data, function_names, cfg) {

  # ---- targets table --------------------------------------------------------
  target_rows <- lapply(targets_data$target_names, function(target_name) {
    dep <- get_target_network_dependencies(
      target_name, targets_data$network,
      max_depth_up = Inf, max_depth_down = Inf
    )

    b <- .target_basics(target_name, targets_data)

    list(
      name          = target_name,
      description   = b$description,
      command       = b$command,
      status        = b$status,
      last_built    = b$last_built,
      n_upstream    = length(dep$upstream),
      n_downstream  = length(dep$downstream),
      notes         = read_note(target_name, "targets", cfg)
    )
  })

  # ---- functions table ------------------------------------------------------
  r_files <- .function_r_files(cfg)

  function_rows <- lapply(function_names, function(fn_name) {
    src_file   <- .find_function_file(fn_name, r_files)
    docs       <- if (!is.null(src_file)) suppressWarnings(get_fn_docs(fn_name, src_file)) else NULL
    short_desc <- if (!is.null(docs)) .extract_desc(docs) else ""

    list(
      name        = fn_name,
      description = short_desc,
      source_file = if (!is.null(src_file)) basename(src_file) else "",
      notes       = read_note(fn_name, "functions", cfg)
    )
  })

  # ---- edges table ----------------------------------------------------------
  # Full edge list from the network -- used for recursive graph queries
  edges <- targets_data$network$edges
  edge_rows <- lapply(seq_len(nrow(edges)), function(i) {
    list(from_target = edges$from[i], to_target = edges$to[i])
  })

  # ---- assemble and write ---------------------------------------------------
  analytics <- list(
    generated = as.character(Sys.time()),
    targets   = target_rows,
    functions = function_rows,
    edges     = edge_rows
  )

  out_path <- file.path(cfg$site_path, "tardoc_analytics.json")
  writeLines(jsonlite::toJSON(analytics, auto_unbox = TRUE, pretty = FALSE),
             out_path)
  message("Analytics data written: ", out_path)
  invisible(out_path)
}

# ---- private ----------------------------------------------------------------

.extract_desc <- function(docs_md) {
  lines      <- strsplit(docs_md, "\n")[[1]]
  in_desc    <- FALSE
  desc_lines <- character()
  for (line in lines) {
    if (grepl("^##\\s+Description", line, ignore.case = TRUE)) {
      in_desc <- TRUE; next
    }
    if (in_desc) {
      if (grepl("^##", line)) break
      desc_lines <- c(desc_lines, line)
    }
  }
  trimws(paste(desc_lines, collapse = "\n"))
}
