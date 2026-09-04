# tests/testthat/test-load_targets_data.R

test_that(".empty_meta returns a tibble with correct columns", {
  result <- tardoc:::.empty_meta(c("a", "b", "c"))
  expect_s3_class(result, "tbl_df")
  expect_named(result, c("name", "type", "time", "error", "bytes", "format"))
})

test_that(".empty_meta has one row per target name", {
  names  <- c("raw_data", "clean_data", "model_fit")
  result <- tardoc:::.empty_meta(names)
  expect_equal(nrow(result), 3)
  expect_equal(result$name, names)
})

test_that(".empty_meta fills status columns with NA", {
  result <- tardoc:::.empty_meta("a")
  expect_true(is.na(result$time))
  expect_true(is.na(result$error))
  expect_true(is.na(result$bytes))
  expect_true(is.na(result$format))
})

test_that(".empty_meta type column is stem for all rows", {
  result <- tardoc:::.empty_meta(c("x", "y"))
  expect_true(all(result$type == "stem"))
})

test_that("load_targets_data does not write into the global environment", {
  # withr::with_dir() evaluates its code in the caller's frame, so `<<-` inside
  # it reached past the function and bound into globalenv, clobbering any user
  # variable called meta / network / manifest / target_names / has_store.
  polluters <- c("meta", "network", "manifest", "target_names", "has_store")
  sentinel  <- "do-not-clobber"
  for (v in polluters) assign(v, sentinel, envir = globalenv())
  withr::defer(rm(list = polluters, envir = globalenv()))

  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp)
  td  <- mock_targets_data()
  local_mocked_bindings(
    tar_config_set = function(...) invisible(NULL),
    tar_manifest   = function(...) td$manifest,
    tar_network    = function(...) td$network,
    tar_meta       = function(...) td$meta,
    .package = "targets"
  )
  suppressMessages(load_targets_data(cfg))

  for (v in polluters) {
    expect_identical(get(v, envir = globalenv()), sentinel,
                     info = paste("globalenv$", v, "was overwritten"))
  }
})

test_that("load_targets_data returns the documented fields", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp)
  td  <- mock_targets_data()
  local_mocked_bindings(
    tar_config_set = function(...) invisible(NULL),
    tar_manifest   = function(...) td$manifest,
    tar_network    = function(...) td$network,
    tar_meta       = function(...) td$meta,
    .package = "targets"
  )
  res <- suppressMessages(load_targets_data(cfg))
  expect_named(res, c("meta", "target_names", "network", "manifest", "has_store"))
  expect_setequal(res$target_names, td$target_names)
  expect_false(res$has_store)
})
