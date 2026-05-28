# tests/testthat/test-generate_target_pages.R

# ---- .pull_description ------------------------------------------------------

test_that(".pull_description returns value when present", {
  row <- dplyr::tibble(name = "x", description = "My description")
  expect_equal(tardoc:::.pull_description(row), "My description")
})

test_that(".pull_description returns NA for NA value", {
  expect_true(is.na(tardoc:::.pull_description(dplyr::tibble(name="x", description=NA_character_))))
})

test_that(".pull_description returns NA for empty string", {
  expect_true(is.na(tardoc:::.pull_description(dplyr::tibble(name="x", description=""))))
})

test_that(".pull_description returns NA when column absent", {
  expect_true(is.na(tardoc:::.pull_description(dplyr::tibble(name="x", command="do()"))))
})

# ---- .local_mermaid ---------------------------------------------------------

test_that(".local_mermaid returns valid mermaid block", {
  dep <- list(upstream="raw_data", downstream="model_fit",
              edges=dplyr::tibble(from=c("raw_data","clean_data"), to=c("clean_data","model_fit")))
  result <- tardoc:::.local_mermaid("clean_data", dep)
  expect_match(result, "```mermaid")
  expect_match(result, "graph LR")
  expect_match(result, "raw_data --> clean_data")
})

test_that(".local_mermaid styles the focal target", {
  dep <- list(upstream="raw_data", downstream=character(),
              edges=dplyr::tibble(from="raw_data", to="focal"))
  expect_match(tardoc:::.local_mermaid("focal", dep), "style focal")
})

test_that(".local_mermaid handles target with no edges", {
  dep <- list(upstream=character(), downstream=character(),
              edges=dplyr::tibble(from=character(), to=character()))
  result <- tardoc:::.local_mermaid("lone_target", dep)
  expect_match(result, "lone_target")
  expect_match(result, "```mermaid")
})

# ---- .build_target_generated_block -----------------------------------------

test_that(".build_target_generated_block includes command", {
  meta <- dplyr::tibble(name="t",type="stem",time="2024-01-01",error=NA_character_,bytes=1,format="rds")
  fns  <- dplyr::tibble(name=character(),type=character())
  dep  <- list(upstream=character(),downstream=character(),edges=dplyr::tibble(from=character(),to=character()))
  block <- tardoc:::.build_target_generated_block("t", meta, "do_thing(x)", fns, dep)
  expect_match(block, "do_thing\\(x\\)")
  expect_match(block, "```r")
})

test_that(".build_target_generated_block shows Up-to-date when no error", {
  meta <- dplyr::tibble(name="t",type="stem",time="2024-01-01",error=NA_character_,bytes=1,format="rds")
  fns  <- dplyr::tibble(name=character(),type=character())
  dep  <- list(upstream=character(),downstream=character(),edges=dplyr::tibble(from=character(),to=character()))
  expect_match(tardoc:::.build_target_generated_block("t", meta, "cmd()", fns, dep), "Up-to-date")
})

test_that(".build_target_generated_block includes error when present", {
  meta <- dplyr::tibble(name="t",type="stem",time="2024-01-01",error="object not found",bytes=1,format="rds")
  fns  <- dplyr::tibble(name=character(),type=character())
  dep  <- list(upstream=character(),downstream=character(),edges=dplyr::tibble(from=character(),to=character()))
  expect_match(tardoc:::.build_target_generated_block("t", meta, "cmd()", fns, dep), "object not found")
})

# ---- .write_generated_md / preservation ------------------------------------

test_that(".write_generated_md creates a new file", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "test.md")
  tardoc:::.write_generated_md(path, "# Target: t", NA_character_, "## Block\n\ncontent\n")
  expect_true(file.exists(path))
})

test_that("new .md file contains generated markers", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "test.md")
  tardoc:::.write_generated_md(path, "# Target: t", NA_character_, "## Block\n\ncontent\n")
  content <- paste(readLines(path), collapse = "\n")
  expect_match(content, "<!-- tardoc:generated -->")
  expect_match(content, "<!-- tardoc:end -->")
})

test_that("re-running .write_generated_md updates generated block only", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "test.md")
  tardoc:::.write_generated_md(path, "# Target: t", NA_character_, "## Block\n\nv1\n")
  existing <- paste(readLines(path), collapse = "\n")
  writeLines(paste0(existing, "\n\n## My notes\n\nKeep this.\n"), path)
  tardoc:::.write_generated_md(path, "# Target: t", NA_character_, "## Block\n\nv2\n")
  final <- paste(readLines(path), collapse = "\n")
  expect_match(final, "v2")
  expect_false(grepl("v1", final))
  expect_match(final, "Keep this.")
})

# ---- generate_all_target_pages integration ----------------------------------

test_that("generate_all_target_pages writes one .md per target", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  td  <- mock_targets_data()
  local_mocked_bindings(
    get_target_network_dependencies = function(...) list(
      upstream=character(), downstream=character(),
      edges=dplyr::tibble(from=character(), to=character())),
    .package = "tardoc")
  generate_all_target_pages(td, cfg)
  expect_equal(length(list.files(cfg$targets_dir, pattern="\\.md$")), length(td$target_names))
})

test_that("generate_all_target_pages returns target names", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  td  <- mock_targets_data()
  local_mocked_bindings(
    get_target_network_dependencies = function(...) list(
      upstream=character(), downstream=character(),
      edges=dplyr::tibble(from=character(), to=character())),
    .package = "tardoc")
  result <- generate_all_target_pages(td, cfg)
  expect_equal(sort(result), sort(td$target_names))
})
