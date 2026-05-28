# R/document_targets.R

#' Document a targets project
#'
#' Generates all tardoc output: markdown pages, Tier 1 viewer, Tier 2 WASM
#' analytics viewer, Tier 3/4 server analytics database, and `llms.txt`.
#'
#' **Tiers produced:**
#' - Tier 1: `viewer.html` — opens as `file://`, no server
#' - Tier 2: `wasm_analytics.html` — DuckDB WASM, opens as `file://`, data embedded
#' - Tier 3/4: `tardoc.duckdb` — for `view_tardoc_db()` with Quack + LLM chat
#'
#' @param project_path  Path to the targets project root. Default `"."`.
#' @param site_dir      Subfolder for all generated content. Default `"tardoc"`.
#' @param pkg_name      Title shown in viewer headers.
#' @param pkg_desc      One-paragraph project description (used in `llms.txt`).
#' @param repo_url      Optional base URL of the hosted repo for source links.
#' @param llm           Logical. Auto-generate missing target descriptions and
#'   function explanations via an LLM. Default `FALSE`.
#' @param llm_chat      A pre-configured ellmer `Chat` object. When provided,
#'   `llm_provider`, `llm_model`, `llm_api_key`, and `llm_base_url` are ignored.
#' @param llm_provider  Provider for LLM calls. One of `"openai"` (default),
#'   `"anthropic"`, `"ollama"`, `"openai_compatible"`.
#' @param llm_model     Model name. `NULL` uses the ellmer default per provider.
#' @param llm_api_key   API key. `NULL` reads the env var.
#' @param llm_base_url  Base URL for `"openai_compatible"` provider (e.g. a
#'   llama.cpp server: `"http://localhost:8080/v1"`).
#'
#' @return The `cfg` list, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' # Minimal — Tier 1 + 2 always, Tier 3 if duckdb installed
#' document_targets(pkg_name = "My pipeline")
#' view_tardoc()              # Tier 1: file:// viewer
#' view_wasm_analytics()      # Tier 2: WASM, file://
#' view_tardoc_db()           # Tier 3: server + Quack
#'
#' # With LLM descriptions (OpenAI by default, reads OPENAI_API_KEY)
#' document_targets(llm = TRUE)
#'
#' # Local LLM via Ollama
#' document_targets(llm = TRUE, llm_provider = "ollama", llm_model = "llama3.2")
#'
#' # Analytics + chat with any provider
#' view_tardoc_db(llm_chat = ellmer::chat_openai())
#' view_tardoc_db(llm_chat = ellmer::chat_ollama("llama3.2"))
#' }
document_targets <- function(project_path  = ".",
                              site_dir      = "tardoc",
                              pkg_name      = "targets docs",
                              pkg_desc      = "",
                              repo_url      = NULL,
                              llm           = FALSE,
                              llm_chat      = NULL,
                              llm_provider  = "openai",
                              llm_model     = NULL,
                              llm_api_key   = NULL,
                              llm_base_url  = NULL) {

  cfg <- build_site_config(project_path, site_dir, repo_url)
  setup_site_dirs(cfg)

  targets_data   <- load_targets_data(cfg)
  target_names   <- generate_all_target_pages(targets_data, cfg)
  function_names <- generate_all_function_pages(cfg)

  generate_notes(target_names, function_names, cfg)
  generate_search_index(targets_data, function_names, cfg)
  generate_llms_txt(targets_data, cfg,
                     project_title = pkg_name, project_desc = pkg_desc)

  # Optional: LLM-generated descriptions and explanations
  if (isTRUE(llm)) {
    generate_llm_content(
      targets_data   = targets_data,
      function_names = function_names,
      cfg            = cfg,
      llm_chat       = llm_chat,
      provider       = llm_provider,
      model          = llm_model,
      api_key        = llm_api_key,
      base_url       = llm_base_url
    )
  }

  # Tier 1: self-contained viewer
  generate_viewer(targets_data, function_names, cfg, pkg_name)

  # Generate analytics data (used by both WASM and server analytics)
  analytics_data <- .build_analytics_data(targets_data, function_names, cfg)

  # Write the JSON file (used by server analytics fallback)
  writeLines(
    jsonlite::toJSON(analytics_data, auto_unbox = TRUE),
    file.path(cfg$site_path, "tardoc_analytics.json")
  )

  # Tier 2: WASM self-contained analytics viewer
  generate_wasm_viewer(analytics_data, cfg, pkg_name)

  # Tier 3 DB: server analytics database (requires duckdb)
  # Tier 3 HTML template: server analytics + chat viewer
  generate_analytics_viewer(cfg, pkg_name)

  message(
    "\nDone.\n",
    "  Tier 1 (static):     ", file.path(cfg$site_path, "viewer.html"), "\n",
    "  Tier 2 (WASM):       ", file.path(cfg$site_path, "wasm_analytics.html"), "\n",
    "  Tier 3 (server):     tardoc::view_tardoc_db()\n",
    "  Tier 3 + chat:       tardoc::view_tardoc_db(llm_chat = ellmer::chat_openai())\n",
    "  MCP (Claude Desktop): tardoc::serve_tardoc_mcp()\n",
    "  LLMs:                ", file.path(cfg$project_path, "llms.txt"), "\n",
    if (isTRUE(llm)) "" else
      "\nTip: rerun with llm=TRUE to auto-generate missing descriptions.\n"
  )
  invisible(cfg)
}

