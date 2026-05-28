# tests/testthat/test-document_targets.R

test_that("view_tardoc errors when viewer.html absent", {
  tmp <- withr::local_tempdir()
  expect_error(view_tardoc(tmp), "Run document_targets")
})

test_that("view_wasm_analytics errors when wasm_analytics.html absent", {
  tmp <- withr::local_tempdir()
  expect_error(view_wasm_analytics(tmp), "Run document_targets")
})
