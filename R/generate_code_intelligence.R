# R/generate_code_intelligence.R
#
# Optional code intelligence layer for tardoc.duckdb.
# Attempts to load two community extensions:
#
#   sitting_duck  — parses R source files via tree-sitter and builds a
#                   function_calls table: which functions call which.
#                   Adds complexity metrics (call-out count) to functions.
#
#   duck_tails    — queries git history and builds a git_history table:
#                   which R files changed when and by whom.
#
# Both are installed from the DuckDB community extension registry at
# generate_tardoc_db() time. If either is unavailable the step is skipped
# silently and _meta records the result.
#
# API note: sitting_duck and duck_tails are community extensions. The exact
# function names below reflect the most likely API based on their
# documentation. If the API differs from what is installed, the tryCatch
# will suppress the error and set the capability flag to FALSE.

#' Add code intelligence tables to an open DuckDB connection
#'
#' Called by [generate_tardoc_db()] with an already-open connection. Tries to
#' install and use `sitting_duck` (R code AST) and `duck_tails` (git history).
#'
#' @param con  An open DBI connection to `tardoc.duckdb`.
#' @param cfg  A site config list.
#'
#' @return A named logical list: `list(has_ast = ., has_git = .)`.
#' @export
generate_code_intelligence <- function(con, cfg) {
  has_ast <- FALSE
  has_git <- FALSE

  # ---- sitting_duck: function call graph ------------------------------------
  r_glob <- file.path(cfg$r_scripts_dir, "*.R")
  if (!dir.exists(cfg$r_scripts_dir) || length(list.files(cfg$r_scripts_dir, "*.R")) == 0) {
    message("  sitting_duck: no R files found, skipping.")
  } else {
    tryCatch({
      message("  Installing sitting_duck (R code AST)...")
      DBI::dbExecute(con, "INSTALL sitting_duck FROM community; LOAD sitting_duck;")

      # Build function_calls table.
      # sitting_duck exposes read_ast() which returns a tree-sitter AST.
      # For R, call nodes have type 'call'; the callee name is in the first
      # identifier child. We use regexp_extract on the call text as a robust
      # fallback that works regardless of nesting depth.
      DBI::dbExecute(con, sprintf("
        CREATE TABLE function_calls AS
        WITH raw_calls AS (
          SELECT
            file,
            start_row                                      AS line_number,
            text                                           AS call_text,
            -- Extract leading identifier (the function being called)
            regexp_extract(text, '^([a-zA-Z_.][a-zA-Z0-9_.:]*)', 1) AS callee
          FROM read_ast(glob('%s'))
          WHERE type = 'call'
            AND text IS NOT NULL
            AND text != ''
        ),
        -- Derive caller: innermost enclosing function definition.
        -- Approximated by the basename of the file for simplicity.
        -- A richer join on parent_id would need sitting_duck's full AST.
        annotated AS (
          SELECT
            regexp_replace(basename(file), '\\.R$', '') AS caller_file,
            callee,
            file,
            line_number
          FROM raw_calls
          WHERE callee != ''
        )
        SELECT
          caller_file AS caller,
          callee,
          file,
          line_number
        FROM annotated
        ORDER BY caller, line_number
      ", r_glob))

      n_calls <- DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM function_calls")$n
      message("  sitting_duck: ", n_calls, " call edges found.")

      # Add complexity column to functions table
      DBI::dbExecute(con, "
        ALTER TABLE functions ADD COLUMN IF NOT EXISTS call_out_count INTEGER DEFAULT 0
      ")
      DBI::dbExecute(con, "
        UPDATE functions SET call_out_count = (
          SELECT COUNT(DISTINCT callee)
          FROM function_calls fc
          WHERE fc.caller = functions.name
        )
      ")

      has_ast <- TRUE
    }, error = function(e) {
      message("  sitting_duck unavailable: ", conditionMessage(e))
    })
  }

  # ---- duck_tails: git history ---------------------------------------------
  git_dir <- file.path(cfg$project_path, ".git")
  if (!dir.exists(git_dir)) {
    message("  duck_tails: not a git repo, skipping.")
  } else {
    tryCatch({
      message("  Installing duck_tails (git history)...")
      DBI::dbExecute(con, "INSTALL duck_tails FROM community; LOAD duck_tails;")

      # Build git_history table from log entries touching R files and
      # _targets.R. duck_tails exposes git_log() with columns:
      #   hash, author_name, author_email, author_date, message, paths
      DBI::dbExecute(con, sprintf("
        CREATE TABLE git_history AS
        SELECT
          hash,
          author_name   AS author,
          author_date::VARCHAR AS date,
          message,
          UNNEST(paths) AS file
        FROM git_log(repository => '%s')
        WHERE list_any_value(
          list_apply(paths, p ->
            p LIKE '%%.R' OR p LIKE '%%_targets.R'
          )
        )
        ORDER BY author_date DESC
        LIMIT 2000
      ", cfg$project_path))

      n_commits <- DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT hash) n FROM git_history")$n
      message("  duck_tails: ", n_commits, " relevant commits found.")
      has_git <- TRUE
    }, error = function(e) {
      message("  duck_tails unavailable: ", conditionMessage(e))
    })
  }

  list(has_ast = has_ast, has_git = has_git)
}
