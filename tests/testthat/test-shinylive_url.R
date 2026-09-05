# tests/testthat/test-shinylive_url.R
#
# The encoding must round-trip: shinylive.io will only run what it can decode.

skip_if_no_lz <- function() skip_if_not_installed("lzstring")

decode <- function(url) {
  code <- sub("^.*#code=", "", url)
  jsonlite::fromJSON(lzstring::decompressFromEncodedURIComponent(code),
                     simplifyDataFrame = FALSE)
}

test_that("a single unnamed string becomes app.R", {
  skip_if_no_lz()
  url <- shinylive_url("cat('hello')")
  files <- decode(url)
  expect_length(files, 1L)
  expect_equal(files[[1]]$name, "app.R")
  expect_equal(files[[1]]$content, "cat('hello')")
})

test_that("the payload round-trips exactly, including multiple files", {
  skip_if_no_lz()
  src <- list(
    "app.R"   = "library(shiny)\nshinyApp(fluidPage('x'), function(i, o) {})",
    "utils.R" = "f <- function(x) x + 1"
  )
  files <- decode(shinylive_url(src))
  expect_length(files, 2L)
  got <- stats::setNames(vapply(files, `[[`, character(1), "content"),
                         vapply(files, `[[`, character(1), "name"))
  expect_equal(got[["app.R"]], src[["app.R"]])
  expect_equal(got[["utils.R"]], src[["utils.R"]])
})

test_that("multi-line character vectors are joined with newlines", {
  skip_if_no_lz()
  files <- decode(shinylive_url(list("app.R" = c("line1", "line2"))))
  expect_equal(files[[1]]$content, "line1\nline2")
})

test_that("mode selects the app or editor endpoint", {
  skip_if_no_lz()
  expect_match(shinylive_url("1", mode = "app"),    "shinylive\\.io/r/app/")
  expect_match(shinylive_url("1", mode = "editor"), "shinylive\\.io/r/editor/")
})

test_that("unnamed multi-element input is rejected rather than silently mangled", {
  skip_if_no_lz()
  expect_error(shinylive_url(c("a", "b")), "single string")
})

test_that("the iframe carries both a link and a frame to the same URL", {
  skip_if_no_lz()
  html <- shinylive_iframe("cat(1)", height = "400px")
  expect_match(html, "Open in Shinylive", fixed = TRUE)
  expect_match(html, "<iframe", fixed = TRUE)
  expect_match(html, "height:400px", fixed = TRUE)
  urls <- regmatches(html, gregexpr('https://shinylive\\.io[^"]+', html))[[1]]
  expect_length(unique(urls), 1L)
})
