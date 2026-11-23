# tests/testthat/test-target_outputs.R
#
# A report target -- tar_render(), tar_quarto(), or any file target that writes
# an HTML or PDF -- is `format = "file"` and its recorded paths include the
# output. Publishing is opt-in (`reports =`), copies the output with its
# supporting folders into tardoc/reports/<target>/, and links it from the
# target's page and the viewer, only for a target that built without error.

# A project on disk plus the tar_meta()-shaped data describing it. Paths are
# relative to the project, as targets records them.
local_report_project <- function(env = parent.frame()) {
  tmp <- withr::local_tempdir(.local_envir = env)
  cfg <- build_site_config(tmp); setup_site_dirs(cfg)
  dir.create(file.path(tmp, "out", "rep_files"), recursive = TRUE)
  writeLines("<html>report</html>", file.path(tmp, "out", "rep.html"))
  writeLines("fig", file.path(tmp, "out", "rep_files", "fig.png"))
  writeLines("# src", file.path(tmp, "rep.Rmd"))
  writeLines("%PDF-1.4", file.path(tmp, "out", "paper.pdf"))
  writeLines("a,b", file.path(tmp, "out", "data.csv"))

  meta <- dplyr::tibble(
    name   = c("rep", "paper", "data_csv", "plain", "broken", "outside"),
    type   = "stem",
    format = c("file", "file", "file", "rds", "file", "file"),
    time   = "2026-01-01 00:00:00",
    error  = c(NA, NA, NA, NA, "boom", NA)
  )
  meta$path <- list(c("out/rep.html", "rep.Rmd", "out/rep_files"), "out/paper.pdf",
                    "out/data.csv", NA_character_, "out/rep.html",
                    c("../escape.html", "/etc/hostname"))
  td <- list(meta = meta, target_names = meta$name, has_store = TRUE,
             outdated = NULL, manifest = dplyr::tibble(name = meta$name))
  list(cfg = cfg, td = td, tmp = tmp)
}

test_that("only built, error-free file targets with a browser-openable output are candidates", {
  p <- local_report_project()
  cand <- .report_candidates(p$td, p$cfg)
  expect_setequal(names(cand), c("rep", "paper"))      # not csv, rds, errored or outside
  expect_identical(cand$rep$file, "out/rep.html")
  expect_identical(cand$rep$dirs, "out/rep_files")
  expect_identical(cand$paper$file, "out/paper.pdf")
})

test_that("a path that leaves the project is never a candidate", {
  p <- local_report_project()
  writeLines("<html/>", file.path(dirname(p$tmp), "escape.html"))
  withr::defer(unlink(file.path(dirname(p$tmp), "escape.html")))
  expect_false("outside" %in% names(.report_candidates(p$td, p$cfg)))
})

test_that("a target that has not built is not a candidate", {
  p <- local_report_project()
  p$td$has_store <- FALSE
  expect_length(.report_candidates(p$td, p$cfg), 0L)
})

test_that("a missing output file means no report", {
  p <- local_report_project()
  unlink(file.path(p$tmp, "out", "rep.html"))
  expect_false("rep" %in% names(.report_candidates(p$td, p$cfg)))
})

test_that("HTML is preferred over PDF when a render made both", {
  p <- local_report_project()
  writeLines("%PDF", file.path(p$tmp, "out", "rep.pdf"))
  p$td$meta$path[[1]] <- c("out/rep.pdf", "out/rep.html", "out/rep_files")
  expect_identical(.report_candidates(p$td, p$cfg)$rep$file, "out/rep.html")
})

test_that("an outdated target is still a candidate, and is marked stale", {
  p <- local_report_project(); p$td$outdated <- "rep"
  td <- .publish_reports(p$td, p$cfg, TRUE)
  expect_true(td$reports$rep$stale)
  expect_false(td$reports$paper$stale)
})

# ---- the reports argument ----------------------------------------------------

