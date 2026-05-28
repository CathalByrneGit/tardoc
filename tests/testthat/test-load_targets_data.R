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
