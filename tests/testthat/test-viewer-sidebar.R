# tests/testthat/test-viewer-sidebar.R
#
# Guards on the sidebar's scaling behaviour. Measured on a 420-target pipeline
# before the rework: 420 nav items, 12,616px of scroll in a 900px viewport,
# and loadPage() rebuilding every node on each click to move one class.
#
# The rendering is JavaScript in a template, so these assert the mechanisms
# are present rather than exercising them -- the behaviour itself was checked
# in a headless browser against that pipeline.

tpl <- function() {
  paste(readLines(system.file("templates", "viewer.html", package = "tardoc"),
                  warn = FALSE), collapse = "\n")
}

test_that("the default list is capped", {
  expect_match(tpl(), "NAV_CAP", fixed = TRUE)
  expect_match(tpl(), "show all", fixed = TRUE)
})

test_that("targets are grouped so the default view is informative", {
  # The first 40 of 400 alphabetically says nothing; the errored and outdated
  # ones are the reason the page was opened.
  s <- tpl()
  for (label in c("Errored", "Outdated", "Not built", "Up to date")) {
    expect_match(s, label, fixed = TRUE)
  }
  expect_match(s, "navGroups", fixed = TRUE)
})

test_that("groups that matter are never truncated", {
  # `always` marks the groups exempt from the cap.
  expect_match(tpl(), "always: true", fixed = TRUE)
})

test_that("functions are grouped by the file that defines them", {
  expect_match(tpl(), "source_file", fixed = TRUE)
})

test_that("there is one search implementation, not two", {
  # Typing ran Fuse; renderNavList() did its own substring filter; clicking a
  # result re-rendered with the substring one, silently replacing 30 ranked
  # matches with 70 different rows.
  s <- tpl()
  expect_false(grepl("toLowerCase().includes(filter", s, fixed = TRUE))
  expect_match(s, "function renderSearch", fixed = TRUE)
  expect_match(s, "function renderNav()", fixed = TRUE)
})

test_that("search is name-weighted and not anchored to the start of a field", {
  # Without ignoreLocation, "station" would not match
  # "clean_station_readings"; with a loose threshold, "eval_01" matched a
  # hundred rows.
  s <- tpl()
  expect_match(s, "ignoreLocation: true", fixed = TRUE)
  expect_match(s, "weight: 3", fixed = TRUE)
})

test_that("navigation moves a class instead of rebuilding the list", {
  s <- tpl()
  expect_match(s, "function markActive", fixed = TRUE)
  # loadPage() must not re-render the whole list.
  body <- sub(".*function loadPage\\(type, name\\) \\{", "", s)
  body <- substr(body, 1, 1200)
  expect_false(grepl("renderNavList(", body, fixed = TRUE))
  expect_true(grepl("markActive()", body, fixed = TRUE))
})

test_that("clicks are delegated rather than bound per item", {
  # One listener, not one closure per row.
  s <- tpl()
  expect_match(s, "getElementById('nav-list').addEventListener('click'", fixed = TRUE)
  expect_match(s, "data-key", fixed = TRUE)
})

test_that("the current page is pinned when the cap would hide it", {
  expect_match(tpl(), "nav-pin", fixed = TRUE)
})

test_that("the generated viewer keeps all of it", {
  # The template is substituted into output; a mangled replacement has eaten
  # blocks of this file before.
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  suppressMessages(generate_viewer(mock_targets_data(), character(), cfg, "Test"))
  out <- paste(readLines(file.path(cfg$site_path, "viewer.html"), warn = FALSE),
               collapse = "\n")
  for (needle in c("NAV_CAP", "navGroups", "markActive", "renderSearch",
                   "renderNav()", "nav-pin", "ignoreLocation: true")) {
    expect_match(out, needle, fixed = TRUE)
  }
})
