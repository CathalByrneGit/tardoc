# R/generate_search_index.R

#' Generate a search index for the viewer
#'
#' Writes `search_index.json` into `cfg$site_path`. The viewer uses this for
#' instant full-text search across all targets and functions without any
#' server-side infrastructure.
#'
#' @param targets_data   Output of [load_targets_data()].
#' @param function_names Character vector of function names from
#'   [generate_all_function_pages()].
#' @param cfg            A site config list.
#'
#' @return Path to `search_index.json` invisibly.
#' @export
generate_search_index <- function(targets_data, function_names, cfg) {
  target_entries <- lapply(targets_data$target_names, function(target_name) {
    manifest_row <- dplyr::filter(targets_data$manifest, .data$name == target_name)
    meta_row     <- dplyr::filter(targets_data$meta,     .data$name == target_name)
    dep          <- get_target_network_dependencies(
      target_name, targets_data$network, max_depth_up = 1, max_depth_down = 1
    )

    description <- .pull_description(manifest_row)
    command     <- dplyr::pull(manifest_row, "command")
    status      <- if (is.na(meta_row$error)) "uptodate" else "errored"

    list(
      type        = "target",
      name        = target_name,
      description = if (is.na(description)) "" else description,
      command     = command,
      upstream    = as.list(dep$upstream),
      downstream  = as.list(dep$downstream),
      status      = status,
      file        = paste0("targets/", target_name, ".md")
    )
  })

  function_entries <- lapply(function_names, function(fn_name) {
    # Find which R file defines this function
    r_files   <- list.files(cfg$r_scripts_dir, pattern = "\\.R$", full.names = TRUE)
    src_file  <- .find_function_file(fn_name, r_files)
    docs      <- if (!is.null(src_file)) {
      suppressWarnings(get_fn_docs(fn_name, src_file))
    } else NULL
    short_desc <- if (!is.null(docs)) .extract_description(docs) else ""

    list(
      type        = "function",
      name        = fn_name,
      description = short_desc,
      source_file = if (!is.null(src_file)) basename(src_file) else "",
      file        = paste0("functions/", fn_name, ".md")
    )
  })

  index <- list(
    generated = as.character(Sys.time()),
    targets   = target_entries,
    functions = function_entries
  )

  out_path <- file.path(cfg$site_path, "search_index.json")
  writeLines(jsonlite::toJSON(index, auto_unbox = TRUE, pretty = TRUE),
             out_path)
  message("Search index written: ", out_path)
  invisible(out_path)
}

# ---- private ----------------------------------------------------------------

.find_function_file <- function(func_name, r_files) {
  for (f in r_files) {
    env <- new.env(parent = emptyenv())
    tryCatch(source(f, local = env), error = function(e) NULL)
    if (func_name %in% ls(env)) return(f)
  }
  NULL
}
