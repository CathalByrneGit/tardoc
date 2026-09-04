# R/generate_code_intelligence.R
#
# Optional code intelligence layer for tardoc.duckdb.
# Loads two community extensions:
#
#   sitting_duck  - parses source files via tree-sitter and exposes the AST
#                   as rows. Used here to build a function_calls table:
#                   which function calls which, and where.
#
#   duck_tails    - exposes git history as table functions. Used here to
#                   build a git_history table of recent commits.
#
# Both are installed from the DuckDB community extension registry at
# generate_tardoc_db() time. If either is unavailable the step is skipped and
# the reason is returned to the caller, which records it in _meta so the
# viewer (and the user) can see why a capability is switched off.
#
# The SQL below targets the documented schemas:
#   read_ast(files, [language]) -> node_id, parent_id, type, semantic_type,
#     name, file_path, language, start_line, end_line, depth, peek, ...
#   git_log([path]) -> commit_hash, author_name, author_date, message, ...

#' Add code intelligence tables to an open DuckDB connection
#'
#' Called by [generate_tardoc_db()] with an already-open connection. Installs
#' and uses `sitting_duck` (source AST) and `duck_tails` (git history).
#'
#' @param con  An open DBI connection to `tardoc.duckdb`.
#' @param cfg  A site config list.
#'
#' @return A named list with logical `has_ast` / `has_git` and character
#'   `ast_error` / `git_error` holding the reason a layer was skipped
#'   (`NA_character_` when the layer succeeded).
#' @export
generate_code_intelligence <- function(con, cfg) {
  has_ast <- FALSE
  has_git <- FALSE
  ast_error <- NA_character_
  git_error <- NA_character_

  # ---- sitting_duck: function call graph ------------------------------------
  r_files <- if (dir.exists(cfg$r_scripts_dir)) {
    list.files(cfg$r_scripts_dir, pattern = "\\.[Rr]$")
  } else {
    character(0)
  }

  if (length(r_files) == 0) {
    ast_error <- "no R files found"
    message("  sitting_duck: no R files found, skipping.")
  } else {
    r_glob <- file.path(cfg$r_scripts_dir, "*.R")
    tryCatch({
      message("  Installing sitting_duck (R code AST)...")
      DBI::dbExecute(con, "INSTALL sitting_duck FROM community; LOAD sitting_duck;")

      # Attribute each call to its innermost enclosing function definition by
      # line containment: among all definitions in the same file whose
      # [start_line, end_line] span covers the call, take the narrowest.
      # Calls outside any definition are attributed to '<top-level>'.
      DBI::dbExecute(con, sprintf("
        CREATE TABLE function_calls AS
        WITH ast AS (
          SELECT type, semantic_type, name, file_path, start_line, end_line, peek
          FROM read_ast(%s, 'r')
        ),
        defs AS (
          SELECT file_path, name AS caller, start_line, end_line
          FROM ast
          WHERE is_function_definition(semantic_type)
            AND name IS NOT NULL AND name <> ''
        ),
        calls AS (
          SELECT
            file_path,
            start_line,
            COALESCE(
              NULLIF(name, ''),
              regexp_extract(peek, '^([a-zA-Z._][a-zA-Z0-9._]*(::[a-zA-Z0-9._]+)?)', 1)
            ) AS callee
          FROM ast
          WHERE type = 'call'
        ),
        matched AS (
          SELECT
            c.file_path,
            c.start_line,
            c.callee,
            d.caller,
            ROW_NUMBER() OVER (
              PARTITION BY c.file_path, c.start_line, c.callee
              ORDER BY (d.end_line - d.start_line) ASC NULLS LAST
            ) AS rn
          FROM calls c
          LEFT JOIN defs d
            ON  d.file_path = c.file_path
            AND c.start_line BETWEEN d.start_line AND d.end_line
        )
        SELECT
          COALESCE(caller, '<top-level>') AS caller,
          callee,
          file_path                       AS file,
          start_line                      AS line_number
        FROM matched
        WHERE rn = 1
          AND callee IS NOT NULL
          AND callee <> ''
        ORDER BY caller, line_number
      ", DBI::dbQuoteString(con, r_glob)))

      n_calls <- DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM function_calls")$n
      message("  sitting_duck: ", n_calls, " call edges found.")

      # Complexity metric: distinct callees per documented function.
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
      ast_error <<- conditionMessage(e)
      message("  sitting_duck unavailable: ", conditionMessage(e))
    })
  }

  # ---- duck_tails: git history ---------------------------------------------
  git_dir <- file.path(cfg$project_path, ".git")
  if (!dir.exists(git_dir)) {
    git_error <- "not a git repository"
    message("  duck_tails: not a git repo, skipping.")
  } else {
    tryCatch({
      message("  Installing duck_tails (git history)...")
      DBI::dbExecute(con, "INSTALL duck_tails FROM community; LOAD duck_tails;")

      # git_log() takes the repository path positionally and yields one row
      # per commit. Per-file attribution is deliberately not attempted here:
      # duck_tails exposes it through separate table functions whose schema
      # is not documented, so tying it in would be guesswork.
      DBI::dbExecute(con, sprintf("
        CREATE TABLE git_history AS
        SELECT
          commit_hash,
          author_name          AS author,
          author_date::VARCHAR AS date,
          message
        FROM git_log(%s)
        ORDER BY author_date DESC
        LIMIT 2000
      ", DBI::dbQuoteString(con, cfg$project_path)))

      n_commits <- DBI::dbGetQuery(
        con, "SELECT COUNT(DISTINCT commit_hash) n FROM git_history")$n
      message("  duck_tails: ", n_commits, " commits recorded.")
      has_git <- TRUE
    }, error = function(e) {
      git_error <<- conditionMessage(e)
      message("  duck_tails unavailable: ", conditionMessage(e))
    })
  }

  list(
    has_ast   = has_ast,
    has_git   = has_git,
    ast_error = ast_error,
    git_error = git_error
  )
}
