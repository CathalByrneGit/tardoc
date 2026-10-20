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

# ---- documentation coverage -------------------------------------------------

page <- function(name, content) list(name = name, type = "targets", content = content)

test_that(".doc_coverage counts what the reader sees on a page", {
  targets <- list(
    page("a", "# Target: a\n\n> Has a description\n\n<!-- tardoc:generated -->"),
    page("b", "# Target: b\n\n<!-- tardoc:generated -->\n## Details")
  )
  funs <- list(
    page("f", "# Function: `f`\n\n## Documentation\n\nSomething real."),
    page("g", paste0("# Function: `g`\n\n", .NO_ROXYGEN))
  )
  cov <- .doc_coverage(targets, funs)
  expect_identical(cov$targets$total, 2L)
  expect_identical(as.character(cov$targets$missing), "b")
  expect_identical(as.character(cov$functions$missing), "g")
})

test_that(".doc_coverage serialises missing names as arrays even for one", {
  cov <- .doc_coverage(list(page("b", "# Target: b\n\nno")), list())
  json <- jsonlite::toJSON(cov, auto_unbox = TRUE)
  expect_match(as.character(json), '"missing":["b"]', fixed = TRUE)
  expect_match(as.character(json), '"missing":[]', fixed = TRUE)
})

# ---- per-target history -----------------------------------------------------

snap <- function(...) {
  list(recorded = "x", targets = lapply(list(...), function(t) {
    list(name = t[[1]], status = "uptodate", last_built = t[[2]], seconds = t[[3]], bytes = t[[4]])
  }))
}

test_that(".history_series keeps one point per real build", {
  h <- list(
    snap(list("a", "2026-01-01 10:00:00", 1, 100), list("b", "2026-01-01 10:00:00", 5, 9)),
    snap(list("a", "2026-01-02 10:00:00", 2, 110), list("b", "2026-01-01 10:00:00", 5, 9)),
    snap(list("a", "2026-01-03 10:00:00", 3, 120), list("b", "2026-01-01 10:00:00", 5, 9))
  )
  ser <- .history_series(h)
  expect_length(ser$a$t, 3L)
  expect_identical(as.numeric(ser$a$s), c(1, 2, 3))
  # b was never rebuilt: three snapshots, one build, so no trend to draw.
  expect_null(ser$b)
})

test_that(".history_series is NULL without a trend and caps the points", {
  expect_null(.history_series(list()))
  expect_null(.history_series(list(snap(list("a", "t1", 1, 1)))))
  h <- lapply(1:10, function(i) snap(list("a", paste0("t", i), i, i)))
  expect_length(.history_series(h, max_points = 4L)$a$t, 4L)
})

test_that("a missing runtime becomes null in the viewer payload", {
  h <- list(snap(list("a", "t1", 1, 1)), snap(list("a", "t2", NULL, 2)))
  json <- as.character(jsonlite::toJSON(.history_payload(h), auto_unbox = TRUE,
                                        null = "null", na = "null"))
  expect_match(json, '"s":[1,null]', fixed = TRUE)
})
