# tests/testthat/test-generate_notes.R

test_that("generate_notes creates stub files for all targets", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_notes(c("raw_data","clean_data"), character(), cfg)
  expect_true(file.exists(file.path(cfg$notes_targets, "raw_data.md")))
  expect_true(file.exists(file.path(cfg$notes_targets, "clean_data.md")))
})

test_that("generate_notes creates stub files for all functions", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_notes(character(), c("clean_raw","fit_model"), cfg)
  expect_true(file.exists(file.path(cfg$notes_functions, "clean_raw.md")))
  expect_true(file.exists(file.path(cfg$notes_functions, "fit_model.md")))
})

test_that("stub file contains the name", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_notes("my_target", character(), cfg)
  content <- paste(readLines(file.path(cfg$notes_targets, "my_target.md")), collapse = "\n")
  expect_match(content, "my_target")
})

test_that("generate_notes never overwrites existing note", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  path <- file.path(cfg$notes_targets, "raw_data.md")
  writeLines("## My note\n\nKeep this.", path)
  generate_notes("raw_data", character(), cfg)
  content <- paste(readLines(path), collapse = "\n")
  expect_match(content, "Keep this.")
})

test_that("generate_notes is idempotent", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  expect_no_error(generate_notes("raw_data", "clean_raw", cfg))
  expect_no_error(generate_notes("raw_data", "clean_raw", cfg))
})

test_that("read_note returns empty string when file absent", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  expect_equal(read_note("nonexistent", "targets", cfg), "")
})

test_that("read_note returns file content when present", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  writeLines("Some useful notes.", file.path(cfg$notes_targets, "my_target.md"))
  expect_match(read_note("my_target", "targets", cfg), "Some useful notes.")
})

test_that("read_note works for functions", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  writeLines("Function notes.", file.path(cfg$notes_functions, "my_fn.md"))
  expect_match(read_note("my_fn", "functions", cfg), "Function notes.")
})