# ---- Viewer launchers -------------------------------------------------------

#' Open the Tier 1 static viewer (file://, no dependencies)
#'
#' @param project_path Path to the targets project root.
#' @param site_dir     Subfolder used in [document_targets()].
#' @export
view_tardoc <- function(project_path = ".", site_dir = "tardoc") {
  path <- file.path(normalizePath(project_path), site_dir, "viewer.html")
  if (!file.exists(path)) stop("viewer.html not found. Run document_targets() first.")
  utils::browseURL(paste0("file://", path))
  invisible(NULL)
}

#' Open the Tier 2 WASM analytics viewer (file://, no server needed)
#'
#' Opens `wasm_analytics.html` directly in the browser. DuckDB WASM is loaded
#' from CDN; all pipeline data is embedded in the HTML. Provides full SQL /
#' dplyr queries, BM25 search, and lineage — no R process required after
#' `document_targets()` has run.
#'
#' @param project_path Path to the targets project root.
#' @param site_dir     Subfolder used in [document_targets()].
#' @export
view_wasm_analytics <- function(project_path = ".", site_dir = "tardoc") {
  path <- file.path(normalizePath(project_path), site_dir, "wasm_analytics.html")
  if (!file.exists(path)) stop("wasm_analytics.html not found. Run document_targets() first.")
  utils::browseURL(paste0("file://", path))
  invisible(NULL)
}

