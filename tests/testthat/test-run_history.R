# tests/testthat/test-run_history.R
#
# Every docs build used to overwrite the previous figures, so "what rebuilt?"
# and "did that get slower?" had no answer. These cover the snapshot file and
# the diff, including the JSON round-trip that broke deduplication the first
# time: jsonlite turns a whole-number `bytes` into an integer, so identical()
# against a freshly built double never matched and every build appended.

hist_cfg <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  list(site_path = dir)
}

hist_data <- function(seconds = c(1, 2), bytes = c(1000, 2000),
                      time = "2026-01-01 10:00:00", names = c("a", "b")) {
  list(
    target_names = names,
    meta = dplyr::tibble(
      name = names, type = "stem", time = time,
      error = NA_character_, warnings = NA_character_,
      seconds = seconds, bytes = bytes
    ),
    manifest = dplyr::tibble(name = names, command = "f()",
                             description = "", pattern = ""),
    network  = list(vertices = dplyr::tibble(name = names, type = "stem"),
                    edges = dplyr::tibble(from = character(), to = character())),
    outdated = NULL, progress = NULL, has_store = TRUE
  )
}

test_that("no history file means no history", {
  expect_equal(read_run_history(hist_cfg()), list())
})

test_that("a snapshot is written and read back", {
  cfg <- hist_cfg()
  suppressMessages(record_run_snapshot(hist_data(), cfg))
  h <- read_run_history(cfg)
  expect_length(h, 1L)
  expect_length(h[[1]]$targets, 2L)
  expect_true(file.exists(file.path(cfg$site_path, "history.json")))
})

test_that("an unchanged pipeline documented twice records one snapshot", {
  # The JSON round-trip regression: comparison must survive int/double drift.
  cfg <- hist_cfg()
  suppressMessages(record_run_snapshot(hist_data(), cfg))
  suppressMessages(record_run_snapshot(hist_data(), cfg))
  expect_length(read_run_history(cfg), 1L)
})

test_that("a changed pipeline appends", {
  cfg <- hist_cfg()
  suppressMessages(record_run_snapshot(hist_data(), cfg))
  suppressMessages(record_run_snapshot(hist_data(time = "2026-01-02 11:00:00"), cfg))
  expect_length(read_run_history(cfg), 2L)
})

test_that("history is capped at max_runs, dropping the oldest", {
  cfg <- hist_cfg()
  for (i in 1:5) {
    suppressMessages(record_run_snapshot(
      hist_data(time = paste0("2026-01-0", i, " 10:00:00")), cfg, max_runs = 3L))
  }
  h <- read_run_history(cfg)
  expect_length(h, 3L)
  expect_equal(h[[1]]$targets[[1]]$last_built, "2026-01-03 10:00:00")
})

test_that("a corrupt history file is reported and restarted, not fatal", {
  cfg <- hist_cfg()
  writeLines("{not json", file.path(cfg$site_path, "history.json"))
  expect_message(h <- read_run_history(cfg), "Could not read run history")
  expect_equal(h, list())
})

# ---- diff ------------------------------------------------------------------

two_runs <- function(second) {
  cfg <- hist_cfg(parent.frame())
  suppressMessages(record_run_snapshot(hist_data(), cfg))
  suppressMessages(record_run_snapshot(second, cfg))
  read_run_history(cfg)
}

test_that("a single snapshot has nothing to diff against", {
  cfg <- hist_cfg()
  suppressMessages(record_run_snapshot(hist_data(), cfg))
  expect_null(diff_run_history(read_run_history(cfg)))
})

test_that("a rebuild is detected from the build time", {
  d <- diff_run_history(two_runs(hist_data(time = "2026-01-02 10:00:00")))
  expect_setequal(d$rebuilt, c("a", "b"))
})

test_that("a target appearing and disappearing is reported", {
  d <- diff_run_history(two_runs(
    hist_data(names = c("a", "c"), seconds = c(1, 2), bytes = c(1000, 2000))))
  expect_equal(d$added, "c")
  expect_equal(d$removed, "b")
})

test_that("a meaningful slowdown is reported and noise is not", {
  # b doubles; a moves 10%, which is a re-run, not a regression.
  d <- diff_run_history(two_runs(hist_data(seconds = c(1.1, 4))))
  expect_length(d$slower, 1L)
  expect_match(d$slower, "^b: ")
  expect_match(d$slower, "\\+100%")
})

test_that("a speed-up is reported separately from a slowdown", {
  d <- diff_run_history(two_runs(hist_data(seconds = c(1, 1))))
  expect_match(d$faster, "^b: ")
  expect_length(d$slower, 0L)
})

test_that("growth and shrinkage are reported on size too", {
  d <- diff_run_history(two_runs(hist_data(bytes = c(1000, 8000))))
  expect_match(d$grew, "^b: ")
  expect_length(d$shrank, 0L)
})

test_that("a status change is spelled out both ways", {
  second <- hist_data()
  second$meta$error <- c(NA_character_, "boom")
  d <- diff_run_history(two_runs(second))
  expect_match(d$status_changed, "b: uptodate -> errored")
})

test_that("a target with no timing recorded is not reported as a change", {
  d <- diff_run_history(two_runs(hist_data(seconds = c(NA_real_, NA_real_))))
  expect_length(d$slower, 0L)
  expect_length(d$faster, 0L)
})
