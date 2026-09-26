# tests/testthat/test-pipeline-docs-workflow.R
#
# The workflow users copy into their own pipeline repository ships inside the
# package, so it has to survive R CMD build and stay findable by name. A typo
# here is invisible until someone's CI fails.

wf_path <- function() {
  system.file("templates", "pipeline-docs.yaml", package = "tardoc")
}

test_that("the workflow template is installed with the package", {
  expect_true(nzchar(wf_path()))
  expect_true(file.exists(wf_path()))
})

test_that("it publishes the directory document_targets() actually writes", {
  wf <- readLines(wf_path(), warn = FALSE)
  expect_true(any(grepl("document_targets\\(", wf)))
  expect_true(any(grepl("^\\s+path: tardoc\\s*$", wf)))
  # Pages serves index.html at the root; viewer.html alone gives a 404.
  expect_true(any(grepl("tardoc/index.html", wf, fixed = TRUE)))
})

test_that("it requests the permissions a Pages deploy needs", {
  wf <- paste(readLines(wf_path(), warn = FALSE), collapse = "\n")
  for (perm in c("pages: write", "id-token: write")) {
    expect_match(wf, perm, fixed = TRUE)
  }
})

test_that("the staleness job compares without running the pipeline", {
  # tar_make() in the staleness job would rewrite timestamps on every run and
  # the comparison would never pass.
  wf <- readLines(wf_path(), warn = FALSE)
  stale_at <- grep("^  stale:", wf)
  expect_length(stale_at, 1L)
  job <- wf[stale_at:length(wf)]
  job <- job[!grepl("^\\s*#", job)]   # the comment saying so is not a call
  expect_false(any(grepl("tar_make", job)))
})
