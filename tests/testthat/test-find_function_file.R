# tests/testthat/test-find_function_file.R
#
# .find_function_file() used to source each R file into
# `new.env(parent = emptyenv())`. That environment has no base functions, so
# source() died on the first `<-` and the lookup never matched anything: every
# function in the search index had an empty `source_file` and, because the
# roxygen lookup was gated on the same result, an empty description too.
#
# It now parses instead, which also avoids running a user's top-level code
# just to find out where a function is defined.

write_r <- function(lines, dir = withr::local_tempdir(.local_envir = parent.frame())) {
  path <- file.path(dir, paste0("f", sample.int(1e6, 1), ".R"))
  writeLines(lines, path)
  path
}

test_that("a plain function definition is found", {
  f <- write_r(c("greet <- function(x) paste('hi', x)", "n <- 1"))
  expect_equal(tardoc:::.file_defines(f), "greet")
  expect_equal(tardoc:::.find_function_file("greet", f), f)
})

test_that("the lookup no longer fails on an ordinary assignment", {
  # The exact shape that broke: a file whose first statement is an assignment.
  f <- write_r(c("threshold <- 5", "flag <- function(x) x > threshold"))
  expect_true("flag" %in% tardoc:::.file_defines(f))
  expect_equal(tardoc:::.find_function_file("flag", f), f)
})

test_that("non-function assignments are not reported as functions", {
  f <- write_r(c("constant <- 42", "vec <- c(1, 2, 3)"))
  expect_equal(tardoc:::.file_defines(f), character())
})

test_that("= and <<- assignments count too", {
  f <- write_r(c("a = function() 1", "b <<- function() 2"))
  expect_setequal(tardoc:::.file_defines(f), c("a", "b"))
})

test_that("the backslash lambda shorthand is recognised", {
  skip_if(getRversion() < "4.1.0")
  f <- write_r("short <- \\(x) x + 1")
  expect_equal(tardoc:::.file_defines(f), "short")
})

test_that("top-level code is parsed, not executed", {
  # Sourcing this would delete a file; parsing must not.
  canary <- file.path(withr::local_tempdir(), "canary.txt")
  writeLines("still here", canary)
  f <- write_r(c(
    sprintf('file.remove(%s)', deparse(canary)),
    "safe <- function() TRUE"
  ))
  expect_equal(tardoc:::.file_defines(f), "safe")
  expect_true(file.exists(canary))
})

test_that("a file that will not parse is skipped rather than fatal", {
  f <- write_r("this is ( not valid R")
  expect_equal(tardoc:::.file_defines(f), character())
  expect_null(tardoc:::.find_function_file("anything", f))
})

test_that("the first file defining the name wins", {
  dir <- withr::local_tempdir()
  a <- file.path(dir, "a.R"); writeLines("shared <- function() 1", a)
  b <- file.path(dir, "b.R"); writeLines("shared <- function() 2", b)
  expect_equal(tardoc:::.find_function_file("shared", c(a, b)), a)
})

test_that("an unknown name returns NULL", {
  f <- write_r("known <- function() 1")
  expect_null(tardoc:::.find_function_file("unknown", f))
})
