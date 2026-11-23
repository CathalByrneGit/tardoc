# tests/testthat/test-regressions-docs.R
#
# Six defects found by running the package against awkward-but-ordinary
# projects rather than the tidy fixtures: a partly built store, edited
# descriptions, subfolders under R/, a pipeline never run, an LLM description
# beside the user's own quotes, and a large file.

cfg_for <- function(tmp, ...) { cfg <- build_site_config(tmp, ...); setup_site_dirs(cfg); cfg }
mocked_docs <- function(env = parent.frame()) {
  local_mocked_bindings(get_fn_docs = function(...) "## Description\n\nA helper.",
                        .package = "tardoc", .env = env)
}

# ---- 1. a target with no metadata row ---------------------------------------

test_that("analytics data copes with a target missing from tar_meta()", {
  # After tar_make(names = "a") only `a` has a row; documenting then stopped
  # with "argument is of length zero".
  tmp <- withr::local_tempdir(); cfg <- cfg_for(tmp)
  td  <- mock_targets_data(has_store = TRUE)
  td$meta <- td$meta[td$meta$name == "raw_data", , drop = FALSE]

  rows <- NULL
  expect_no_error(rows <- .build_analytics_data(td, character(), cfg))
  status <- stats::setNames(vapply(rows$targets, `[[`, "", "status"),
                            vapply(rows$targets, `[[`, "", "name"))
  expect_identical(status[["report"]], "unbuilt")
})

test_that("generate_analytics_data and the DuckDB tables share the same guard", {
  tmp <- withr::local_tempdir(); cfg <- cfg_for(tmp)
  td  <- mock_targets_data(has_store = TRUE)
  td$meta <- td$meta[td$meta$name == "raw_data", , drop = FALSE]
  expect_no_error(suppressMessages(generate_analytics_data(td, character(), cfg)))
})

# ---- 2. a description edited in _targets.R ----------------------------------

test_that("an edited description reaches an existing page", {
  tmp <- withr::local_tempdir(); path <- file.path(tmp, "t.md")
  gen <- "<!-- tardoc:generated -->\nbody\n<!-- tardoc:end -->\n"
  .write_generated_md(path, "# Target: a", "first", gen)
  .write_generated_md(path, "# Target: a", "second", gen)
  expect_identical(readLines(path)[3], "> second")
})

test_that("a refresh leaves anything the user put above the markers alone", {
  tmp <- withr::local_tempdir(); path <- file.path(tmp, "t.md")
  gen <- "<!-- tardoc:generated -->\nbody\n<!-- tardoc:end -->\n"
  writeLines(c("# Target: a", "", "> first", "", "My own preamble.", "",
               "<!-- tardoc:generated -->", "old", "<!-- tardoc:end -->"), path)
  .write_generated_md(path, "# Target: a", "second", gen)
  out <- paste(readLines(path), collapse = "\n")
  expect_match(out, "My own preamble.", fixed = TRUE)
  expect_match(out, "> first", fixed = TRUE)   # not ours to rewrite
})

test_that("a run with no description keeps one an LLM wrote earlier", {
  tmp <- withr::local_tempdir(); path <- file.path(tmp, "t.md")
  gen <- "<!-- tardoc:generated -->\nbody\n<!-- tardoc:end -->\n"
  .write_generated_md(path, "# Target: a", NA_character_, gen)
  .inject_description(path, "a", "Wrote by model.")
  .write_generated_md(path, "# Target: a", NA_character_, gen)
  expect_identical(readLines(path)[3], "> Wrote by model.")
})

test_that("a multi-line description stays one blockquote line", {
  tmp <- withr::local_tempdir(); path <- file.path(tmp, "t.md")
  .write_generated_md(path, "# Target: a", "line one\nline two",
                      "<!-- tardoc:generated -->\nb\n<!-- tardoc:end -->\n")
  expect_identical(readLines(path)[3], "> line one line two")
})

# ---- 3. llm injection and the user's own quotes -----------------------------

