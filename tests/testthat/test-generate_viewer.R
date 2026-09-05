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

test_that("every external asset is version-pinned with integrity", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_viewer(mock_targets_data(), character(), cfg, pkg_name = "Test pipeline")
  html <- paste(readLines(file.path(cfg$site_path, "viewer.html"), warn = FALSE),
                collapse = "\n")
  # Scripts and stylesheets alike, across both CDNs the viewer uses.
  assets <- regmatches(html, gregexpr('(src|href)="https://(cdn\\.jsdelivr|cdnjs)[^"]+"',
                                      html))[[1]]
  expect_true(length(assets) >= 6)
  # An unpinned path silently tracks whatever release still ships that
  # filename, so the viewer must never contain one. jsdelivr pins read
  # "pkg@1.2.3", cdnjs pins read "/libs/pkg/1.2.3/".
  expect_false(any(!grepl("@[0-9]|/[0-9]+\\.[0-9]", assets)))
  # One integrity attribute per external asset.
  expect_equal(
    length(regmatches(html, gregexpr("integrity=\"sha384-", html))[[1]]),
    length(assets)
  )
})
