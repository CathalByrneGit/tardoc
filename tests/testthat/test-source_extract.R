# tests/testthat/test-source_extract.R
#
# Function pages showed deparse(fun_obj), which is R's reconstruction of the
# parsed object rather than the source. Comments are discarded at parse time,
# so every internal comment was lost -- often the part of a function that
# explains why it does what it does. Srcrefs give the file's own bytes back.

write_r <- function(lines, env = parent.frame()) {
  dir  <- withr::local_tempdir(.local_envir = env)
  path <- file.path(dir, "f.R")
  writeLines(lines, path)
  path
}

test_that("internal comments survive", {
  f <- write_r(c(
    "clean <- function(x) {",
    "  # why this is done at all",
    "  x + 1  # and a trailing note",
    "}"
  ))
  txt <- .file_functions(f)$clean$text
  expect_match(txt, "# why this is done at all", fixed = TRUE)
  expect_match(txt, "# and a trailing note", fixed = TRUE)
})

test_that("the author's formatting survives", {
  # deparse re-indents to four spaces, drops blank lines and re-wraps.
  f <- write_r(c(
    "spaced <- function(x) {",
    "  a <- 1",
    "",
    "      b <- 2",
    "  a + b + x",
    "}"
  ))
  txt <- .file_functions(f)$spaced$text
  expect_match(txt, "\n\n", fixed = TRUE)          # blank line kept
  expect_match(txt, "      b <- 2", fixed = TRUE)  # odd indent kept
})

test_that("the assignment itself is included, not just the function", {
  # deparse drops the name, so the page showed a headless `function (x)`.
  f <- write_r("named <- function(x) x")
  expect_match(.file_functions(f)$named$text, "^named <- function", perl = TRUE)
})

test_that("roxygen above the function is not swallowed into the source", {
  # It is rendered separately as documentation; repeating it in the source
  # block would duplicate half the page.
  f <- write_r(c(
    "#' Title here",
    "#' @param x thing",
    "documented <- function(x) x"
  ))
  txt <- .file_functions(f)$documented$text
  expect_false(grepl("@param", txt, fixed = TRUE))
  expect_match(txt, "^documented <-", perl = TRUE)
})

test_that("line numbers point at the definition", {
  f <- write_r(c("# a leading comment", "", "fn <- function() {", "  1", "}"))
  d <- .file_functions(f)$fn
  expect_equal(d$start, 3L)
  expect_equal(d$end, 5L)
})

test_that("all three assignment operators are recognised", {
  f <- write_r(c("a <- function() 1", "b = function() 2", "c <<- function() 3"))
  expect_setequal(names(.file_functions(f)), c("a", "b", "c"))
})

test_that("the lambda shorthand is recognised", {
  skip_if(getRversion() < "4.1.0")
  f <- write_r("short <- \\(x) x + 1")
  expect_equal(names(.file_functions(f)), "short")
})

test_that("indented definitions are found", {
  # The old regex anchored at column one and missed these entirely.
  f <- write_r(c("  indented <- function() 1"))
  expect_equal(names(.file_functions(f)), "indented")
})

test_that("values are not mistaken for functions", {
  f <- write_r(c("threshold <- 42", "lookup <- c(a = 1)", "fn <- function() 1"))
  expect_equal(names(.file_functions(f)), "fn")
})

test_that("top-level code is parsed, never run", {
  canary <- file.path(withr::local_tempdir(), "canary.txt")
  writeLines("still here", canary)
  f <- write_r(c(sprintf("file.remove(%s)", deparse(canary)),
                 "safe <- function() TRUE"))
  expect_equal(names(.file_functions(f)), "safe")
  expect_true(file.exists(canary))
})

test_that("a file needing an uninstalled package still yields its source", {
  # Sourcing this would fail and the page fell back to "# source unavailable".
  f <- write_r(c(
    "library(apackagethatdoesnotexist999)",
    "usable <- function(x) {",
    "  # the comment is still here",
    "  x",
    "}"
  ))
  d <- .file_functions(f)$usable
  expect_false(is.null(d))
  expect_match(d$text, "# the comment is still here", fixed = TRUE)
})

test_that("an unparseable file yields nothing rather than erroring", {
  f <- write_r("broken <- function( {")
  expect_equal(.file_functions(f), list())
  expect_equal(.file_defines(f), character())
})

test_that("a file with no functions yields nothing", {
  expect_equal(.file_functions(write_r("x <- 1")), list())
})

test_that(".file_defines is the same parse, names only", {
  f <- write_r(c("a <- function() 1", "b <- function() 2"))
  expect_equal(.file_defines(f), names(.file_functions(f)))
})

test_that("generated function pages carry the verbatim source", {
  dir <- withr::local_tempdir()
  cfg <- mock_cfg(dir); setup_site_dirs(cfg)
  dir.create(cfg$r_scripts_dir, showWarnings = FALSE, recursive = TRUE)
  writeLines(c(
    "#' A documented helper",
    "#' @param x input",
    "helper <- function(x) {",
    "  # this line explains the next one",
    "  x * 2",
    "}"
  ), file.path(cfg$r_scripts_dir, "helpers.R"))

  suppressMessages(generate_all_function_pages(cfg))
  md <- paste(readLines(file.path(cfg$functions_dir, "helper.md"), warn = FALSE),
              collapse = "\n")
  expect_match(md, "# this line explains the next one", fixed = TRUE)
  expect_match(md, "helper <- function(x)", fixed = TRUE)
  # The deparse fallback must be gone.
  expect_false(grepl("source unavailable", md, fixed = TRUE))
})
