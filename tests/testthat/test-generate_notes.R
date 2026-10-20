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

test_that("generate_notes creates a project overview stub", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_notes("a", character(), cfg)
  expect_true(file.exists(file.path(cfg$notes_dir, "index.md")))
})

test_that("the overview stub reads as empty, so the home page is unchanged", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_notes("a", character(), cfg)
  # The stub is comments only; the viewer strips them, but R must not have
  # decided it is content in the meantime.
  stripped <- gsub("(?s)<!--.*?-->", "", read_overview(cfg), perl = TRUE)
  expect_identical(trimws(stripped), "")
})

test_that("generate_notes never overwrites the project overview", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  writeLines("Owned by Field Ops.", file.path(cfg$notes_dir, "index.md"))
  generate_notes("a", character(), cfg)
  expect_match(read_overview(cfg), "Owned by Field Ops.", fixed = TRUE)
})

test_that("read_overview is empty when there is no file", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  expect_identical(read_overview(cfg), "")
})

test_that("the overview reaches the generated viewer", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  writeLines("Weekly station health check.", file.path(cfg$notes_dir, "index.md"))
  suppressMessages(generate_viewer(mock_targets_data(), character(), cfg, "Test"))
  html <- paste(readLines(file.path(cfg$site_path, "viewer.html"), warn = FALSE),
                collapse = "\n")
  expect_match(html, "const OVERVIEW = \"Weekly station health check.\"", fixed = TRUE)
})

test_that("an overview cannot close the script tag it is embedded in", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  writeLines("</script><b>x</b>", file.path(cfg$notes_dir, "index.md"))
  suppressMessages(generate_viewer(mock_targets_data(), character(), cfg, "Test"))
  html <- paste(readLines(file.path(cfg$site_path, "viewer.html"), warn = FALSE),
                collapse = "\n")
  line <- regmatches(html, regexpr("const OVERVIEW = [^\n]*", html))
  expect_false(grepl("</script>", line, fixed = TRUE))
})
