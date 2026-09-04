# tests/testthat/test-generate_wasm_viewer.R

test_that("generate_wasm_viewer writes wasm_analytics.html", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_wasm_viewer(mock_analytics_data(), cfg, pkg_name = "Test pipeline")
  expect_true(file.exists(file.path(cfg$site_path, "wasm_analytics.html")))
})

test_that("pipeline data is embedded rather than fetched", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  td  <- mock_targets_data()
  generate_wasm_viewer(mock_analytics_data(td), cfg, pkg_name = "Test pipeline")
  html <- paste(readLines(file.path(cfg$site_path, "wasm_analytics.html"), warn = FALSE),
                collapse = "\n")
  expect_true(all(vapply(td$target_names,
                         function(n) grepl(n, html, fixed = TRUE), logical(1))))
})

test_that("duckdb-wasm is pinned to an exact version", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_wasm_viewer(mock_analytics_data(), cfg, pkg_name = "Test pipeline")
  html <- paste(readLines(file.path(cfg$site_path, "wasm_analytics.html"), warn = FALSE),
                collapse = "\n")
  expect_false(grepl("duckdb-wasm@latest", html, fixed = TRUE))
  expect_match(html, "duckdb-wasm@[0-9]+\\.[0-9]+\\.[0-9]+")
})
