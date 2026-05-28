# R/generate_tardoc_db.R
#
# Generates tardoc/tardoc.duckdb — the server-side DuckDB database.
# Capability layers (each gracefully optional):
#
#   1. Always:   targets, functions, edges tables
#   2. Always:   built-in FTS index
#   3. Optional: quackformers  → BERT embeddings (384-dim)
#   4. Optional: faiss         → HNSW32 ANN index on embeddings
#   5. Optional: sitting_duck  → function_calls table (R AST)
#   6. Optional: duck_tails    → git_history table
#   7. Optional: duckdb_mcp    → install extension + write MCP config
#   8. Always:   _meta table recording which capabilities were built

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
#'   `sitting_duck` (R code AST), `duck_tails` (git history), `duckdb_mcp`
#'   (MCP server config). Each step is wrapped in `tryCatch`; failures are
#'   skipped silently. Default `FALSE` — core tables and FTS only.
#'
#' @return Path to `tardoc.duckdb` invisibly, or `NULL` if the `duckdb`
#'   package is not installed.
#' @export
generate_tardoc_db <- function(targets_data, function_names, cfg,
                               db_extensions = FALSE) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    message("'duckdb' not installed — skipping tardoc.duckdb. ",
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
  tryCatch({
    tryCatch(
      DBI::dbExecute(con, "LOAD fts;"),  # bundled on most systems
      error = function(e) DBI::dbExecute(con, "INSTALL fts; LOAD fts;")  # download if needed
    )
    DBI::dbExecute(con, "PRAGMA create_fts_index('targets',   'name', 'name', 'description', 'command')")
    DBI::dbExecute(con, "PRAGMA create_fts_index('functions', 'name', 'name', 'description')")
    has_fts <- TRUE
    message("  FTS index built.")
  }, error = function(e) message("  FTS unavailable: ", conditionMessage(e)))

  # ---- 3–7. Community extensions (opt-in) ---------------------------------
  if (!isTRUE(db_extensions)) {
    message("  Skipping community extensions (db_extensions = FALSE).")
    message("  Re-run with db_extensions = TRUE to add semantic search,")
    message("  code intelligence, git history, and MCP support.")
  }

  # ---- 3. Embeddings (quackformers) ----------------------------------------
  has_embeddings <- FALSE
  if (isTRUE(db_extensions)) tryCatch({
    message("  Installing quackformers (BERT embeddings)...")
    DBI::dbExecute(con, "INSTALL quackformers FROM community; LOAD quackformers;")
    DBI::dbExecute(con, "ALTER TABLE targets   ADD COLUMN embedding FLOAT[]")
    DBI::dbExecute(con, "ALTER TABLE functions ADD COLUMN embedding FLOAT[]")
    DBI::dbExecute(con, "UPDATE targets   SET embedding = embed(COALESCE(description,'') || ' ' || command)")
    DBI::dbExecute(con, "UPDATE functions SET embedding = embed(COALESCE(description,'') || ' ' || name)")
    has_embeddings <- TRUE
    message("  Embeddings generated.")
  }, error = function(e) message("  quackformers unavailable: ", conditionMessage(e)))

  # ---- 4. FAISS (semantic index) -------------------------------------------
  has_faiss <- FALSE
  if (isTRUE(db_extensions) && has_embeddings) {
    tryCatch({
      message("  Installing faiss (HNSW32 index)...")
      DBI::dbExecute(con, "INSTALL faiss FROM community; LOAD faiss;")
      DBI::dbExecute(con, "CALL FAISS_CREATE('target_semantic',   384, 'IDMap,HNSW32')")
      DBI::dbExecute(con, "CALL FAISS_CREATE('function_semantic', 384, 'IDMap,HNSW32')")
      DBI::dbExecute(con, "CALL FAISS_ADD((SELECT rowid, embedding FROM targets   WHERE embedding IS NOT NULL), 'target_semantic')")
      DBI::dbExecute(con, "CALL FAISS_ADD((SELECT rowid, embedding FROM functions WHERE embedding IS NOT NULL), 'function_semantic')")
      has_faiss <- TRUE
      message("  FAISS index built.")
    }, error = function(e) message("  faiss unavailable: ", conditionMessage(e)))
  }

  # ---- 5 & 6. Code intelligence (sitting_duck + duck_tails) ----------------
  ci <- if (isTRUE(db_extensions)) generate_code_intelligence(con, cfg) else
          list(has_ast = FALSE, has_git = FALSE)
  has_ast <- isTRUE(ci$has_ast)
  has_git <- isTRUE(ci$has_git)

  # ---- 7. duckdb_mcp: install + write config --------------------------------
  has_mcp <- FALSE
  if (isTRUE(db_extensions)) tryCatch({
    message("  Installing duckdb_mcp...")
    DBI::dbExecute(con, "INSTALL duckdb_mcp FROM community; LOAD duckdb_mcp;")
    .write_mcp_config(cfg, db_path)
    has_mcp <- TRUE
    message("  MCP config written: ", file.path(cfg$site_path, "tardoc_mcp_config.json"))
  }, error = function(e) message("  duckdb_mcp unavailable: ", conditionMessage(e)))

  # ---- 8. Capability metadata ----------------------------------------------
  DBI::dbExecute(con, sprintf(
    "CREATE TABLE _meta AS SELECT %s AS has_fts, %s AS has_embeddings,
     %s AS has_faiss, %s AS has_ast, %s AS has_git, %s AS has_mcp",
    tolower(has_fts), tolower(has_embeddings), tolower(has_faiss),
    tolower(has_ast), tolower(has_git), tolower(has_mcp)
  ))

  message("tardoc.duckdb ready: ", db_path)
  message(sprintf(
    "  FTS=%s  Embeddings=%s  FAISS=%s  AST=%s  Git=%s  MCP=%s",
    has_fts, has_embeddings, has_faiss, has_ast, has_git, has_mcp
  ))

  invisible(db_path)
}

