# tests/testthat/test-generate_tardoc_db.R
#
# Core-tier tests only: db_extensions = FALSE. The community extensions
# (quackformers, faiss, duckdb_mcp) are downloaded
# from the DuckDB registry at build time and are not exercised here.

skip_if_no_duckdb <- function() {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
}

local_db <- function(env = parent.frame(), ...) {
  tmp <- withr::local_tempdir(.local_envir = env)
  cfg <- mock_cfg(tmp)
  setup_site_dirs(cfg)
  path <- generate_tardoc_db(mock_targets_data(), character(), cfg, ...)
  list(path = path, cfg = cfg, tmp = tmp)
}

with_con <- function(path, f) {
  con <- duckdb::dbConnect(duckdb::duckdb(), path, read_only = TRUE)
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  f(con)
}

test_that("generate_tardoc_db returns NULL when duckdb is unavailable", {
  skip_if_no_duckdb()
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  local_mocked_bindings(
    requireNamespace = function(package, ...) if (package == "duckdb") FALSE else TRUE,
    .package = "base"
  )
  expect_message(
    res <- generate_tardoc_db(mock_targets_data(), character(), cfg),
    "duckdb"
  )
  expect_null(res)
})

test_that("generate_tardoc_db creates the database file", {
  skip_if_no_duckdb()
  db <- local_db()
  expect_true(file.exists(db$path))
  expect_equal(basename(db$path), "tardoc.duckdb")
})

test_that("core tables are created", {
  skip_if_no_duckdb()
  db <- local_db()
  tbls <- with_con(db$path, DBI::dbListTables)
  expect_true(all(c("targets", "functions", "edges") %in% tbls))
})

test_that("targets table holds one row per target", {
  skip_if_no_duckdb()
  td <- mock_targets_data()
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  path <- generate_tardoc_db(td, character(), cfg)
  got <- with_con(path, function(con)
    DBI::dbGetQuery(con, "SELECT name FROM targets ORDER BY name"))
  expect_setequal(got$name, td$target_names)
})

test_that("_meta exposes the wide capability flags view_tardoc_db reads", {
  skip_if_no_duckdb()
  db <- local_db()
  meta <- with_con(db$path, function(con)
    DBI::dbGetQuery(con, "SELECT * FROM _meta LIMIT 1"))
  expect_equal(nrow(meta), 1L)
  expect_true(all(c("has_fts", "has_embeddings", "has_faiss",
                    "has_mcp") %in% names(meta)))
  expect_type(meta$has_faiss[1], "logical")
})

test_that("community-extension capabilities are off when db_extensions = FALSE", {
  skip_if_no_duckdb()
  db <- local_db()
  meta <- with_con(db$path, function(con)
    DBI::dbGetQuery(con, "SELECT * FROM _meta LIMIT 1"))
  expect_false(meta$has_embeddings[1])
  expect_false(meta$has_faiss[1])
  expect_false(meta$has_mcp[1])
})

test_that("_meta_detail records why each layer was skipped", {
  skip_if_no_duckdb()
  db <- local_db()
  detail <- with_con(db$path, function(con)
    DBI::dbGetQuery(con, "SELECT * FROM _meta_detail ORDER BY capability"))
  expect_setequal(detail$capability,
                  c("embeddings", "faiss", "fts", "mcp"))
  # Every unavailable capability carries a non-empty reason.
  off <- detail[!detail$available, ]
  expect_true(nrow(off) > 0)
  expect_false(any(is.na(off$reason)))
})

test_that("no FAISS sidecar is written without extensions", {
  skip_if_no_duckdb()
  db <- local_db()
  expect_length(list.files(db$cfg$site_path, pattern = "\\.faiss$"), 0)
})

test_that("regenerating replaces rather than appends", {
  skip_if_no_duckdb()
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  td  <- mock_targets_data()
  generate_tardoc_db(td, character(), cfg)
  path <- generate_tardoc_db(td, character(), cfg)
  n <- with_con(path, function(con)
    DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM targets")$n)
  expect_equal(n, length(td$target_names))
})

test_that(".faiss_index_path lands beside the database", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp)
  p <- .faiss_index_path(cfg, "target_semantic")
  expect_equal(dirname(p), cfg$site_path)
  expect_equal(basename(p), "target_semantic.faiss")
})

test_that("a pipeline with no documented functions still builds", {
  skip_if_no_duckdb()
  # do.call(rbind, list()) is NULL, which dbWriteTable rejects; the functions
  # table must exist and be empty rather than blowing up the whole build.
  db <- local_db()
  fns <- with_con(db$path, function(con)
    DBI::dbGetQuery(con, "SELECT * FROM functions"))
  expect_equal(nrow(fns), 0L)
  expect_true(all(c("name", "description", "source_file", "notes") %in% names(fns)))
})

test_that("a pipeline with no targets still builds", {
  skip_if_no_duckdb()
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  td <- mock_targets_data()
  td$target_names <- character()
  path <- generate_tardoc_db(td, character(), cfg)
  n <- with_con(path, function(con)
    DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM targets")$n)
  expect_equal(n, 0)
})
