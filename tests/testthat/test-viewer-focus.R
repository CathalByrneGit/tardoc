# tests/testthat/test-viewer-focus.R
#
# Clicking a node fades everything outside its upstream and downstream
# chains. The behaviour is JavaScript in a template, so these pin the
# mechanisms; it was checked in headless Chromium against the example
# pipeline (focus on drift_model, upstream only: its three targets stay lit,
# station_summary, drift_flags and report fade).

tpl <- function() {
  paste(readLines(system.file("templates", "viewer.html", package = "tardoc"),
                  warn = FALSE), collapse = "\n")
}

test_that("selecting a node applies a focus", {
  s <- tpl()
  expect_match(s, "function applyFocus(id)", fixed = TRUE)
  # rfOpen is the one place every node click and neighbour chip goes through.
  expect_match(s, "rfPanel.hidden = false;\n  applyFocus(id);", fixed = TRUE)
})

test_that("closing the panel clears the focus", {
  expect_match(tpl(), "hidden = true;\n  clearFocus();", fixed = TRUE)
})

test_that("traversal is directional", {
  # Upstream follows edges backwards only and downstream forwards only, so a
  # shared function does not pull its other users into the neighbourhood.
  s <- tpl()
  expect_match(s, "reach(id, FOCUS_UP, depth)", fixed = TRUE)
  expect_match(s, "reach(id, FOCUS_DOWN, depth)", fixed = TRUE)
})

test_that("hidden function nodes are not counted", {
  expect_match(tpl(), "!fnShown", fixed = TRUE)
})

test_that("the fade is a generated rule, not a class React Flow can overwrite", {
  s <- tpl()
  expect_match(s, ".react-flow__node[data-id=", fixed = TRUE)
  expect_match(s, "rf__edge-", fixed = TRUE)
})

test_that("the focus controls are in the generated viewer", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  suppressMessages(generate_viewer(mock_targets_data(), character(), cfg, "Test"))
  html <- paste(readLines(file.path(cfg$site_path, "viewer.html"), warn = FALSE),
                collapse = "\n")
  for (needle in c("focus-bar", "focus-dir", "focus-depth", "focus-clear",
                   "home-overview")) {
    expect_match(html, needle, fixed = TRUE)
  }
})
