# tests/testthat/test-generate_llms_txt.R

.make_llms <- function(tmp, td = mock_targets_data(), ...) {
  cfg <- mock_cfg(tmp)
  setup_site_dirs(cfg)
  generate_llms_txt(td, cfg, project_title = "Test pipeline", ...)
  readLines(file.path(tmp, "llms.txt"), warn = FALSE)
}

test_that("generate_llms_txt writes llms.txt at project root", {
  tmp <- withr::local_tempdir()
  .make_llms(tmp)
  expect_true(file.exists(file.path(tmp, "llms.txt")))
})

test_that("llms.txt contains project title as h1", {
  tmp <- withr::local_tempdir()
  content <- paste(.make_llms(tmp), collapse = "\n")
  expect_match(content, "# Test pipeline")
})

test_that("llms.txt contains all target names", {
  tmp <- withr::local_tempdir()
  td  <- mock_targets_data()
  content <- paste(.make_llms(tmp, td), collapse = "\n")
  for (name in td$target_names) expect_match(content, name)
})

test_that("llms.txt includes description blockquote for targets that have one", {
  tmp <- withr::local_tempdir()
  content <- paste(.make_llms(tmp), collapse = "\n")
  expect_match(content, "Raw sensor readings")
})

test_that("llms.txt omits blockquote for targets without description", {
  tmp  <- withr::local_tempdir()
  lines <- .make_llms(tmp)
  model_fit_idx <- grep("model_fit", lines)
  expect_true(length(model_fit_idx) > 0)
})

test_that("llms.txt contains ## Targets and ## Functions sections", {
  tmp <- withr::local_tempdir()
  content <- paste(.make_llms(tmp), collapse = "\n")
  expect_match(content, "## Targets")
  expect_match(content, "## Functions")
})

test_that("generate_llms_txt writes to cfg$project_path not cfg$package_path", {
  tmp <- withr::local_tempdir()
  cfg <- mock_cfg(tmp)
  setup_site_dirs(cfg)
  expect_true("project_path" %in% names(cfg))
  expect_false("package_path" %in% names(cfg))
  generate_llms_txt(mock_targets_data(), cfg, project_title = "Test")
  expect_true(file.exists(file.path(cfg$project_path, "llms.txt")))
})

test_that("llms.txt includes project description blockquote when provided", {
  tmp <- withr::local_tempdir()
  content <- paste(.make_llms(tmp, project_desc = "A modelling pipeline."), collapse = "\n")
  expect_match(content, "A modelling pipeline.")
})