test_that("reports = FALSE publishes nothing and writes nothing", {
  p <- local_report_project()
  td <- .publish_reports(p$td, p$cfg, FALSE)
  expect_length(td$reports, 0L)
  expect_false(dir.exists(file.path(p$cfg$site_path, "reports")))
})

test_that("reports = TRUE copies the output and its supporting folder", {
  p <- local_report_project()
  td <- suppressMessages(.publish_reports(p$td, p$cfg, TRUE))
  d <- file.path(p$cfg$site_path, "reports")
  expect_true(file.exists(file.path(d, "rep", "rep.html")))
  expect_true(file.exists(file.path(d, "rep", "rep_files", "fig.png")))
  expect_true(file.exists(file.path(d, "paper", "paper.pdf")))
  # The source is not published.
  expect_false(file.exists(file.path(d, "rep", "rep.Rmd")))
  expect_identical(td$reports$rep$href, "reports/rep/rep.html")
  expect_identical(td$reports$paper$type, "pdf")
})

test_that("a vector of names publishes only those", {
  p <- local_report_project()
  td <- suppressMessages(.publish_reports(p$td, p$cfg, "paper"))
  expect_named(td$reports, "paper")
  expect_false(dir.exists(file.path(p$cfg$site_path, "reports", "rep")))
})

test_that("a name that is not a target warns; one that cannot publish says why", {
  p <- local_report_project()
  expect_warning(suppressMessages(.publish_reports(p$td, p$cfg, c("rep", "nope"))), "nope")
  expect_message(.publish_reports(p$td, p$cfg, c("broken")), "Not published")
})

test_that("reports must be TRUE, FALSE or names", {
  p <- local_report_project()
  expect_error(.publish_reports(p$td, p$cfg, 3), "must be TRUE, FALSE")
})

test_that("turning reports off removes what an earlier run published", {
  p <- local_report_project()
  suppressMessages(.publish_reports(p$td, p$cfg, TRUE))
  expect_true(dir.exists(file.path(p$cfg$site_path, "reports", "rep")))
  .publish_reports(p$td, p$cfg, FALSE)
  expect_false(dir.exists(file.path(p$cfg$site_path, "reports")))
})

test_that("a folder called reports that tardoc did not make is never touched", {
  p <- local_report_project()
  mine <- file.path(p$cfg$site_path, "reports"); dir.create(mine)
  writeLines("keep", file.path(mine, "notes.txt"))
  .publish_reports(p$td, p$cfg, FALSE)
  expect_true(file.exists(file.path(mine, "notes.txt")))
})

test_that("republishing replaces a report rather than accumulating", {
  p <- local_report_project()
  suppressMessages(.publish_reports(p$td, p$cfg, TRUE))
  writeLines("<html>v2</html>", file.path(p$tmp, "out", "rep.html"))
  suppressMessages(.publish_reports(p$td, p$cfg, "rep"))
  expect_match(readLines(file.path(p$cfg$site_path, "reports", "rep", "rep.html")), "v2")
  expect_false(dir.exists(file.path(p$cfg$site_path, "reports", "paper")))
})

test_that("a large total warns", {
  p <- local_report_project()
  expect_warning(suppressMessages(.publish_reports(p$td, p$cfg, TRUE, warn_mb = 1e-6)), "total")
})

# ---- where it shows up ------------------------------------------------------

test_that("the Output section links relative to the target page, and says when stale", {
  rep <- list(href = "reports/rep/rep.html", type = "html", bytes = 2048, stale = TRUE)
  out <- .output_section("rep", rep)
  expect_match(out, "[Open report](../reports/rep/rep.html)", fixed = TRUE)
  expect_match(out, "Out of date")
  expect_match(.output_section("p", list(href = "reports/p/p.pdf", type = "pdf", bytes = 1, stale = FALSE)),
               "Open PDF", fixed = TRUE)
  expect_identical(.output_section("x", NULL), "")
})

