# tests/testthat/test-generate_code_intelligence.R
#
# The sitting_duck / duck_tails SQL needs those community extensions, which
# are not assumed available in CI. These tests cover the skip paths and the
# contract generate_tardoc_db() depends on: a four-field list whose error
# fields explain any FALSE flag.

test_that("returns the documented shape", {
  skip_if_not_installed("duckdb")
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp)
  con <- duckdb::dbConnect(duckdb::duckdb())
  withr::defer(duckdb::dbDisconnect(con, shutdown = TRUE))

  res <- suppressMessages(generate_code_intelligence(con, cfg))
  expect_named(res, c("has_ast", "has_git", "ast_error", "git_error"))
  expect_type(res$has_ast, "logical")
  expect_type(res$has_git, "logical")
})

test_that("missing R directory is reported, not silently ignored", {
  skip_if_not_installed("duckdb")
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp)  # no R/ created
  con <- duckdb::dbConnect(duckdb::duckdb())
  withr::defer(duckdb::dbDisconnect(con, shutdown = TRUE))

  res <- suppressMessages(generate_code_intelligence(con, cfg))
  expect_false(res$has_ast)
  expect_match(res$ast_error, "no R files")
})

test_that("an R directory containing no R files is treated as empty", {
  skip_if_not_installed("duckdb")
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp)
  dir.create(cfg$r_scripts_dir, recursive = TRUE)
  writeLines("not r code", file.path(cfg$r_scripts_dir, "notes.txt"))
  con <- duckdb::dbConnect(duckdb::duckdb())
  withr::defer(duckdb::dbDisconnect(con, shutdown = TRUE))

  res <- suppressMessages(generate_code_intelligence(con, cfg))
  expect_false(res$has_ast)
  expect_match(res$ast_error, "no R files")
})

test_that("lower-case .r files are counted as R source", {
  skip_if_not_installed("duckdb")
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp)
  dir.create(cfg$r_scripts_dir, recursive = TRUE)
  writeLines("f <- function() 1", file.path(cfg$r_scripts_dir, "lower.r"))
  con <- duckdb::dbConnect(duckdb::duckdb())
  withr::defer(duckdb::dbDisconnect(con, shutdown = TRUE))

  res <- suppressMessages(generate_code_intelligence(con, cfg))
  # Either the extension loaded and ran, or it failed to install — but the
  # reason must never be the "no R files" short-circuit.
  expect_false(identical(res$ast_error, "no R files found"))
})

test_that("a non-git project is reported, not silently ignored", {
  skip_if_not_installed("duckdb")
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp)  # no .git
  con <- duckdb::dbConnect(duckdb::duckdb())
  withr::defer(duckdb::dbDisconnect(con, shutdown = TRUE))

  res <- suppressMessages(generate_code_intelligence(con, cfg))
  expect_false(res$has_git)
  expect_match(res$git_error, "not a git")
})
