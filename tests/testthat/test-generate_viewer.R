# tests/testthat/test-generate_viewer.R

test_that("generate_viewer writes viewer.html", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_viewer(mock_targets_data(), character(), cfg, pkg_name = "Test pipeline")
  expect_true(file.exists(file.path(cfg$site_path, "viewer.html")))
})

test_that("the viewer carries the pipeline name", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_viewer(mock_targets_data(), character(), cfg, pkg_name = "Zebra pipeline")
  html <- readLines(file.path(cfg$site_path, "viewer.html"), warn = FALSE)
  expect_true(any(grepl("Zebra pipeline", html, fixed = TRUE)))
})

test_that("no template placeholders survive into the output", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_viewer(mock_targets_data(), character(), cfg, pkg_name = "Test pipeline")
  html <- paste(readLines(file.path(cfg$site_path, "viewer.html"), warn = FALSE),
                collapse = "\n")
  expect_false(grepl("\\{\\{[A-Z_]+\\}\\}", html))
  expect_false(grepl("__[A-Z_]+__", html))
})

test_that("every CDN script is version-pinned with integrity", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_viewer(mock_targets_data(), character(), cfg, pkg_name = "Test pipeline")
  html <- paste(readLines(file.path(cfg$site_path, "viewer.html"), warn = FALSE),
                collapse = "\n")
  srcs <- regmatches(html, gregexpr('src="https://[^"]+"', html))[[1]]
  expect_true(length(srcs) > 0)
  # An unpinned jsdelivr path silently tracks whatever release still ships
  # that filename, so the viewer must never contain one.
  expect_false(any(grepl("jsdelivr", srcs) & !grepl("@[0-9]", srcs)))
  expect_equal(
    length(regmatches(html, gregexpr("integrity=\"sha384-", html))[[1]]),
    sum(grepl("jsdelivr", srcs))
  )
})