test_that("a published report appears on the target's page, a plain target's has none", {
  p <- local_report_project()
  td <- suppressMessages(.publish_reports(p$td, p$cfg, TRUE))
  td$manifest <- dplyr::tibble(name = td$target_names, command = "f()", pattern = NA_character_,
                               description = NA_character_)
  td$network <- list(vertices = dplyr::tibble(name = td$target_names, type = "stem"),
                     edges = dplyr::tibble(from = character(), to = character()))
  suppressMessages(generate_all_target_pages(td, p$cfg))
  expect_match(paste(readLines(file.path(p$cfg$targets_dir, "rep.md")), collapse = "\n"),
               "## Output", fixed = TRUE)
  expect_no_match(paste(readLines(file.path(p$cfg$targets_dir, "plain.md")), collapse = "\n"),
                  "## Output", fixed = TRUE)
})

test_that("the viewer payload is an object, empty when nothing is published", {
  expect_identical(as.character(jsonlite::toJSON(.reports_payload(NULL), auto_unbox = TRUE)), "{}")
  json <- as.character(jsonlite::toJSON(
    .reports_payload(list(rep = list(href = "reports/rep/rep.html", type = "html", bytes = 9, stale = FALSE))),
    auto_unbox = TRUE))
  expect_match(json, '"rep":{"href":"reports/rep/rep.html","type":"html","stale":false}', fixed = TRUE)
})

test_that("the viewer turns the page link into a new-tab button and rewrites its path", {
  s <- paste(readLines(system.file("templates", "viewer.html", package = "tardoc"), warn = FALSE), collapse = "\n")
  expect_match(s, "href.indexOf('../reports/') !== 0", fixed = TRUE)
  expect_match(s, "a.classList.add('report-btn')", fixed = TRUE)
  expect_match(s, "const REPORTS  = {{REPORTS_JSON}};", fixed = TRUE)
  expect_match(s, "REPORTS[n.id]", fixed = TRUE)
})

# ---- end to end, against a real store ------------------------------------------

test_that("document_targets publishes a real report target and skips a failing one", {
  skip_if_not_installed("targets")
  d <- withr::local_tempdir()
  writeLines(c(
    "library(targets)",
    "list(",
    "  tar_target(report, {",
    "    dir.create('out/report_files', recursive = TRUE, showWarnings = FALSE)",
    "    writeLines('<html>r</html>', 'out/report.html')",
    "    writeLines('x', 'out/report_files/a.txt')",
    "    c('out/report.html', 'out/report_files')",
    "  }, format = 'file'),",
    "  tar_target(failing, { stop('no') }, format = 'file', error = 'continue')",
    ")"), file.path(d, "_targets.R"))
  withr::with_dir(d, suppressMessages(try(
    targets::tar_make(callr_function = NULL, reporter = "silent"), silent = TRUE)))

  suppressMessages(document_targets(d, check_outdated = FALSE, reports = TRUE))
  expect_true(file.exists(file.path(d, "tardoc", "reports", "report", "report.html")))
  expect_true(file.exists(file.path(d, "tardoc", "reports", "report", "report_files", "a.txt")))
  expect_false(dir.exists(file.path(d, "tardoc", "reports", "failing")))
  expect_match(paste(readLines(file.path(d, "tardoc", "targets", "report.md")), collapse = "\n"),
               "Open report", fixed = TRUE)
  idx <- jsonlite::fromJSON(file.path(d, "tardoc", "search_index.json"), simplifyVector = FALSE)
  out <- vapply(idx$targets, function(t) t$output, "")
  names(out) <- vapply(idx$targets, `[[`, "", "name")
  expect_identical(out[["report"]], "reports/report/report.html")
  expect_match(paste(readLines(file.path(d, "llms.txt")), collapse = "\n"),
               "**Output:** tardoc/reports/report/report.html", fixed = TRUE)

  suppressMessages(document_targets(d, check_outdated = FALSE))     # default: off
  expect_false(dir.exists(file.path(d, "tardoc", "reports")))
})
