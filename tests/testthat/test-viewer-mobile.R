# tests/testthat/test-viewer-mobile.R
#
# The viewer was a fixed 280px sidebar beside the content, which on a 390px
# phone left about 100px for the page -- a Target heading wrapping one word
# per line. There are no media queries to test against in a unit test, so
# these pin the mechanisms; the behaviour itself was checked in headless
# Chromium inside a 390px iframe (the browser's own minimum window width is
# wider than a phone, so a plain --window-size does not trigger the query).

tpl <- function() {
  paste(readLines(system.file("templates", "viewer.html", package = "tardoc"),
                  warn = FALSE), collapse = "\n")
}

test_that("there is a phone layout", {
  expect_match(tpl(), "@media (max-width:760px)", fixed = TRUE)
})

test_that("the navigation folds behind a Menu button on phones", {
  s <- tpl()
  expect_match(s, 'id="menu-btn"', fixed = TRUE)
  expect_match(s, "#sidebar.nav-open #nav-list", fixed = TRUE)
})

test_that("choosing a page closes the menu again", {
  s <- tpl()
  expect_match(s, "function collapseNav()", fixed = TRUE)
  # Both ways of leaving the list: opening a page, and going home.
  body <- sub(".*function goHome\\(\\) \\{", "", s)
  expect_match(substr(body, 1, 40), "collapseNav();", fixed = TRUE)
  expect_match(s, "currentKey = key;\n  collapseNav();", fixed = TRUE)
})

test_that("focusing search opens the menu so its results are visible", {
  expect_match(tpl(), "addEventListener('focus', function () { toggleNav(true); })",
               fixed = TRUE)
})

test_that("the header grid lets the title shrink", {
  # With a plain 1fr the nowrap title sets the column's minimum width and
  # pushes the Menu button off the right edge of the screen.
  expect_match(tpl(), "grid-template-columns:minmax(0,1fr) auto", fixed = TRUE)
})
