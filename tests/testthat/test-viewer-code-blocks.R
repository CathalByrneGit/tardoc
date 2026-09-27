# tests/testthat/test-viewer-code-blocks.R
#
# Code blocks had no height limit, so a long function ran to 2.6 screens.
# Measured across tardoc's own 115 functions, though, the median is 12 lines:
# a fixed-height pane would add a scrollbar to something that already fits
# and create a nested-scroll trap for 84% of functions to fix the other 16%.
# Hence clamp-only-what-is-long, plus a pop-out for the separate problem of
# long lines scrolling sideways in a ~900px column.
#
# The rendering is JavaScript in a template, so these assert the mechanisms
# are present; the behaviour itself was checked in a headless browser against
# a 113-line function (2.6 screens -> 1.5 clamped, expand and pop-out both
# working, Escape closing).

tpl <- function() {
  paste(readLines(system.file("templates", "viewer.html", package = "tardoc"),
                  warn = FALSE), collapse = "\n")
}

test_that("only long blocks are clamped", {
  s <- tpl()
  expect_match(s, "CODE_CLAMP_LINES", fixed = TRUE)
  # The short-block early return is what keeps the common case untouched.
  expect_match(s, "if (lines <= CODE_CLAMP_LINES) return;", fixed = TRUE)
})

test_that("the clamp threshold is in a sane range", {
  s <- tpl()
  n <- as.integer(sub(".*CODE_CLAMP_LINES = (\\d+).*", "\\1",
                      regmatches(s, regexpr("CODE_CLAMP_LINES = \\d+", s))))
  # Below ~25 it would clamp ordinary functions; above ~80 it would never fire.
  expect_gte(n, 25L)
  expect_lte(n, 80L)
})

test_that("a clamped block says how much it is hiding", {
  # "Show all" without a number tells the reader nothing about the cost.
  expect_match(tpl(), "'Show all ' + lines + ' lines'", fixed = TRUE)
})

test_that("every block gets a pop-out, not just the clamped ones", {
  # The pop-out solves width, which a short block with long lines also has.
  s <- tpl()
  expect_match(s, "openCodeModal", fixed = TRUE)
  # The button is added before the length check returns.
  before <- sub("if \\(lines <= CODE_CLAMP_LINES\\) return;.*", "", s)
  expect_match(before, "wrap.appendChild(pop)", fixed = TRUE)
})

test_that("the overlay can be dismissed three ways", {
  s <- tpl()
  expect_match(s, "code-modal-close", fixed = TRUE)
  expect_match(s, "ev.key === 'Escape'", fixed = TRUE)
  expect_match(s, "ev.target.id === 'code-modal'", fixed = TRUE)
})

test_that("clicking the code itself does not dismiss the overlay", {
  # Selecting text inside the block must not close it.
  expect_match(tpl(), "if (ev.target.id === 'code-modal') closeCodeModal();",
               fixed = TRUE)
})

test_that("the graph host is not wrapped as a code block", {
  # The local dependency graph replaces a fence; wrapping it would put an
  # Expand button on a React Flow canvas.
  expect_match(tpl(), "pre.closest('.local-graph')", fixed = TRUE)
})

test_that("blocks are not wrapped twice on re-render", {
  expect_match(tpl(), "pre.closest('.codewrap')", fixed = TRUE)
})

test_that("the generated viewer keeps the code-block machinery", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  suppressMessages(generate_viewer(mock_targets_data(), character(), cfg, "Test"))
  out <- paste(readLines(file.path(cfg$site_path, "viewer.html"), warn = FALSE),
               collapse = "\n")
  for (needle in c("enhanceCodeBlocks", "CODE_CLAMP_LINES", "openCodeModal",
                   "code-modal", "codewrap")) {
    expect_match(out, needle, fixed = TRUE)
  }
})
