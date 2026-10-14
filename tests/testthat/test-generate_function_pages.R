# tests/testthat/test-generate_function_pages.R

test_that("generate_all_function_pages writes one .md per function", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  cfg$r_scripts_dir <- file.path(tmp, "R"); write_mock_r_file(cfg$r_scripts_dir)
  local_mocked_bindings(get_fn_docs = function(...) "## Description\n\nA helper.", .package = "tardoc")
  generate_all_function_pages(cfg)
  expect_gte(length(list.files(cfg$functions_dir, pattern = "\\.md$")), 1L)
})

test_that("function .md files contain generated markers", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  cfg$r_scripts_dir <- file.path(tmp, "R"); write_mock_r_file(cfg$r_scripts_dir)
  local_mocked_bindings(get_fn_docs = function(...) "## Description\n\nA helper.", .package = "tardoc")
  generate_all_function_pages(cfg)
  first <- list.files(cfg$functions_dir, pattern = "\\.md$", full.names = TRUE)[1]
  content <- paste(readLines(first), collapse = "\n")
  expect_match(content, "<!-- tardoc:generated -->")
  expect_match(content, "<!-- tardoc:end -->")
})

test_that("function .md title is correct format", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  cfg$r_scripts_dir <- file.path(tmp, "R"); write_mock_r_file(cfg$r_scripts_dir, "math.R")
  local_mocked_bindings(get_fn_docs = function(...) "## Description\n\nAdds.", .package = "tardoc")
  generate_all_function_pages(cfg)
  content <- paste(readLines(file.path(cfg$functions_dir, "add.md")), collapse = "\n")
  expect_match(content, "# Function: `add`")
})

test_that("function .md includes source file name", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  cfg$r_scripts_dir <- file.path(tmp, "R"); write_mock_r_file(cfg$r_scripts_dir, "myfile.R")
  local_mocked_bindings(get_fn_docs = function(...) "## Description\n\nA function.", .package = "tardoc")
  generate_all_function_pages(cfg)
  content <- paste(readLines(file.path(cfg$functions_dir, "add.md")), collapse = "\n")
  expect_match(content, "myfile.R")
})

test_that("function .md includes fallback when no docs", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  cfg$r_scripts_dir <- file.path(tmp, "R"); write_mock_r_file(cfg$r_scripts_dir)
  local_mocked_bindings(get_fn_docs = function(...) NULL, .package = "tardoc")
  expect_no_error(generate_all_function_pages(cfg))
  first <- list.files(cfg$functions_dir, pattern = "\\.md$", full.names = TRUE)[1]
  content <- paste(readLines(first), collapse = "\n")
  expect_match(content, "No roxygen documentation found")
})

test_that("generate_all_function_pages returns function names", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  cfg$r_scripts_dir <- file.path(tmp, "R"); write_mock_r_file(cfg$r_scripts_dir)
  local_mocked_bindings(get_fn_docs = function(...) NULL, .package = "tardoc")
  result <- generate_all_function_pages(cfg)
  expect_true(is.character(result) && length(result) >= 1L)
})

test_that("re-running preserves content outside generated markers", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  cfg$r_scripts_dir <- file.path(tmp, "R"); write_mock_r_file(cfg$r_scripts_dir)
  local_mocked_bindings(get_fn_docs = function(...) "## Description\n\nVersion 1.", .package = "tardoc")
  generate_all_function_pages(cfg)
  path <- file.path(cfg$functions_dir, "add.md")
  writeLines(paste0(paste(readLines(path), collapse = "\n"), "\n\n## My notes\n\nCustom.\n"), path)
  local_mocked_bindings(get_fn_docs = function(...) "## Description\n\nVersion 2.", .package = "tardoc")
  generate_all_function_pages(cfg)
  final <- paste(readLines(path), collapse = "\n")
  expect_match(final, "Version 2")
  expect_false(grepl("Version 1", final))
  expect_match(final, "Custom.")
})

test_that("the source code is shown whether or not repo_url is set", {
  # With repo_url set, the code used to be replaced by a link, so a project
  # publishing from CI -- which sets repo_url -- got a Source heading with
  # nothing under it. The live example site shipped that way.
  for (url in list(NULL, "https://github.com/user/repo/blob/main/")) {
    tmp <- withr::local_tempdir()
    cfg <- build_site_config(tmp, repo_url = url); setup_site_dirs(cfg)
    cfg$r_scripts_dir <- file.path(tmp, "R"); write_mock_r_file(cfg$r_scripts_dir, "math.R")
    local_mocked_bindings(get_fn_docs = function(...) "## Description\n\nAdds.", .package = "tardoc")
    suppressMessages(generate_all_function_pages(cfg))
    content <- paste(readLines(file.path(cfg$functions_dir, "add.md")), collapse = "\n")
    expect_match(content, "## Source\n\nDefined in ", fixed = TRUE)
    expect_match(content, "```r\nadd <- function", fixed = TRUE)
  }
})

test_that("with repo_url the file name links to the definition line", {
  tmp <- withr::local_tempdir()
  cfg <- build_site_config(tmp, repo_url = "https://github.com/user/repo/blob/main/")
  setup_site_dirs(cfg)
  cfg$r_scripts_dir <- file.path(tmp, "R"); write_mock_r_file(cfg$r_scripts_dir, "math.R")
  local_mocked_bindings(get_fn_docs = function(...) "## Description\n\nAdds.", .package = "tardoc")
  suppressMessages(generate_all_function_pages(cfg))
  content <- paste(readLines(file.path(cfg$functions_dir, "add.md")), collapse = "\n")
  expect_match(content, "(https://github.com/user/repo/blob/main/R/math.R#L", fixed = TRUE)
})
