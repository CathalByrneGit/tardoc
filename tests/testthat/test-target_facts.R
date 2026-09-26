# tests/testthat/test-target_facts.R
#
# Status used to be derived in six places as
# `if (is.na(error)) "uptodate" else "errored"`, which reads "did not error
# last run" rather than "is current". These pin the four-state replacement and
# the fact that the target page and the graph node now describe a target from
# the same call.

fake_data <- function(outdated = NULL, has_store = TRUE, error = NA_character_,
                      warnings = NA_character_, time = "2026-01-01 10:00:00") {
  list(
    meta = dplyr::tibble(
      name = c("a", "b"), type = "stem",
      time = time, error = error, warnings = warnings,
      seconds = c(1.5, NA_real_), bytes = c(2048, NA_real_)
    ),
    manifest = dplyr::tibble(
      name = c("a", "b"),
      command = c("f(x)", "g(a)"),
      description = c("first", ""),
      pattern = c("", ""),
      format = c("rds", "rds"),
      repository = c("local", "local"),
      iteration = c("vector", "vector")
    ),
    network = list(
      vertices = dplyr::tibble(name = c("a", "b"), type = c("stem", "stem")),
      edges    = dplyr::tibble(from = "a", to = "b")
    ),
    outdated  = outdated,
    progress  = dplyr::tibble(name = c("a", "b"), progress = c("built", "skipped")),
    has_store = has_store
  )
}

test_that("status distinguishes stale from merely error-free", {
  td <- fake_data(outdated = "b")
  expect_equal(tardoc:::.target_status("a", td$meta, td$outdated, TRUE), "uptodate")
  expect_equal(tardoc:::.target_status("b", td$meta, td$outdated, TRUE), "outdated")
})

test_that("an error outranks staleness", {
  td <- fake_data(outdated = c("a", "b"), error = "boom")
  expect_equal(tardoc:::.target_status("a", td$meta, td$outdated, TRUE), "errored")
})

test_that("no store means unbuilt, not up to date", {
  td <- fake_data(has_store = FALSE, time = NA_character_)
  expect_equal(tardoc:::.target_status("a", td$meta, NULL, FALSE), "unbuilt")
})

test_that("a NULL outdated vector falls back rather than erroring", {
  # check_outdated = FALSE, or tar_outdated() failed.
  td <- fake_data(outdated = NULL)
  expect_equal(tardoc:::.target_status("a", td$meta, NULL, TRUE), "uptodate")
})

test_that("an unknown target with a store is unbuilt", {
  td <- fake_data()
  expect_equal(tardoc:::.target_status("nope", td$meta, NULL, TRUE), "unbuilt")
})

test_that("labels are human-readable", {
  expect_equal(tardoc:::.status_label("outdated"), "Outdated")
  expect_equal(tardoc:::.status_label("unbuilt"),  "Not built")
  expect_equal(tardoc:::.status_label("weird"),    "weird")
})

test_that("facts carry the fields the page and the panel both need", {
  f <- tardoc:::.target_facts("a", fake_data(outdated = "b"))
  expect_equal(f$status, "uptodate")
  expect_equal(f$status_label, "Up-to-date")
  expect_equal(f$command, "f(x)")
  expect_equal(f$description, "first")
  expect_equal(f$progress, "built")
  expect_equal(f$seconds, 1.5)
  expect_equal(f$bytes, 2048)
  # Absent character fields are "" so templates can use nzchar().
  expect_identical(f$error, "")
  expect_false(f$branched)
})

test_that("the last run is reported separately from status", {
  # "skipped last run" and "current now" are different claims.
  f <- tardoc:::.target_facts("b", fake_data(outdated = "b"))
  expect_equal(f$status, "outdated")
  expect_equal(f$progress, "skipped")
})

test_that("missing progress data does not break facts", {
  td <- fake_data(); td$progress <- NULL
  expect_equal(tardoc:::.target_facts("a", td)$progress, "")
})

test_that("the details table omits defaults but keeps what differs", {
  f <- tardoc:::.target_facts("a", fake_data())
  tbl <- tardoc:::.facts_table(f)
  expect_match(tbl, "Up-to-date")
  expect_match(tbl, "Runtime")
  expect_match(tbl, "Size")
  # repository: local and iteration: vector are true of nearly every target.
  expect_false(grepl("Repository", tbl, fixed = TRUE))
  expect_false(grepl("Iteration", tbl, fixed = TRUE))
})

test_that("warnings reach the page -- they previously surfaced nowhere", {
  td <- fake_data(warnings = "NaNs produced")
  sections <- tardoc:::.facts_sections(tardoc:::.target_facts("a", td))
  expect_match(sections, "## Warnings")
  expect_match(sections, "NaNs produced")
})

test_that("a clean target gets no error or warning sections", {
  expect_identical(tardoc:::.facts_sections(tardoc:::.target_facts("a", fake_data())), "")
})

test_that("formatters match the panel's rendering", {
  expect_equal(tardoc:::.fmt_seconds(0.25), "250 ms")
  expect_equal(tardoc:::.fmt_seconds(2.5),  "2.5 s")
  expect_equal(tardoc:::.fmt_seconds(125),  "2m 5s")
  expect_equal(tardoc:::.fmt_bytes(512),    "512 B")
  expect_equal(tardoc:::.fmt_bytes(2048),   "2.05 kB")
  expect_identical(tardoc:::.fmt_bytes(NA_real_), "")
})

test_that("the graph node and the target page agree on a target", {
  # The whole point of the shared call: the inspect panel used to show a dozen
  # fields the page it linked to did not.
  td    <- fake_data(outdated = "b")
  graph <- build_dag_graph(td)
  node  <- Filter(function(n) n$id == "b", graph$nodes)[[1]]
  facts <- tardoc:::.target_facts("b", td)
  for (k in c("status", "status_label", "command", "description",
              "progress", "warnings", "branched", "n_branches")) {
    expect_identical(node[[k]], facts[[k]], info = k)
  }
})