#' Open the Tier 3 server analytics viewer (Quack + optional LLM chat)
#'
#' Starts a DuckDB Quack server (background process via `callr`) and a minimal
#' httpuv HTML server. The browser DuckDB WASM connects via Quack for all
#' queries. When `llm_chat` is provided, a `/chat` endpoint is exposed and the
#' Chat tab becomes active.
#'
#' @param project_path Path to the targets project root.
#' @param site_dir     Subfolder used in [document_targets()].
#' @param port         Port for the HTML server. Default `9000`.
#' @param quack_port   Port for the Quack DuckDB server. Default `9494`.
#' @param db_extensions Logical. Install community DuckDB extensions when
#'   building `tardoc.duckdb`: `quackformers` (BERT semantic search), `faiss`,
#'   `sitting_duck`, `duck_tails`, `duckdb_mcp`. Slow on first run. Default
#'   `FALSE`.
#' @param llm_chat     An ellmer `Chat` object for the chat interface.
#'   Any provider: `ellmer::chat_openai()`, `ellmer::chat_ollama("llama3.2")`,
#'   `ellmer::chat_anthropic()`, `ellmer::chat_openai_compatible(base_url)`.
#'   `NULL` (default) disables chat.
#' @export
view_tardoc_db <- function(project_path = ".", site_dir = "tardoc",
                            port = 9000, quack_port = 9494,
                            llm_chat = NULL,
                            db_extensions = FALSE) {
  for (pkg in c("httpuv", "duckdb", "callr", "DBI")) {
    if (!requireNamespace(pkg, quietly = TRUE))
      stop(sprintf("'%s' is required: install.packages('%s')", pkg, pkg))
  }

  site_path <- file.path(normalizePath(project_path), site_dir)
  db_path   <- file.path(site_path, "tardoc.duckdb")
  cfg       <- build_site_config(project_path, site_dir)

  # Generate tardoc.duckdb if it doesn't exist yet, or regenerate with
  # extensions if db_extensions = TRUE and was previously built without them
  if (!file.exists(db_path) || isTRUE(db_extensions)) {
    if (!requireNamespace("duckdb", quietly = TRUE)) {
      message("'duckdb' not installed — skipping database generation. ",
              "Install with: install.packages('duckdb')")
    } else {
      td <- load_targets_data(cfg)
      fn <- generate_all_function_pages(cfg)
      generate_tardoc_db(td, fn, cfg, db_extensions = db_extensions)
      # Regenerate analytics JSON so sidebar stays in sync with new functions
      analytics_data <- .build_analytics_data(td, fn, cfg)
      writeLines(
        jsonlite::toJSON(analytics_data, auto_unbox = TRUE),
        file.path(site_path, "tardoc_analytics.json")
      )
    }
  }

  if (!file.exists(file.path(site_path, "analytics.html")))
    stop("analytics.html not found. Run document_targets() first.")

  # Read capability flags
  has_faiss <- FALSE
  db_con    <- NULL
  if (file.exists(db_path)) {
    tryCatch({
      db_con    <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
      meta      <- DBI::dbGetQuery(db_con, "SELECT * FROM _meta LIMIT 1")
      has_faiss <- isTRUE(meta$has_faiss[1])
    }, error = function(e) NULL)
  }

  # Configure chat
  chat_con <- NULL
  sql_log  <- new.env(parent = emptyenv())
  sql_log$calls <- list()

  if (!is.null(llm_chat)) {
    if (!requireNamespace("ellmer", quietly = TRUE))
      stop("'ellmer' is required for chat: install.packages('ellmer')")
    if (file.exists(db_path)) {
      tryCatch(
        chat_con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE),
        error = function(e) NULL
      )
    }
    .configure_chat_for_analytics(llm_chat, chat_con, prefix = "")
    .patch_sql_tool_logging(llm_chat, chat_con, sql_log)
  }

  # Start Quack server in background
  token      <- paste(sample(c(letters, 0:9), 20, replace = TRUE), collapse = "")
  quack_proc <- NULL
  if (file.exists(db_path)) {
    message("Starting Quack server on port ", quack_port, "...")
    quack_proc <- tryCatch(
      callr::r_bg(
        func = function(db_path, token, quack_port) {
          con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
          DBI::dbExecute(con, "INSTALL quack FROM core_nightly; LOAD quack;")
          DBI::dbExecute(con, sprintf(
            "CALL quack_serve('quack:localhost:%d', token = '%s');",
            quack_port, token
          ))
        },
        args = list(db_path, token, quack_port),
        supervise = TRUE
      ),
      error = function(e) {
        message("Quack unavailable (", conditionMessage(e), ") — JSON fallback.")
        NULL
      }
    )
    Sys.sleep(1.5)
    if (!is.null(quack_proc) && !quack_proc$is_alive()) {
      message("Quack exited early — JSON fallback.")
      quack_proc <- NULL
    }
  }

  session_path <- inject_quack_session(
    cfg, token, quack_port,
    has_faiss   = has_faiss,
    llm_enabled = !is.null(llm_chat)
  )

  serve_file <- function(fp) {
    mime <- switch(tools::file_ext(fp),
      html = "text/html", json = "application/json",
      js = "application/javascript", "application/octet-stream")
    list(status  = 200L,
         headers = list("Content-Type" = mime,
                        "Access-Control-Allow-Origin" = "*"),
         body    = readBin(fp, "raw", file.info(fp)$size))
  }

  # Find a free port if the requested one is in use
  port <- .find_free_port(port)
  quack_port <- .find_free_port(quack_port)

  app <- list(call = function(req) {
    p <- req$PATH_INFO

    if (req$REQUEST_METHOD == "OPTIONS")
      return(list(status = 204L,
                  headers = list("Access-Control-Allow-Origin"  = "*",
                                 "Access-Control-Allow-Methods" = "POST, GET, OPTIONS",
                                 "Access-Control-Allow-Headers" = "Content-Type"),
                  body = ""))

    if (p == "/chat" && req$REQUEST_METHOD == "POST") {
      if (is.null(llm_chat))
        return(.json_resp(list(error = "LLM not configured.")))
      tryCatch({
        body <- jsonlite::fromJSON(rawToChar(req$rook.input$read()))
        if (isTRUE(body$clear)) {
          llm_chat$set_turns(list())
          sql_log$calls <- list()
          return(.json_resp(list(response = "Conversation cleared.")))
        }
        sql_log$calls <- list()
        response      <- llm_chat$chat(body$message, echo = FALSE)
        .json_resp(list(response = response, sql_calls = sql_log$calls))
      }, error = function(e) .json_resp(list(error = conditionMessage(e))))
    } else {
      fp <- if (p == "/" || p == "" || p == "/analytics") session_path
            else file.path(site_path, sub("^/", "", p))
      if (file.exists(fp)) serve_file(fp) else
        list(status = 404L, headers = list("Content-Type" = "text/plain"),
             body = "Not found")
    }
  })

  url <- paste0("http://localhost:", port)
  message("\nAnalytics viewer: ", url)
  if (!is.null(quack_proc)) message("Quack server:     quack:localhost:", quack_port)
  if (!is.null(llm_chat))   message("LLM chat:         enabled (", class(llm_chat)[1], ")")
  if (has_faiss)            message("Semantic search:  enabled")
  message("Press Ctrl+C to stop.\n")

  on.exit({
    if (!is.null(quack_proc) && quack_proc$is_alive()) quack_proc$kill()
    if (!is.null(db_con))   try(duckdb::dbDisconnect(db_con,   shutdown = TRUE), silent = TRUE)
    if (!is.null(chat_con)) try(duckdb::dbDisconnect(chat_con, shutdown = TRUE), silent = TRUE)
  }, add = TRUE)

  utils::browseURL(url)
  httpuv::runServer("0.0.0.0", port, app)
  invisible(NULL)
}

