# tests/testthat/test-generate_search_index.R

.mock_dep <- function(...) list(
  upstream = character(), downstream = character(),
  edges = dplyr::tibble(from = character(), to = character())
)

test_that("generate_search_index writes search_index.json", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  local_mocked_bindings(get_target_network_dependencies = .mock_dep, .package = "tardoc")
  generate_search_index(mock_targets_data(), character(), cfg)
  expect_true(file.exists(file.path(cfg$site_path, "search_index.json")))
})

test_that("search_index.json is valid JSON", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  local_mocked_bindings(get_target_network_dependencies = .mock_dep, .package = "tardoc")
  generate_search_index(mock_targets_data(), character(), cfg)
  expect_no_error(jsonlite::fromJSON(file.path(cfg$site_path, "search_index.json")))
})

test_that("search index contains all target names", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  td  <- mock_targets_data()
  local_mocked_bindings(get_target_network_dependencies = .mock_dep, .package = "tardoc")
  generate_search_index(td, character(), cfg)
  idx <- jsonlite::fromJSON(file.path(cfg$site_path, "search_index.json"))
  expect_true(all(td$target_names %in% idx$targets$name))
})

test_that("search index contains all function names", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  local_mocked_bindings(get_target_network_dependencies = .mock_dep, .package = "tardoc")
  generate_search_index(mock_targets_data(), c("fn_a","fn_b"), cfg)
  idx <- jsonlite::fromJSON(file.path(cfg$site_path, "search_index.json"))
  expect_true(all(c("fn_a","fn_b") %in% idx$functions$name))
})

test_that("target entries have required fields", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  local_mocked_bindings(get_target_network_dependencies = .mock_dep, .package = "tardoc")
  generate_search_index(mock_targets_data(), character(), cfg)
  idx <- jsonlite::fromJSON(file.path(cfg$site_path, "search_index.json"))
  expect_true(all(c("name","type","description","command","file") %in% names(idx$targets)))
})

test_that("target file paths point to targets/ subdir", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  local_mocked_bindings(get_target_network_dependencies = .mock_dep, .package = "tardoc")
  generate_search_index(mock_targets_data(), character(), cfg)
  idx <- jsonlite::fromJSON(file.path(cfg$site_path, "search_index.json"))
  expect_true(all(startsWith(idx$targets$file, "targets/")))
})

test_that("function file paths point to functions/ subdir", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  local_mocked_bindings(get_target_network_dependencies = .mock_dep, .package = "tardoc")
  generate_search_index(mock_targets_data(), c("my_fn"), cfg)
  idx <- jsonlite::fromJSON(file.path(cfg$site_path, "search_index.json"))
  expect_true(all(startsWith(idx$functions$file, "functions/")))
})