# ---- private ----------------------------------------------------------------

.create_core_tables <- function(con, targets_data, function_names, cfg) {
  target_rows <- lapply(targets_data$target_names, function(tn) {
    manifest_row <- dplyr::filter(targets_data$manifest, .data$name == tn)
    meta_row     <- dplyr::filter(targets_data$meta,     .data$name == tn)
    dep          <- get_target_network_dependencies(
      tn, targets_data$network, max_depth_up = Inf, max_depth_down = Inf
    )
    desc       <- .pull_desc_db(manifest_row)
    command    <- dplyr::pull(manifest_row, "command")
    status     <- if (is.na(meta_row$error)) "uptodate" else "errored"
    last_built <- as.character(meta_row$time)
    data.frame(
      name         = tn,
      description  = if (is.na(desc)) "" else desc,
      command      = command,
      status       = status,
      last_built   = if (is.na(last_built)) "" else last_built,
      n_upstream   = length(dep$upstream),
      n_downstream = length(dep$downstream),
      notes        = read_note(tn, "targets", cfg),
      stringsAsFactors = FALSE
    )
  })
  DBI::dbWriteTable(con, "targets", do.call(rbind, target_rows), overwrite = TRUE)

  r_files <- list.files(cfg$r_scripts_dir, pattern = "\\.R$", full.names = TRUE)
  func_rows <- lapply(function_names, function(fn) {
    src  <- .find_src_db(fn, r_files)
    docs <- if (!is.null(src)) suppressWarnings(get_fn_docs(fn, src)) else NULL
    desc <- if (!is.null(docs)) .extract_desc_db(docs) else ""
    data.frame(name = fn, description = desc,
               source_file = if (!is.null(src)) basename(src) else "",
               notes = read_note(fn, "functions", cfg),
               stringsAsFactors = FALSE)
  })
  DBI::dbWriteTable(con, "functions", do.call(rbind, func_rows), overwrite = TRUE)

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

.pull_desc_db <- function(manifest_row) {
  if (!"description" %in% names(manifest_row)) return(NA_character_)
  val <- dplyr::pull(manifest_row, "description")
  if (length(val) == 0 || is.na(val) || nchar(trimws(val)) == 0) NA_character_ else val
}
.find_src_db <- function(fn, r_files) {
  for (f in r_files) {
    env <- new.env(parent = globalenv())
    tryCatch(source(f, local = env), error = function(e) NULL)
    if (fn %in% ls(env)) return(f)
  }
  NULL
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
