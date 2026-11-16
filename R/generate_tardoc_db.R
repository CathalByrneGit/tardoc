# R/generate_tardoc_db.R
#
# Generates tardoc/tardoc.duckdb -- the server-side DuckDB database.
# Capability layers (each gracefully optional):
#
#   1. Always:   targets, functions, edges tables
#   2. Always:   built-in FTS index
#   3. Optional: quackformers  -> BERT embeddings (384-dim)
#   4. Optional: faiss         -> HNSW32 ANN index on embeddings
#   7. Optional: duckdb_mcp    -> install extension + write MCP config
#   8. Always:   _meta (wide flags) + _meta_detail (flags plus skip reason)

#' Generate the tardoc DuckDB analytics database
#'
#' Creates `tardoc/tardoc.duckdb`. Attempts each capability layer in turn;
#' skips cleanly if the required extension is unavailable. The `_meta` table
#' records which capabilities succeeded so the analytics viewer can adapt its
#' UI accordingly.
#'
#' @param targets_data   Output of [load_targets_data()].
#' @param function_names Character vector of function names.
#' @param cfg            A site config list.
#' @param db_extensions Logical. When `TRUE`, attempts to install community
#'   extensions: `quackformers` (BERT embeddings), `faiss` (ANN index),
#'   `duckdb_mcp`
#'   (MCP server config). Each step is wrapped in `tryCatch`; a failure skips
#'   that layer and the reason is recorded in the `_meta_detail` table.
#'   Default `FALSE` -- core tables and FTS only.
#'
#' @return Path to `tardoc.duckdb` invisibly, or `NULL` if the `duckdb`
#'   package is not installed.
#' @export
generate_tardoc_db <- function(targets_data, function_names, cfg,
                               db_extensions = FALSE) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    message("'duckdb' not installed -- skipping tardoc.duckdb. ",
            "Install with: install.packages('duckdb')")
    return(invisible(NULL))
  }

  db_path <- file.path(cfg$site_path, "tardoc.duckdb")
  if (file.exists(db_path)) file.remove(db_path)

  con <- duckdb::dbConnect(duckdb::duckdb(), db_path)
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  message("Building tardoc.duckdb...")

  # ---- 1. Core tables -------------------------------------------------------
  .create_core_tables(con, targets_data, function_names, cfg)

  # ---- 2. FTS (built-in) ---------------------------------------------------
  has_fts <- FALSE
  fts_error <- NA_character_
  tryCatch({
    tryCatch(
      DBI::dbExecute(con, "LOAD fts;"),  # bundled on most systems
      error = function(e) DBI::dbExecute(con, "INSTALL fts; LOAD fts;")  # download if needed
    )
    DBI::dbExecute(con, "PRAGMA create_fts_index('targets',   'name', 'name', 'description', 'command')")
    DBI::dbExecute(con, "PRAGMA create_fts_index('functions', 'name', 'name', 'description')")
    has_fts <- TRUE
    message("  FTS index built.")
  }, error = function(e) {
    fts_error <<- conditionMessage(e)
    message("  FTS unavailable: ", conditionMessage(e))
  })

  # ---- 3-7. Community extensions (opt-in) ---------------------------------
  if (!isTRUE(db_extensions)) {
    message("  Skipping community extensions (db_extensions = FALSE).")
    message("  Re-run with db_extensions = TRUE to add semantic search")
    message("  and MCP support.")
  }

  # ---- 3. Embeddings (quackformers) ----------------------------------------
  has_embeddings <- FALSE
  emb_error <- if (!isTRUE(db_extensions)) "db_extensions = FALSE" else NA_character_
  if (isTRUE(db_extensions)) tryCatch({
    message("  Installing quackformers (BERT embeddings)...")
    DBI::dbExecute(con, "INSTALL quackformers FROM community; LOAD quackformers;")
    DBI::dbExecute(con, "ALTER TABLE targets   ADD COLUMN embedding FLOAT[]")
    DBI::dbExecute(con, "ALTER TABLE functions ADD COLUMN embedding FLOAT[]")
    DBI::dbExecute(con, "UPDATE targets   SET embedding = embed(COALESCE(description,'') || ' ' || command)")
    DBI::dbExecute(con, "UPDATE functions SET embedding = embed(COALESCE(description,'') || ' ' || name)")
    has_embeddings <- TRUE
    message("  Embeddings generated.")
  }, error = function(e) {
    emb_error <<- conditionMessage(e)
    message("  quackformers unavailable: ", conditionMessage(e))
  })

  # ---- 4. FAISS (semantic index) -------------------------------------------
  has_faiss <- FALSE
  faiss_error <- if (!isTRUE(db_extensions)) "db_extensions = FALSE"
                 else if (!has_embeddings) "requires embeddings"
                 else NA_character_
  if (isTRUE(db_extensions) && has_embeddings) {
    tryCatch({
      message("  Installing faiss (HNSW32 index)...")
      DBI::dbExecute(con, "INSTALL faiss FROM community; LOAD faiss;")
      for (idx in names(.faiss_indexes)) {
        tbl <- .faiss_indexes[[idx]]
        DBI::dbExecute(con, sprintf(
          "CALL FAISS_CREATE('%s', %d, 'IDMap,HNSW32')", idx, .embedding_dim))
        DBI::dbExecute(con, sprintf(
          "CALL FAISS_ADD((SELECT rowid, embedding FROM %s WHERE embedding IS NOT NULL), '%s')",
          tbl, idx))
        # A FAISS index lives in the extension, not in the .duckdb file. Without
        # an explicit save it is discarded on disconnect and every later
        # FAISS_SEARCH fails, so persist it to a sidecar next to the database.
        DBI::dbExecute(con, sprintf(
          "CALL FAISS_SAVE('%s', %s)", idx,
          DBI::dbQuoteString(con, .faiss_index_path(cfg, idx))))
      }
      has_faiss <- TRUE
      message("  FAISS indexes built and saved to ", cfg$site_path, ".")
    }, error = function(e) {
      faiss_error <<- conditionMessage(e)
      message("  faiss unavailable: ", conditionMessage(e))
    })
  }

  # ---- 5. duckdb_mcp: install + write config --------------------------------
  has_mcp <- FALSE
  mcp_error <- if (!isTRUE(db_extensions)) "db_extensions = FALSE" else NA_character_
  if (isTRUE(db_extensions)) tryCatch({
    message("  Installing duckdb_mcp...")
    DBI::dbExecute(con, "INSTALL duckdb_mcp FROM community; LOAD duckdb_mcp;")
    .write_mcp_config(cfg, db_path)
    has_mcp <- TRUE
    message("  MCP config written: ", file.path(cfg$site_path, "tardoc_mcp_config.json"))
  }, error = function(e) {
    mcp_error <<- conditionMessage(e)
    message("  duckdb_mcp unavailable: ", conditionMessage(e))
  })

  # ---- 6. Capability metadata ----------------------------------------------
  # One row per capability, with the reason it is off. Recording the reason
  # means a FALSE flag is diagnosable instead of just mysterious.
  meta <- data.frame(
    capability = c("fts", "embeddings", "faiss", "mcp"),
    available  = c(has_fts, has_embeddings, has_faiss, has_mcp),
    reason     = c(fts_error, emb_error, faiss_error, mcp_error),
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, "_meta_detail", meta, overwrite = TRUE)

  # Wide single-row _meta is the shape view_tardoc_db() and the README
  # document, so it stays exactly as it was; _meta_detail carries the reasons.
  DBI::dbExecute(con, sprintf(
    "CREATE TABLE _meta AS SELECT %s AS has_fts, %s AS has_embeddings,
     %s AS has_faiss, %s AS has_mcp",
    tolower(has_fts), tolower(has_embeddings), tolower(has_faiss),
    tolower(has_mcp)
  ))

  message("tardoc.duckdb ready: ", db_path)
  message(sprintf(
    "  FTS=%s  Embeddings=%s  FAISS=%s  MCP=%s",
    has_fts, has_embeddings, has_faiss, has_mcp
  ))

  invisible(db_path)
}