#' Expose the tardoc database as an MCP server for Claude Desktop / Claude Code
#'
#' Starts the DuckDB `duckdb_mcp` extension server, making `tardoc.duckdb`
#' queryable by any MCP-compatible LLM client. Also writes
#' `tardoc/tardoc_mcp_config.json` — add its contents to your Claude Desktop
#' configuration to make the pipeline database available as a persistent tool.
#'
#' @param project_path Path to the targets project root.
#' @param site_dir     Subfolder used in [document_targets()].
#' @param port         MCP server port. Default `8765`.
#' @export
serve_tardoc_mcp <- function(project_path = ".", site_dir = "tardoc", port = 8765) {
  if (!requireNamespace("callr", quietly = TRUE))
    stop("'callr' is required: install.packages('callr')")
  if (!requireNamespace("duckdb", quietly = TRUE))
    stop("'duckdb' is required: install.packages('duckdb')")

  site_path <- file.path(normalizePath(project_path), site_dir)
  db_path   <- file.path(site_path, "tardoc.duckdb")
  cfg_path  <- file.path(site_path, "tardoc_mcp_config.json")

  if (!file.exists(db_path))
    stop("tardoc.duckdb not found. Run document_targets() first.")

  # Print the Claude Desktop config for the user
  if (file.exists(cfg_path)) {
    message("Claude Desktop MCP config (add 'tardoc' to your claude_desktop_config.json):\n")
    cat(paste(readLines(cfg_path, warn = FALSE), collapse = "\n"), "\n\n")
  }

  message("Starting MCP server on port ", port, "...")
  message("Once running, Claude Desktop and Claude Code can query your pipeline database.")
  message("Press Ctrl+C to stop.\n")

  proc <- tryCatch(
    callr::r_bg(
      func = function(db_path, port) {
        con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
        DBI::dbExecute(con, "INSTALL duckdb_mcp FROM community; LOAD duckdb_mcp;")
        DBI::dbExecute(con, sprintf("CALL mcp_serve('0.0.0.0', %d);", port))
      },
      args = list(db_path, port),
      supervise = TRUE
    ),
    error = function(e) {
      message("Could not start MCP server: ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(proc)) return(invisible(NULL))

  Sys.sleep(2)
  if (!proc$is_alive()) {
    message("MCP server exited. The duckdb_mcp extension may not be available.")
    message("Ensure tardoc.duckdb was built with has_mcp=TRUE (shown in generate_tardoc_db output).")
    return(invisible(NULL))
  }

  on.exit(if (proc$is_alive()) proc$kill(), add = TRUE)
  proc$wait()
  invisible(NULL)
}

# ---- Internal helpers -------------------------------------------------------

#' Build analytics data list for WASM embedding and JSON file
#' @keywords internal
.build_analytics_data <- function(targets_data, function_names, cfg) {
  target_rows <- lapply(targets_data$target_names, function(tn) {
    manifest_row <- dplyr::filter(targets_data$manifest, .data$name == tn)
    meta_row     <- dplyr::filter(targets_data$meta,     .data$name == tn)
    dep          <- get_target_network_dependencies(
      tn, targets_data$network, max_depth_up = 1, max_depth_down = 1
    )
    desc       <- .ad_pull_desc(manifest_row)
    command    <- dplyr::pull(manifest_row, "command")
    status     <- if (is.na(meta_row$error)) "uptodate" else "errored"
    last_built <- as.character(meta_row$time)
    list(
      name = tn, description = if (is.na(desc)) "" else desc,
      command = command, status = status,
      last_built = if (is.na(last_built)) "" else last_built,
      n_upstream = length(dep$upstream), n_downstream = length(dep$downstream),
      notes = read_note(tn, "targets", cfg),
      upstream = as.list(dep$upstream), downstream = as.list(dep$downstream)
    )
  })

  r_files <- list.files(cfg$r_scripts_dir, pattern = "\\.R$", full.names = TRUE)
  func_rows <- lapply(function_names, function(fn) {
    src  <- .ad_find_src(fn, r_files)
    docs <- if (!is.null(src)) suppressWarnings(get_fn_docs(fn, src)) else NULL
    list(name = fn, description = if (!is.null(docs)) .ad_extract_desc(docs) else "",
         source_file = if (!is.null(src)) basename(src) else "",
         notes = read_note(fn, "functions", cfg))
  })

  edges <- targets_data$network$edges
  edge_rows <- lapply(seq_len(nrow(edges)), function(i)
    list(from_target = edges$from[i], to_target = edges$to[i])
  )

  list(
    generated = as.character(Sys.time()),
    targets   = target_rows,
    functions = func_rows,
    edges     = edge_rows
  )
}

.json_resp <- function(data) {
  list(status  = 200L,
       headers = list("Content-Type" = "application/json",
                      "Access-Control-Allow-Origin" = "*"),
       body    = jsonlite::toJSON(data, auto_unbox = TRUE))
}

.configure_chat_for_analytics <- function(chat, con, prefix = "") {
  sys <- paste0(
    "You are an expert assistant for an R targets data pipeline.\n\n",
    "Use the run_sql tool to query the database when the user asks about ",
    "pipeline structure, targets, functions, lineage, status, or dependencies.\n\n",
    "Tables: ", prefix, "targets, ", prefix, "functions, ", prefix, "edges",
    if (!is.null(con)) {
      tryCatch({
        n  <- DBI::dbGetQuery(con, paste0("SELECT COUNT(*) n FROM ", prefix, "targets"))$n
        ne <- DBI::dbGetQuery(con, paste0("SELECT COUNT(*) n FROM ", prefix, "targets WHERE status='errored'"))$n
        ns <- DBI::dbGetQuery(con, paste0("SELECT STRING_AGG(name,', ') n FROM ", prefix, "targets"))$n
        paste0("\nPipeline: ", n, " targets (", ne, " errored). Names: ", ns)
      }, error = function(e) "")
    } else ""
  )
  tryCatch(chat$.__enclos_env__$private$system_prompt <- sys, error = function(e) NULL)
}

.patch_sql_tool_logging <- function(chat, con, sql_log) {
  sql_fn <- function(query, explanation = "") {
    result <- tryCatch(DBI::dbGetQuery(con, query),
                       error = function(e) data.frame(error = conditionMessage(e)))
    sql_log$calls <- c(sql_log$calls, list(list(
      sql         = query,
      explanation = explanation,
      columns     = names(result),
      rows        = lapply(seq_len(min(nrow(result), 50L)),
                           function(i) as.list(result[i, , drop = FALSE]))
    )))
    result
  }
  sql_tool <- ellmer::tool(
    sql_fn,
    "Execute a SQL or dplyr query against the tardoc pipeline database.",
    query       = ellmer::type_string("The SQL query to execute"),
    explanation = ellmer::type_string("One sentence describing what this query finds",
                                       required = FALSE)
  )
  chat$register_tool(sql_tool)
}

.ad_pull_desc <- function(r) {
  if (!"description" %in% names(r)) return(NA_character_)
  v <- dplyr::pull(r, "description")
  if (length(v) == 0 || is.na(v) || nchar(trimws(v)) == 0) NA_character_ else v
}
.ad_find_src <- function(fn, r_files) {
  for (f in r_files) {
    e <- new.env(parent = globalenv())
    tryCatch(source(f, local = e), error = function(e) NULL)
    if (fn %in% ls(e)) return(f)
  }
  NULL
}
.ad_extract_desc <- function(docs) {
  lines <- strsplit(docs, "\n")[[1]]
  in_d  <- FALSE; dl <- character()
  for (l in lines) {
    if (grepl("^##\\s+Description", l, ignore.case = TRUE)) { in_d <- TRUE; next }
    if (in_d) { if (grepl("^##", l)) break; dl <- c(dl, l) }
  }
  trimws(paste(dl, collapse = "\n"))
}

`%||%` <- function(x, y) if (is.null(x)) y else x


#' Find a free TCP port starting from the given port
#' @keywords internal
.find_free_port <- function(start_port) {
  for (p in start_port:(start_port + 20)) {
    tryCatch({
      s <- serverSocket(p)
      close(s)
      return(p)
    }, error = function(e) NULL)
  }
  start_port  # fallback to original if nothing found
}