test_that("injecting a description does not delete the user's blockquotes", {
  tmp <- withr::local_tempdir(); path <- file.path(tmp, "t.md")
  writeLines(c("# Target: a", "", "<!-- tardoc:generated -->", "body",
               "<!-- tardoc:end -->", "", "## My notes", "",
               "> a quote I wrote myself", "", "end"), path)
  .inject_description(path, "a", "Generated sentence.")
  out <- readLines(path)
  expect_true("> a quote I wrote myself" %in% out)
  expect_identical(out[3], "> Generated sentence.")
})

test_that("injecting twice replaces rather than stacks", {
  tmp <- withr::local_tempdir(); path <- file.path(tmp, "t.md")
  writeLines(c("# Target: a", "", "<!-- tardoc:generated -->", "x", "<!-- tardoc:end -->"), path)
  .inject_description(path, "a", "One.")
  .inject_description(path, "a", "Two.")
  expect_identical(sum(startsWith(readLines(path), "> ")), 1L)
  expect_identical(readLines(path)[3], "> Two.")
})

# ---- 4. functions called, without a store -----------------------------------

test_that("a target page lists the functions it calls before any tar_make()", {
  tmp <- withr::local_tempdir(); cfg <- cfg_for(tmp)
  suppressMessages(generate_all_target_pages(mock_targets_data(has_store = FALSE), cfg))
  page <- paste(readLines(file.path(cfg$targets_dir, "clean_data.md")), collapse = "\n")
  expect_match(page, "functions/clean_raw.md", fixed = TRUE)
  expect_no_match(page, "No distinct functions identified")
})

# ---- 5. subfolders under R/ -------------------------------------------------

test_that(".function_r_files finds files in subfolders, either case of extension", {
  tmp <- withr::local_tempdir(); cfg <- cfg_for(tmp)
  dir.create(file.path(tmp, "R", "ingest"), recursive = TRUE)
  file.create(file.path(tmp, "R", c("a.R", "b.r")), file.path(tmp, "R", "ingest", "c.R"))
  file.create(file.path(tmp, "R", "notes.md"))
  expect_setequal(basename(.function_r_files(cfg)), c("a.R", "b.r", "c.R"))
})

test_that("functions in R/ subfolders get pages and a correct repo link", {
  tmp <- withr::local_tempdir()
  cfg <- cfg_for(tmp, repo_url = "https://github.com/u/r/blob/main/")
  write_mock_r_file(file.path(tmp, "R", "ingest"), "read.R")
  mocked_docs()
  suppressMessages(generate_all_function_pages(cfg))
  page <- paste(readLines(file.path(cfg$functions_dir, "add.md")), collapse = "\n")
  expect_match(page, "blob/main/R/ingest/read.R#L", fixed = TRUE)
})

# ---- 6. one roxygen pass per file -------------------------------------------

test_that("get_fn_docs parses a file once however many functions ask", {
  tmp <- withr::local_tempdir(); f <- write_mock_r_file(tmp, "x.R")
  calls <- 0L
  local_mocked_bindings(
    .file_to_rd = function(file) { calls <<- calls + 1L; list("add.Rd" = "\\name{add}\\title{t}") },
    .package = "tardoc")
  suppressWarnings({ get_fn_docs("add", f); get_fn_docs("add", f); get_fn_docs("add", f) })
  expect_identical(calls, 1L)
})

test_that("an edited file is not served from the cache", {
  tmp <- withr::local_tempdir(); f <- write_mock_r_file(tmp, "y.R")
  calls <- 0L
  local_mocked_bindings(
    .file_to_rd = function(file) { calls <<- calls + 1L; list() }, .package = "tardoc")
  suppressWarnings(get_fn_docs("add", f))
  cat("# changed\n", file = f, append = TRUE)
  suppressWarnings(get_fn_docs("add", f))
  expect_identical(calls, 2L)
})

# ---- the title lands in HTML, so it is escaped -------------------------------

test_that(".html_escape handles the four characters that break markup", {
  expect_identical(.html_escape("A <b>&</b> \"B\""), "A &lt;b&gt;&amp;&lt;/b&gt; &quot;B&quot;")
})

