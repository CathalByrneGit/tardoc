# tests/testthat/test-callr_fn.R
#
# targets reads _targets.R in a subprocess by default, which keeps the
# pipeline's environment out of the caller's session. Some R builds cannot
# spawn one: under webR every tar_manifest(), tar_network(), tar_outdated()
# and tar_make() call fails with "Cannot find R executable at
# /usr/lib/R/bin/R". Passing callr_function = NULL reads the pipeline in the
# current session instead, and everything works.
#
# The check is for the capability rather than the platform, because that is
# what callr itself looks for -- see site/notes/webr-feasibility.md.

test_that("a spawnable R gives the subprocess reader", {
  # This machine has one; if it did not, targets' own default would be broken.
  skip_if_not(any(file.exists(file.path(R.home("bin"), c("R", "R.exe")))))
  skip_if_not_installed("callr")
  expect_identical(tardoc:::.callr_fn(), callr::r)
})

test_that("no R executable means the in-process reader", {
  # R.home() is resolved from R_HOME, so pointing it at an empty directory
  # reproduces what callr sees under webR.
  empty <- withr::local_tempdir()
  withr::local_envvar(R_HOME = empty)
  expect_null(tardoc:::.callr_fn())
})

test_that("R.exe counts, so Windows is not treated as unspawnable", {
  home <- withr::local_tempdir()
  withr::local_envvar(R_HOME = home)
  # R.home("bin") is <R_HOME>/bin on Unix but <R_HOME>/bin/x64 on Windows, so
  # the fake layout has to be built where R would look rather than where the
  # Unix layout puts it -- otherwise this test fails on the one platform whose
  # executable name it exists to check.
  dir.create(R.home("bin"), recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(R.home("bin"), "R.exe"))
  skip_if_not_installed("callr")
  expect_identical(tardoc:::.callr_fn(), callr::r)
})

test_that("load_targets_data passes the choice to every targets call", {
  # Three call sites; missing one leaves a failure that only shows up in an
  # environment nobody runs the test suite in.
  src <- paste(deparse(body(load_targets_data)), collapse = "\n")
  expect_match(src, "cf <- .callr_fn()", fixed = TRUE)
  for (fn in c("tar_manifest", "tar_network", "tar_outdated")) {
    call_txt <- regmatches(src, regexpr(paste0(fn, "\\([^)]*\\)"), src))
    expect_true(length(call_txt) == 1L, info = fn)
    expect_match(call_txt, "callr_function", fixed = TRUE)
  }
})

test_that("documenting a project does not write _targets.yaml", {
  # tar_config_set() writes that file in the user's project, and the store
  # path tardoc had was absolute -- so running tardoc once left a machine
  # path committed in their repository, breaking the project everywhere else.
  skip_if_not_installed("targets")
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "R"))
  writeLines("double_it <- function(x) x * 2", file.path(dir, "R", "f.R"))
  writeLines(c("library(targets)", "tar_source('R')",
               "list(tar_target(a, 1), tar_target(b, double_it(a)))"),
             file.path(dir, "_targets.R"))

  cfg <- build_site_config(dir)
  setup_site_dirs(cfg)
  suppressMessages(load_targets_data(cfg, check_outdated = FALSE))

  expect_false(file.exists(file.path(dir, "_targets.yaml")))
})

test_that("the store is passed per call rather than set globally", {
  src <- paste(deparse(body(load_targets_data)), collapse = "\n")
  expect_false(grepl("tar_config_set", src, fixed = TRUE))
  # Matching to the closing paren is not safe -- tar_meta()'s arguments
  # contain their own -- so look at a window after each call name.
  for (fn in c("tar_network", "tar_meta", "tar_progress", "tar_outdated")) {
    window <- regmatches(src, regexpr(paste0(fn, "\\(.{0,110}"), src))
    expect_true(length(window) == 1L, info = fn)
    expect_match(window, "store = store", fixed = TRUE)
  }
})
