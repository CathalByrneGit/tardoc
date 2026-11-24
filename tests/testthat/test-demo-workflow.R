# tests/testthat/test-demo-workflow.R
#
# The live demo and the workflow template both depend on a few things that
# live outside R: a committed overview note, and a step that restores the
# previous deploy's history.json. A deploy starts from a fresh checkout, so
# without that step "Build history" never has a second build to draw. Neither
# can be exercised without GitHub, so these pin that they are present and in
# the right order.

example_dir <- function() system.file("examples", "station-monitoring", package = "tardoc")

test_that("the example ships its own project overview", {
  f <- file.path(example_dir(), "tardoc", "notes", "index.md")
  expect_true(file.exists(f))
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_gt(nchar(trimws(gsub("<!--.*?-->", "", txt))), 100L)
})

test_that("the template restores the history before documenting", {
  y <- paste(readLines(system.file("templates", "pipeline-docs.yaml", package = "tardoc"),
                       warn = FALSE), collapse = "\n")
  restore  <- regexpr("name: Restore the build history", y, fixed = TRUE)[1]
  document <- regexpr("name: Generate the documentation", y, fixed = TRUE)[1]
  expect_gt(restore, 0L)
  expect_lt(restore, document)
  # A 404 (the first deploy) must not fail the job.
  expect_match(y, "|| rm -f tardoc/history.json", fixed = TRUE)
  expect_match(y, "/history.json", fixed = TRUE)
})
