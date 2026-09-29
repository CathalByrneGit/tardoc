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
# what callr itself looks for -- see docs/webr-feasibility.md.

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
  dir.create(file.path(home, "bin"))
  file.create(file.path(home, "bin", "R.exe"))
  withr::local_envvar(R_HOME = home)
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