# ---- private ----------------------------------------------------------------

.create_core_tables <- function(con, targets_data, function_names, cfg) {
  target_rows <- lapply(targets_data$target_names, function(tn) {
    dep <- get_target_network_dependencies(
      tn, targets_data$network, max_depth_up = Inf, max_depth_down = Inf
    )
    b <- .target_basics(tn, targets_data)
    data.frame(
      name         = tn,
      description  = b$description,
      command      = b$command,
      status       = b$status,
      last_built   = b$last_built,
      n_upstream   = length(dep$upstream),
      n_downstream = length(dep$downstream),
      notes        = read_note(tn, "targets", cfg),
      stringsAsFactors = FALSE
    )
  })
  # do.call(rbind, list()) is NULL, which dbWriteTable cannot write. A pipeline
  # with no targets, or with no documented functions, must still produce the
  # tables the viewer queries -- empty, not absent.
  DBI::dbWriteTable(con, "targets",
                    .rows_or_empty(target_rows, .targets_proto), overwrite = TRUE)

  r_files <- .function_r_files(cfg)
  func_rows <- lapply(function_names, function(fn) {
    src  <- .find_function_file(fn, r_files)
    docs <- if (!is.null(src)) suppressWarnings(get_fn_docs(fn, src)) else NULL
    desc <- if (!is.null(docs)) .extract_desc_db(docs) else ""
    data.frame(name = fn, description = desc,
               source_file = if (!is.null(src)) basename(src) else "",
               notes = read_note(fn, "functions", cfg),
               stringsAsFactors = FALSE)
  })
  DBI::dbWriteTable(con, "functions",
                    .rows_or_empty(func_rows, .functions_proto), overwrite = TRUE)

  edges_df       <- as.data.frame(targets_data$network$edges)
  names(edges_df) <- c("from_target", "to_target")
  DBI::dbWriteTable(con, "edges", edges_df, overwrite = TRUE)
  message("  Core tables written.")
}