test_that("a project title with markup does not reach the viewer unescaped", {
  tmp <- withr::local_tempdir(); cfg <- cfg_for(tmp)
  suppressMessages(generate_viewer(mock_targets_data(), character(), cfg, "Q3 <script>x</script> & co"))
  html <- paste(readLines(file.path(cfg$site_path, "viewer.html"), warn = FALSE), collapse = "\n")
  expect_match(html, "<title>Q3 &lt;script&gt;x&lt;/script&gt; &amp; co</title>", fixed = TRUE)
})

# ---- no sourcing of user code in the LLM and llms.txt paths ------------------

test_that("llms.txt lists functions without running the project's top-level code", {
  tmp <- withr::local_tempdir(); cfg <- cfg_for(tmp)
  # Forward slashes: the path is written into R source as a string literal, and
  # on Windows "C:\\Users\\..." is an invalid escape that stops the file parsing --
  # which emptied the function list and failed this test for the wrong reason.
  marker <- file.path(normalizePath(tmp, winslash = "/"), "ran.txt")
  dir.create(file.path(tmp, "R"))
  writeLines(c("add <- function(x, y) x + y",
               sprintf("writeLines('x', '%s')", marker)), file.path(tmp, "R", "f.R"))
  mocked_docs()
  suppressMessages(generate_llms_txt(mock_targets_data(), cfg, project_title = "t", project_desc = ""))
  expect_false(file.exists(marker))
  expect_match(paste(readLines(file.path(tmp, "llms.txt")), collapse = "\n"), "`add`", fixed = TRUE)
})

# ---- descriptions an LLM wrote reach every output ---------------------------

test_that("a description on a page is folded into the data the outputs read", {
  tmp <- withr::local_tempdir(); cfg <- cfg_for(tmp)
  td <- mock_targets_data()
  suppressMessages(generate_all_target_pages(td, cfg))
  .inject_description(file.path(cfg$targets_dir, "model_fit.md"), "model_fit", "Fits the model.")
  merged <- .merge_page_descriptions(td, cfg)
  expect_identical(merged$manifest$description[merged$manifest$name == "model_fit"], "Fits the model.")
  # The pipeline's own description is never replaced by a page's.
  expect_identical(merged$manifest$description[merged$manifest$name == "raw_data"], "Raw sensor readings")
})

test_that("the search index carries a description that only the page had", {
  tmp <- withr::local_tempdir(); cfg <- cfg_for(tmp)
  td <- mock_targets_data()
  suppressMessages(generate_all_target_pages(td, cfg))
  .inject_description(file.path(cfg$targets_dir, "model_fit.md"), "model_fit", "Fits the model.")
  td <- .merge_page_descriptions(td, cfg)
  suppressMessages(generate_search_index(td, character(), cfg))
  idx <- jsonlite::fromJSON(file.path(cfg$site_path, "search_index.json"), simplifyVector = FALSE)
  d <- vapply(idx$targets, function(t) t$description, "")
  names(d) <- vapply(idx$targets, `[[`, "", "name")
  expect_identical(d[["model_fit"]], "Fits the model.")
})

test_that("document_targets builds the LLM pass before the outputs that read descriptions", {
  src <- paste(deparse(document_targets), collapse = "\n")
  pos <- function(x) regexpr(x, src, fixed = TRUE)[1]
  expect_lt(pos("generate_llm_content("), pos("generate_search_index("))
  expect_lt(pos(".merge_page_descriptions("), pos("generate_search_index("))
  expect_lt(pos(".merge_page_descriptions("), pos("generate_llms_txt("))
})

# ---- one description extractor -----------------------------------------------

test_that(".docs_description reads the Description section and nothing else", {
  md <- "# T\n\n## Description\n\nDoes a thing.\nOver two lines.\n\n## Arguments\n\n* `x`: y"
  expect_identical(.docs_description(md), "Does a thing.\nOver two lines.")
  expect_identical(.docs_description("# T\n\n## Value\n\nv"), "")
  expect_identical(.extract_description("# T\n\n## Value\n\nv"), "_No description._")
})
