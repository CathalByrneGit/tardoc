test_that("non-ASCII text survives a non-UTF-8 locale end to end", {
  skip_if_not_installed("withr")
  skip_on_cran()
  withr::local_locale(c(LC_CTYPE = "C"))
  dash <- "—"; ae <- "é"

  d <- normalizePath(tempfile("enc"), winslash = "/", mustWork = FALSE)
  dir.create(file.path(d, "R"), recursive = TRUE)
  writeLines(c(paste0("#' Clean ", dash, " drop caf", ae), "#' @param x x",
               "f <- function(x) x"), file.path(d, "R", "f.R"), useBytes = TRUE)
  writeLines(c("library(targets)", "tar_source('R')",
               paste0("list(tar_target(a, f(1), description = 'Reads caf", ae,
                      " ", dash, " data'))")),
             file.path(d, "_targets.R"), useBytes = TRUE)

  withr::with_dir(d, suppressMessages(suppressWarnings(
    document_targets(d, pkg_name = paste0("Caf", ae, " ", dash), check_outdated = FALSE))))

  for (f in c("tardoc/viewer.html", "tardoc/targets/a.md", "llms.txt",
              "tardoc/search_index.json", "tardoc/functions/f.md")) {
    bytes <- readBin(file.path(d, f), "raw", 1e7)
    txt   <- rawToChar(bytes)
    expect_false(grepl("<e2>", txt, fixed = TRUE), info = f)
    expect_true(grepl("\xe2\x80\x94", txt, useBytes = TRUE, fixed = TRUE), info = f)
  }
})

test_that(".read_lines_utf8 strips a BOM and marks UTF-8", {
  p <- tempfile(fileext = ".md")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("caf"), as.raw(c(0xc3, 0xa9)), as.raw(10)), p)
  x <- .read_lines_utf8(p)
  expect_identical(x, "café")
  expect_identical(Encoding(x), "UTF-8")
})
