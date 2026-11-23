# tests/testthat/test-code_dirs.R
#
# Functions are not always in R/. tar_source("code") and tar_source("a", "b")
# are ordinary, and so is a single file; tardoc used to look only in R/.

proj <- function(targets_lines, files) {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  for (f in names(files)) {
    dir.create(dirname(file.path(d, f)), showWarnings = FALSE, recursive = TRUE)
    writeLines(files[[f]], file.path(d, f))
  }
  writeLines(targets_lines, file.path(d, "_targets.R"))
  d
}
fn <- function(name) c(sprintf("#' %s", name), sprintf("%s <- function(x) x", name))
rel <- function(cfg) sub(paste0("^", cfg$project_path, "/"), "", .function_r_files(cfg))

test_that("with no tar_source(), the default is R/", {
  d <- proj("list()", list("R/a.R" = fn("a")))
  expect_identical(rel(build_site_config(d)), "R/a.R")
})

test_that("tar_source(\"code\") is picked up without being told", {
  d <- proj(c("library(targets)", 'tar_source("code")', "list()"),
            list("code/a.R" = fn("a"), "R/ignored.R" = fn("zz")))
  expect_identical(rel(build_site_config(d)), "code/a.R")
})

test_that("several directories, a file, and the namespaced call are all read", {
  d <- proj(c('targets::tar_source(c("one", "two/x.R"))', "list()"),
            list("one/a.R" = fn("a"), "one/sub/b.R" = fn("b"), "two/x.R" = fn("x"), "two/y.R" = fn("y")))
  expect_setequal(rel(build_site_config(d)), c("one/a.R", "one/sub/b.R", "two/x.R"))
})

test_that("files= by name and file.path() of literals work", {
  d <- proj(c('tar_source(files = file.path("src", "fns"))', "list()"),
            list("src/fns/a.R" = fn("a")))
  expect_identical(rel(build_site_config(d)), "src/fns/a.R")
})

test_that("a bare tar_source() means R/", {
  d <- proj(c("tar_source()", "list()"), list("R/a.R" = fn("a")))
  expect_identical(rel(build_site_config(d)), "R/a.R")
})

test_that("a computed path is skipped, not guessed at or run", {
  marker <- normalizePath(withr::local_tempfile(), winslash = "/", mustWork = FALSE)
  d <- proj(c(sprintf('invisible(writeLines("x", "%s"))', marker),
              "tar_source(Sys.getenv('X_DIR'))", "list()"),
            list("R/a.R" = fn("a")))
  expect_identical(rel(build_site_config(d)), "R/a.R")
  expect_false(file.exists(marker))          # _targets.R was parsed, never run
})

test_that("a path that does not exist falls back to R/", {
  d <- proj(c('tar_source("nowhere")', "list()"), list("R/a.R" = fn("a")))
  expect_identical(rel(build_site_config(d)), "R/a.R")
})

test_that("an explicit code_dirs beats _targets.R", {
  d <- proj(c('tar_source("code")', "list()"),
            list("code/a.R" = fn("a"), "lib/b.R" = fn("b")))
  expect_identical(rel(build_site_config(d, code_dirs = "lib")), "lib/b.R")
  expect_setequal(rel(build_site_config(d, code_dirs = c("lib", "code/a.R"))),
                  c("lib/b.R", "code/a.R"))
})

test_that("an absolute code_dirs is kept as given", {
  d <- proj("list()", list("R/a.R" = fn("a")))
  other <- withr::local_tempdir(); writeLines(fn("q"), file.path(other, "q.R"))
  cfg <- build_site_config(d, code_dirs = other)
  expect_identical(basename(.function_r_files(cfg)), "q.R")
})

test_that("non-R files in a code directory are ignored", {
  d <- proj("list()", list("R/a.R" = fn("a"), "R/notes.md" = "# hi", "R/data.csv" = "a,b"))
  expect_identical(rel(build_site_config(d)), "R/a.R")
})

test_that("document_targets reads functions from a non-R directory", {
  skip_if_not_installed("targets")
  d <- proj(c("library(targets)", 'tar_source("code")',
              "list(tar_target(a, 1), tar_target(b, double_it(a)))"),
            list("code/f.R" = c("#' Double", "#' @param x x", "double_it <- function(x) x * 2")))
  suppressMessages(document_targets(d, check_outdated = FALSE))
  expect_true(file.exists(file.path(d, "tardoc", "functions", "double_it.md")))
  expect_match(paste(readLines(file.path(d, "tardoc", "targets", "b.md")), collapse = "\n"),
               "functions/double_it.md", fixed = TRUE)
})
