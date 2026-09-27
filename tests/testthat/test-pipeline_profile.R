# tests/testthat/test-pipeline_profile.R
#
# seconds and bytes were in tar_meta() all along and nothing ranked them. The
# critical path is the ranking that matters for optimising: no amount of
# parallelism makes a run shorter than its longest dependency chain.

test_that("the critical path follows weight, not hop count", {
  # a -> b -> d is three hops and 3s; a -> c -> d is three hops and 21s.
  nodes <- data.frame(name = c("a", "b", "c", "d"), seconds = c(1, 1, 20, 1))
  edges <- data.frame(from = c("a", "a", "b", "c"), to = c("b", "c", "d", "d"))
  expect_equal(critical_path(nodes, edges), c("a", "c", "d"))
})

test_that("ties are broken toward the longer chain", {
  # A zero-second sink ties with its parent. Stopping there would draw a chain
  # that does not reach the end of the pipeline.
  nodes <- data.frame(name = c("a", "b", "sink"), seconds = c(5, 1, 0))
  edges <- data.frame(from = c("a", "b"), to = c("b", "sink"))
  expect_equal(critical_path(nodes, edges), c("a", "b", "sink"))
})

test_that("targets with no recorded runtime count as zero, not as missing", {
  nodes <- data.frame(name = c("a", "b"), seconds = c(NA_real_, 3))
  edges <- data.frame(from = "a", to = "b")
  expect_equal(critical_path(nodes, edges), c("a", "b"))
})

test_that("an empty pipeline yields an empty path", {
  expect_equal(
    critical_path(data.frame(name = character(), seconds = numeric()),
                  data.frame(from = character(), to = character())),
    character()
  )
})

test_that("a single node is its own path", {
  expect_equal(
    critical_path(data.frame(name = "only", seconds = 1),
                  data.frame(from = character(), to = character())),
    "only"
  )
})

test_that("a cyclic edge list terminates instead of looping", {
  # Impossible in a targets pipeline; a malformed edge list must not hang.
  nodes <- data.frame(name = c("a", "b"), seconds = c(1, 1))
  edges <- data.frame(from = c("a", "b"), to = c("b", "a"))
  expect_silent(p <- critical_path(nodes, edges))
  expect_type(p, "character")
})

test_that("edges naming unknown nodes are ignored", {
  nodes <- data.frame(name = c("a", "b"), seconds = c(1, 2))
  edges <- data.frame(from = c("a", "ghost"), to = c("b", "b"))
  expect_equal(critical_path(nodes, edges), c("a", "b"))
})

# ---- pipeline_profile ------------------------------------------------------

profile_data <- function() {
  list(
    meta = dplyr::tibble(
      name = c("a", "b", "c"), type = "stem",
      time = "2026-01-01", error = NA_character_, warnings = NA_character_,
      seconds = c(1, 10, 0), bytes = c(100, 5000, 0)
    ),
    manifest = dplyr::tibble(name = c("a", "b", "c"),
                             command = "f()", description = "", pattern = ""),
    network = list(
      vertices = dplyr::tibble(name = c("a", "b", "c"), type = "stem"),
      edges    = dplyr::tibble(from = c("a", "b"), to = c("b", "c"))
    ),
    outdated = NULL, progress = NULL, has_store = TRUE,
    target_names = c("a", "b", "c")
  )
}

test_that("the profile ranks by measure, descending", {
  p <- pipeline_profile(profile_data())
  expect_equal(p$slowest$name, c("b", "a"))
  expect_equal(p$largest$name, c("b", "a"))
  expect_equal(p$total_seconds, 11)
  expect_equal(p$total_bytes, 5100)
})

test_that("targets with nothing recorded are left out of the rankings", {
  # c has zero seconds and zero bytes: listing it says nothing.
  p <- pipeline_profile(profile_data())
  expect_false("c" %in% p$slowest$name)
  expect_false("c" %in% p$largest$name)
})

test_that("the critical path and its total come back together", {
  p <- pipeline_profile(profile_data())
  expect_equal(p$critical_path, c("a", "b", "c"))
  expect_equal(p$critical_seconds, 11)
})

test_that("top limits the rankings", {
  expect_equal(nrow(pipeline_profile(profile_data(), top = 1L)$slowest), 1L)
})

test_that("a pipeline with no timings profiles without erroring", {
  td <- profile_data()
  td$meta$seconds <- NA_real_
  td$meta$bytes   <- NA_real_
  p <- pipeline_profile(td)
  expect_equal(nrow(p$slowest), 0L)
  expect_equal(nrow(p$largest), 0L)
  # The path is still meaningful -- every target weighs the same.
  expect_length(p$critical_path, 3L)
})

test_that("functions are excluded from the profile", {
  td <- profile_data()
  td$network$vertices <- dplyr::tibble(name = c("a", "b", "c", "f"),
                                       type = c("stem", "stem", "stem", "function"))
  td$network$edges <- dplyr::tibble(from = c("a", "b", "f"), to = c("b", "c", "a"))
  p <- pipeline_profile(td)
  expect_false("f" %in% p$critical_path)
})