.write_mcp_config <- function(cfg, db_path) {
  # Generate a Claude Desktop config snippet.
  # The duckdb_mcp extension exposes the database via the MCP stdio protocol
  # when invoked as: duckdb <db> -c "LOAD duckdb_mcp; CALL mcp_serve();"
  config <- list(
    mcpServers = list(
      tardoc = list(
        command  = "duckdb",
        args     = list(
          normalizePath(db_path),
          "-unsigned",
          "-c",
          "INSTALL duckdb_mcp FROM community; LOAD duckdb_mcp; CALL mcp_serve();"
        ),
        env = list()
      )
    )
  )
  out <- file.path(cfg$site_path, "tardoc_mcp_config.json")
  writeLines(jsonlite::toJSON(config, pretty = TRUE, auto_unbox = TRUE), out)
  invisible(out)
}

.extract_desc_db <- function(docs_md) {
  lines <- strsplit(docs_md, "\n")[[1]]
  in_d  <- FALSE; dl <- character()
  for (l in lines) {
    if (grepl("^##\\s+Description", l, ignore.case = TRUE)) { in_d <- TRUE; next }
    if (in_d) { if (grepl("^##", l)) break; dl <- c(dl, l) }
  }
  trimws(paste(dl, collapse = "\n"))
}

# Embedding width produced by quackformers' embed(); embed_jina() is 768.
.embedding_dim <- 384L

# FAISS index name -> source table.
.faiss_indexes <- list(
  target_semantic   = "targets",
  function_semantic = "functions"
)

#' Path of a persisted FAISS index sidecar
#'
#' @param cfg A site config list.
#' @param idx FAISS index name.
#' @return Absolute path to the index file.
#' @keywords internal
.faiss_index_path <- function(cfg, idx) {
  file.path(cfg$site_path, paste0(idx, ".faiss"))
}

# Empty-table schemas, so the viewer's queries resolve even when a pipeline has
# no targets or no documented functions.
.targets_proto <- data.frame(
  name = character(), description = character(), command = character(),
  status = character(), last_built = character(),
  n_upstream = integer(), n_downstream = integer(), notes = character(),
  stringsAsFactors = FALSE
)

.functions_proto <- data.frame(
  name = character(), description = character(),
  source_file = character(), notes = character(),
  stringsAsFactors = FALSE
)

#' Bind row data frames, falling back to an empty typed schema
#'
#' @param rows  A list of one-row data frames, possibly empty.
#' @param proto A zero-row data frame giving the column names and types.
#' @return A data frame; `proto` when `rows` is empty.
#' @keywords internal
.rows_or_empty <- function(rows, proto) {
  if (length(rows) == 0) proto else do.call(rbind, rows)
}
