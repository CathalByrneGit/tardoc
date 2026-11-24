# R/document_targets.R

#' Document a targets project
#'
#' Generates all tardoc output: markdown pages, Tier 1 viewer, Tier 2 WASM
#' analytics viewer, Tier 3/4 server analytics database, and `llms.txt`.
#'
#' **Tiers produced:**
#' - Tier 1: `viewer.html` -- opens as `file://`, no server
#' - Tier 2: `wasm_analytics.html` -- DuckDB WASM, opens as `file://`, data embedded
#' - Tier 3/4: `tardoc.duckdb` -- for `view_tardoc_db()` with Quack + LLM chat
#'
#' @param project_path  Path to the targets project root. Default `"."`.
#' @param site_dir      Subfolder for all generated content. Default `"tardoc"`.
#' @param pkg_name      Title shown in viewer headers.
#' @param pkg_desc      One-paragraph project description (used in `llms.txt`).
#' @param repo_url      Optional base URL of the hosted repo for source links.
#' @param code_dirs     Where the function code lives, when it is not in
#'   `R/`: directories (searched recursively) and/or files. `NULL` reads them
#'   from the `tar_source()` calls in `_targets.R`. See [build_site_config()].
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
#' @param reports       Publish what file targets produced -- the rendered
#'   report of a `tarchetypes::tar_render()` or `tar_quarto()` target, or any
#'   `format = "file"` target that writes an `.html` or `.pdf`. `FALSE` (the
#'   default), `TRUE` for every such target, or a character vector of target
#'   names. Outputs are copied to `tardoc/reports/<target>/` with their
#'   supporting folders, and the target's page and the viewer get an
#'   **Open report** link -- only for a target that has built without error;
#'   an out-of-date one is marked as such. Off by default because a report can
#'   hold data you would not want on a public site, and the docs folder is what
#'   gets deployed. With no store nothing is published.
#' @param llm_refresh   Logical. With `llm = TRUE`, regenerate every description
#'   and explanation instead of keeping what an earlier run produced. By default
#'   a target already described on its page is left alone and a function is
#'   explained again only when its source or docs change (cached in
#'   `llm_cache.json`).
#' @param group_by How the pipeline overview may be collapsed into groups:
#'   `"auto"` picks a grouping signal and rejects the lot when none scores
#'   well, `"none"` disables it, or name one of `"declaration"`, `"functions"`,
#'   `"prefix"`, `"depth"` to force it. See [target_groups()]. Grouping only
#'   adds an option in the viewer -- the flat graph stays the default view.
#' @param check_outdated Logical. Call [targets::tar_outdated()] so pages and
#'   the graph can tell a stale target from a current one. It re-hashes
#'   dependencies, so pass `FALSE` on a large pipeline to skip it; status then
#'   falls back to reporting errors only.
#'
#' @return The `cfg` list, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' # Minimal -- Tier 1 + 2 always, Tier 3 if duckdb installed
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
                              llm_base_url  = NULL,
                              llm_refresh   = FALSE,
                              reports       = FALSE,
                              check_outdated = TRUE,
                              group_by      = "auto",
                              code_dirs     = NULL) {

  cfg <- build_site_config(project_path, site_dir, repo_url, code_dirs)
  setup_site_dirs(cfg)

  targets_data   <- load_targets_data(cfg, check_outdated = check_outdated)
  # Before the pages: each target's page links to what it published.
  targets_data   <- .publish_reports(targets_data, cfg, reports)
  target_names   <- generate_all_target_pages(targets_data, cfg)
  function_names <- generate_all_function_pages(cfg)

  generate_notes(target_names, function_names, cfg)

  # Optional: LLM-generated descriptions and explanations. Before anything that
  # reads descriptions: it used to run after the search index and llms.txt were
  # written, so the targets it had just described were "undescribed" in both.
  if (isTRUE(llm)) {
    generate_llm_content(
      targets_data   = targets_data,
      function_names = function_names,
      cfg            = cfg,
      llm_chat       = llm_chat,
      provider       = llm_provider,
      model          = llm_model,
      api_key        = llm_api_key,
      base_url       = llm_base_url,
      refresh        = llm_refresh
    )
  } else {
    # The pages were just rewritten; bring back what an earlier run explained.
    .restore_cached_explanations(function_names, cfg)
  }

  # Descriptions already on the pages (written by an earlier llm = TRUE run, or
  # by this one) become part of the data every output below is built from.
  targets_data <- .merge_page_descriptions(targets_data, cfg)

  # Before the viewer, so this run's figures are in the history the viewer
  # embeds -- the diff shown is then between this build and the one before.
  record_run_snapshot(targets_data, cfg)

  generate_search_index(targets_data, function_names, cfg)
  generate_llms_txt(targets_data, cfg,
                     project_title = pkg_name, project_desc = pkg_desc)

  # Tier 1: self-contained viewer
  generate_viewer(targets_data, function_names, cfg, pkg_name,
                  group_by = group_by)

  # Generate analytics data (used by both WASM and server analytics)
  analytics_data <- .build_analytics_data(targets_data, function_names, cfg)

  # Write the JSON file (used by server analytics fallback)
  .write_lines_utf8(
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
#' dplyr queries, BM25 search, and lineage -- no R process required after
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
#' @param code_dirs    Where the function code lives; see
#'   [document_targets()]. `NULL` reads it from `_targets.R`.
#' @param host         Address the HTML server listens on. Default
#'   `"127.0.0.1"`: only this machine. The server answers chat requests with
#'   your LLM credentials and reads files from the docs folder, so
#'   `"0.0.0.0"` (every interface) is for a trusted network and a deliberate
#'   choice.
#' @param db_extensions Logical. Install community DuckDB extensions when
#'   building `tardoc.duckdb`: `quackformers` (BERT semantic search), `faiss`,
#'   `duckdb_mcp`. Slow on first run. Default
#'   `FALSE`.
#' @param llm_chat     An ellmer `Chat` object for the chat interface.
#'   Any provider: `ellmer::chat_openai()`, `ellmer::chat_ollama("llama3.2")`,
#'   `ellmer::chat_anthropic()`, `ellmer::chat_openai_compatible(base_url)`.
#'   `NULL` (default) disables chat.
#' @export
view_tardoc_db <- function(project_path = ".", site_dir = "tardoc",
                            port = 9000, quack_port = 9494,
                            llm_chat = NULL,
                            db_extensions = FALSE,
                            code_dirs = NULL,
                            host = "127.0.0.1") {
  for (pkg in c("httpuv", "duckdb", "callr", "DBI")) {
    if (!requireNamespace(pkg, quietly = TRUE))
      stop(sprintf("'%s' is required: install.packages('%s')", pkg, pkg))
  }

  site_path <- file.path(normalizePath(project_path), site_dir)
  db_path   <- file.path(site_path, "tardoc.duckdb")
  cfg       <- build_site_config(project_path, site_dir, code_dirs = code_dirs)

  # Generate tardoc.duckdb if it doesn't exist yet, or regenerate with
  # extensions if db_extensions = TRUE and was previously built without them
  # Also when the docs were regenerated after the database was built: it was
  # otherwise served stale, quietly, until deleted by hand. A rebuild keeps the
  # extension layers the old database had, so refreshing never silently
  # downgrades it.
  stale <- .db_is_stale(site_path, db_path)
  if (stale && !isTRUE(db_extensions) && .db_had_extensions(db_path)) {
    db_extensions <- TRUE
  }
  if (stale) message("tardoc.duckdb is older than the current docs -- rebuilding.")
  if (!file.exists(db_path) || isTRUE(db_extensions) || stale) {
    if (!requireNamespace("duckdb", quietly = TRUE)) {
      message("'duckdb' not installed -- skipping database generation. ",
              "Install with: install.packages('duckdb')")
    } else {
      td <- load_targets_data(cfg)
      fn <- generate_all_function_pages(cfg)
      generate_tardoc_db(td, fn, cfg, db_extensions = db_extensions)
      # Regenerate analytics JSON so sidebar stays in sync with new functions
      analytics_data <- .build_analytics_data(td, fn, cfg)
      .write_lines_utf8(
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

  # A FAISS index is saved beside the database, not inside it. If the sidecars
  # are missing (database built by an older tardoc, or files moved) semantic
  # search cannot work, so drop the claim rather than serve a broken button.
  faiss_paths <- character(0)
  if (has_faiss) {
    faiss_paths <- vapply(names(.faiss_indexes),
                          function(i) .faiss_index_path(cfg, i), character(1))
    faiss_paths <- faiss_paths[file.exists(faiss_paths)]
    if (length(faiss_paths) < length(.faiss_indexes)) {
      message("FAISS index files missing -- semantic search disabled.")
      has_faiss   <- FALSE
      faiss_paths <- character(0)
    }
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

  # Pick the ports first: they used to be chosen after the Quack server was
  # started on the requested one, so the page was told a port the server was
  # not on whenever the first was busy, and two services could pick the same.
  port       <- .find_free_port(port)
  quack_port <- .find_free_port(quack_port, avoid = port)

  # Start Quack server in background
  token      <- .session_token()
  quack_proc <- NULL
  if (file.exists(db_path)) {
    message("Starting Quack server on port ", quack_port, "...")
    quack_proc <- tryCatch(
      callr::r_bg(
        func = function(db_path, token, quack_port, faiss_paths) {
          con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
          # The semantic-search query calls embed() and FAISS_SEARCH, so this
          # serving connection needs both extensions loaded and the saved
          # index restored -- neither carries over from the build connection.
          if (length(faiss_paths)) {
            try({
              DBI::dbExecute(con, "LOAD quackformers;")
              DBI::dbExecute(con, "LOAD faiss;")
              for (idx in names(faiss_paths)) {
                DBI::dbExecute(con, sprintf("CALL FAISS_LOAD('%s', '%s')",
                                            idx, faiss_paths[[idx]]))
              }
            }, silent = TRUE)
          }
          # quack is a core extension as of DuckDB 1.5.3; the nightly
          # repository no longer serves it (HTTP 403 for every platform).
          tryCatch(
            DBI::dbExecute(con, "LOAD quack;"),
            error = function(e) DBI::dbExecute(con, "INSTALL quack; LOAD quack;")
          )
          DBI::dbExecute(con, sprintf(
            "CALL quack_serve('quack:localhost:%d', token = '%s');",
            quack_port, token
          ))
          # quack_serve() returns as soon as the listener is bound -- the
          # server runs on a thread inside this DuckDB instance. Without this
          # park the function would return, callr would exit the process, and
          # the server would die about a second after starting. supervise =
          # TRUE ends the process with the parent R session.
          repeat Sys.sleep(86400)
        },
        args = list(db_path, token, quack_port, faiss_paths),
        supervise = TRUE
      ),
      error = function(e) {
        message("Quack unavailable (", conditionMessage(e), ") -- JSON fallback.")
        NULL
      }
    )
    quack_proc <- .await_quack(quack_proc, quack_port)
  }

  session_path <- inject_quack_session(
    cfg, token, quack_port,
    has_faiss   = has_faiss,
    llm_enabled = !is.null(llm_chat)
  )

  app <- .analytics_app(site_path, session_path, port, llm_chat, sql_log)

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
  httpuv::runServer(host, port, app)
  invisible(NULL)
}

#' The request handler behind [view_tardoc_db()]
#'
#' Separate from the server so what it will and will not answer can be tested
#' by calling it with a made-up request, with no network involved.
#'
#' @param site_path The docs folder; the only place files are served from.
#' @param session_path The generated session page served at `/`.
#' @param port The port the server listens on, which fixes the origins it trusts.
#' @param llm_chat An ellmer `Chat`, or `NULL`.
#' @param sql_log Environment collecting the SQL the chat ran.
#' @return A list with a `call` function, as [httpuv::runServer()] expects.
#' @keywords internal
.analytics_app <- function(site_path, session_path, port, llm_chat, sql_log) {
  # Answers only to pages this server itself served. "*" let any website the
  # user visited POST to /chat on localhost and spend their LLM credentials.
  allow_origin <- function(req) {
    o <- req$HTTP_ORIGIN
    if (!is.null(o) && .origin_allowed(o, port)) o else NULL
  }
  with_cors <- function(headers, req) {
    o <- allow_origin(req)
    if (!is.null(o)) headers[["Access-Control-Allow-Origin"]] <- o
    headers
  }

  serve_file <- function(fp, req) {
    mime <- switch(tools::file_ext(fp),
      html = "text/html", json = "application/json",
      js = "application/javascript", "application/octet-stream")
    list(status  = 200L,
         headers = with_cors(list("Content-Type" = mime), req),
         body    = readBin(fp, "raw", file.info(fp)$size))
  }

  app <- list(call = function(req) {
    p <- req$PATH_INFO

    if (req$REQUEST_METHOD == "OPTIONS")
      return(list(status = 204L,
                  headers = with_cors(
                    list("Access-Control-Allow-Methods" = "POST, GET, OPTIONS",
                         "Access-Control-Allow-Headers" = "Content-Type"), req),
                  body = ""))

    if (p == "/chat" && req$REQUEST_METHOD == "POST") {
      # A request from another origin never reaches the model. Requests with no
      # Origin header (curl, same-origin GET-style fetches) are not browsers
      # acting for a stranger's page.
      if (!is.null(req$HTTP_ORIGIN) && !.origin_allowed(req$HTTP_ORIGIN, port))
        return(list(status = 403L, headers = list("Content-Type" = "text/plain"),
                    body = "Forbidden origin."))
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
            else .safe_site_file(site_path, p)
      if (!is.null(fp) && file.exists(fp) && !dir.exists(fp)) serve_file(fp, req) else
        list(status = 404L, headers = list("Content-Type" = "text/plain"),
             body = "Not found")
    }
  })

  app
}

#' Expose the tardoc database as an MCP server for Claude Desktop / Claude Code
#'
#' Starts the DuckDB `duckdb_mcp` extension server, making `tardoc.duckdb`
#' queryable by any MCP-compatible LLM client. Also writes
#' `tardoc/tardoc_mcp_config.json` -- add its contents to your Claude Desktop
#' configuration to make the pipeline database available as a persistent tool.
#'
#' @param project_path Path to the targets project root.
#' @param site_dir     Subfolder used in [document_targets()].
#' @param port         MCP server port. Default `8765`.
#' @param host         Address to listen on. Default `"127.0.0.1"`: only this
#'   machine. The database it exposes holds your pipeline's code and notes.
#' @export
serve_tardoc_mcp <- function(project_path = ".", site_dir = "tardoc", port = 8765,
                             host = "127.0.0.1") {
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
    cat(.read_text_utf8(cfg_path), "\n\n")
  }

  message("Starting MCP server on port ", port, "...")
  message("Once running, Claude Desktop and Claude Code can query your pipeline database.")
  message("Press Ctrl+C to stop.\n")

  proc <- tryCatch(
    callr::r_bg(
      func = function(db_path, port, host) {
        con <- duckdb::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
        DBI::dbExecute(con, "INSTALL duckdb_mcp FROM community; LOAD duckdb_mcp;")
        DBI::dbExecute(con, sprintf("CALL mcp_serve('%s', %d);", host, port))
      },
      args = list(db_path, port, host),
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
    dep <- get_target_network_dependencies(
      tn, targets_data$network, max_depth_up = 1, max_depth_down = 1
    )
    b <- .target_basics(tn, targets_data)
    list(
      name = tn, description = b$description,
      command = b$command, status = b$status,
      last_built = b$last_built,
      n_upstream = length(dep$upstream), n_downstream = length(dep$downstream),
      notes = read_note(tn, "targets", cfg),
      upstream = as.list(dep$upstream), downstream = as.list(dep$downstream)
    )
  })

  r_files <- .function_r_files(cfg)
  func_rows <- lapply(function_names, function(fn) {
    src  <- .find_function_file(fn, r_files)
    docs <- if (!is.null(src)) suppressWarnings(get_fn_docs(fn, src)) else NULL
    list(name = fn, description = if (!is.null(docs)) .docs_description(docs) else "",
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
       headers = list("Content-Type" = "application/json"),
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
  # ellmer's documented setter. The private field this used to write is not
  # part of its API and an ellmer update could drop it without an error; that
  # remains only as a fallback for versions that predate the setter.
  ok <- tryCatch({
    if (is.function(chat$set_system_prompt)) {
      chat$set_system_prompt(sys); TRUE
    } else {
      chat$.__enclos_env__$private$system_prompt <- sys; TRUE
    }
  }, error = function(e) FALSE)
  if (!ok) message("Could not set the chat's system prompt -- it will not know the ",
                   "table names up front, but can still query the database.")
  invisible(ok)
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


`%||%` <- function(x, y) if (is.null(x)) y else x


#' Wait for the background Quack server to accept connections
#'
#' Polls the port rather than sleeping a fixed interval and checking
#' `is_alive()`. That check was a race: `quack_serve()` returns immediately and
#' the process used to exit right behind it, so liveness at an arbitrary moment
#' said nothing about whether the browser would be able to attach. A successful
#' TCP connect does.
#'
#' @param proc A `callr` process, or `NULL`.
#' @param port Integer. The Quack port.
#' @param timeout Numeric. Seconds to wait before giving up.
#'
#' @return `proc` when the port is accepting connections, otherwise `NULL`
#'   after reporting why -- the caller then falls back to JSON.
#' @keywords internal
.await_quack <- function(proc, port, timeout = 15) {
  if (is.null(proc)) return(NULL)
  deadline <- Sys.time() + timeout
  repeat {
    if (!proc$is_alive()) {
      # The last non-empty stderr line is the R error that stopped it -- the
      # reason was previously discarded, leaving an unexplained fallback.
      err   <- tryCatch(proc$read_all_error(), error = function(e) "")
      lines <- trimws(strsplit(err, "\n", fixed = TRUE)[[1]])
      lines <- lines[nzchar(lines)]
      why   <- if (length(lines)) paste0(" (", lines[length(lines)], ")") else ""
      message("Quack exited early", why, " -- JSON fallback.")
      return(NULL)
    }
    ok <- tryCatch({
      con <- suppressWarnings(
        socketConnection("localhost", port, blocking = TRUE, timeout = 1)
      )
      close(con)
      TRUE
    }, error = function(e) FALSE)
    if (ok) return(proc)
    if (Sys.time() > deadline) {
      message("Quack did not accept connections within ", timeout,
              "s -- JSON fallback.")
      proc$kill()
      return(NULL)
    }
    Sys.sleep(0.25)
  }
}

#' Find a free TCP port starting from the given port
#' @keywords internal
.find_free_port <- function(start_port, avoid = integer()) {
  for (p in setdiff(start_port:(start_port + 20), avoid)) {
    tryCatch({
      s <- serverSocket(p)
      close(s)
      return(p)
    }, error = function(e) NULL)
  }
  start_port  # fallback to original if nothing found
}

#' A random session token
#'
#' From the operating system's entropy source where there is one. The token
#' used to come from `sample()`, which a user's earlier `set.seed()` makes the
#' same every session.
#'
#' @return A 32-character hex string.
#' @keywords internal
.session_token <- function() {
  bytes <- tryCatch(
    if (file.exists("/dev/urandom")) {
      con <- file("/dev/urandom", "rb"); on.exit(close(con))
      readBin(con, "raw", 16L)
    },
    error = function(e) NULL
  )
  if (length(bytes) != 16L) {
    bytes <- as.raw(floor(stats::runif(16L, 0, 256)))
  }
  paste(as.character(bytes), collapse = "")
}

#' Is a browser's Origin one of this server's own?
#'
#' @param origin The request's `Origin` header.
#' @param port The port the HTML server listens on.
#' @return `TRUE` for `http://localhost:<port>` and `http://127.0.0.1:<port>`.
#' @keywords internal
.origin_allowed <- function(origin, port) {
  origin %in% sprintf("http://%s:%d", c("localhost", "127.0.0.1"), as.integer(port))
}

#' Resolve a request path to a file inside the docs folder, or nothing
#'
#' The handler used to join the path onto the folder as given, so
#' `/../../.ssh/id_rsa` -- or its percent-encoded form -- named files outside it.
#' The path is decoded, resolved, and must still sit inside `site_path`.
#'
#' @param site_path The docs folder.
#' @param path The request's `PATH_INFO`.
#' @return A file path inside `site_path`, or `NULL`.
#' @keywords internal
.safe_site_file <- function(site_path, path) {
  rel <- tryCatch(utils::URLdecode(sub("^/+", "", path)), error = function(e) "")
  if (!nzchar(rel) || any(strsplit(rel, "[/\\\\]")[[1]] == "..")) return(NULL)
  root <- normalizePath(site_path, winslash = "/", mustWork = FALSE)
  fp   <- normalizePath(file.path(root, rel), winslash = "/", mustWork = FALSE)
  if (identical(fp, root) || !startsWith(fp, paste0(root, "/"))) return(NULL)
  fp
}

#' Is the analytics database older than the docs it describes?
#'
#' `search_index.json` is rewritten by every `document_targets()` run and by
#' nothing else, so a database built before it is out of date.
#'
#' @param site_path The docs folder.
#' @param db_path The database file.
#' @return `TRUE` when the database exists and is older than the index.
#' @keywords internal
.db_is_stale <- function(site_path, db_path) {
  idx <- file.path(site_path, "search_index.json")
  file.exists(db_path) && file.exists(idx) &&
    file.mtime(db_path) < file.mtime(idx)
}

#' Did the existing database have any community-extension layer?
#'
#' @param db_path The database file.
#' @return `TRUE` if its `_meta` records embeddings, FAISS or MCP.
#' @keywords internal
.db_had_extensions <- function(db_path) {
  if (!file.exists(db_path) || !requireNamespace("duckdb", quietly = TRUE)) return(FALSE)
  tryCatch({
    con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
    m <- DBI::dbGetQuery(con, "SELECT * FROM _meta LIMIT 1")
    any(isTRUE(m$has_embeddings[1]), isTRUE(m$has_faiss[1]), isTRUE(m$has_mcp[1]))
  }, error = function(e) FALSE)
}
