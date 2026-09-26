# tests/testthat/test-target_branches.R
#
# A node saying "200 branches" answers the wrong question. tar_meta() already
# returns a row per branch with its own seconds, bytes and error, keyed by
# `parent`; these pin that they are found, ordered and summarised, and that a
# failing branch is never hidden behind a row limit.

branched_meta <- function(n = 3, errors = integer()) {
  kids <- paste0("chunk_", sprintf("%02d", seq_len(n)))
  parent <- dplyr::tibble(
    name = "chunk", type = "pattern", parent = NA_character_,
    children = list(kids), seconds = NA_real_, bytes = NA_real_,
    error = NA_character_, warnings = NA_character_
  )
  if (n == 0) return(parent[0, ])
  branches <- dplyr::tibble(
    name = kids, type = "branch", parent = "chunk",
    children = vector("list", n),
    seconds = seq_len(n) / 1000, bytes = rep(100, n),
    error = as.character(ifelse(seq_len(n) %in% errors, "boom", NA_character_)),
    warnings = NA_character_
  )
  dplyr::bind_rows(parent, branches)
}

test_that("branch rows are found by parent", {
  b <- tardoc:::.target_branches("chunk", branched_meta(3))
  expect_equal(nrow(b), 3L)
  expect_equal(b$index, 1:3)
  expect_true(all(b$status == "uptodate"))
})

test_that("a target with no branches yields no rows", {
  expect_equal(nrow(tardoc:::.target_branches("nope", branched_meta(3))), 0L)
})

test_that("meta without a parent column is handled", {
  m <- dplyr::tibble(name = "a", type = "stem")
  expect_equal(nrow(tardoc:::.target_branches("a", m)), 0L)
})

test_that("branches follow the parent's declared order, not row order", {
  # "branch 3 of 200" only means something against the declared order, and
  # tar_meta() does not promise to return them in it.
  m <- branched_meta(3)
  m <- m[c(1, 4, 2, 3), ]           # shuffle the branch rows
  b <- tardoc:::.target_branches("chunk", m)
  expect_equal(b$name, c("chunk_01", "chunk_02", "chunk_03"))
  expect_equal(b$index, 1:3)
})

test_that("a failing branch is marked errored and carries its message", {
  b <- tardoc:::.target_branches("chunk", branched_meta(4, errors = 2))
  expect_equal(b$status, c("uptodate", "errored", "uptodate", "uptodate"))
  expect_equal(b$error[2], "boom")
})

test_that("the summary totals the branches and names the slowest", {
  s <- tardoc:::.branch_summary(tardoc:::.target_branches("chunk", branched_meta(3)))
  expect_equal(s$n, 3L)
  expect_equal(s$n_errored, 0L)
  expect_equal(s$seconds, 0.006)
  expect_equal(s$bytes, 300)
  expect_equal(s$slowest, 3L)        # seconds increase with index
})

test_that("the summary of no branches is empty, not an error", {
  s <- tardoc:::.branch_summary(tardoc:::.target_branches("x", branched_meta(0)))
  expect_equal(s$n, 0L)
  expect_true(is.na(s$slowest))
})

test_that("the section reports the error count in its first line", {
  sec <- tardoc:::.branches_section(
    tardoc:::.target_branches("chunk", branched_meta(5, errors = c(1, 4)))
  )
  expect_match(sec, "5 branches")
  expect_match(sec, "2 errored")
})

test_that("failing branches are always listed, however many there are", {
  # 200 branches must not put 200 rows on the page, but the three that failed
  # can never be the ones truncated away.
  b   <- tardoc:::.target_branches("chunk", branched_meta(200, errors = c(150, 199)))
  sec <- tardoc:::.branches_section(b, max_rows = 5L)
  expect_match(sec, "\\| 150 \\|")
  expect_match(sec, "\\| 199 \\|")
  expect_match(sec, "193 further branches not listed")
})

test_that("a clean target gets no branches section", {
  expect_identical(
    tardoc:::.branches_section(tardoc:::.target_branches("x", branched_meta(0))),
    ""
  )
})
