# tests/testthat/test-generate_llm_content.R
#
# generate_llm_content() talks to an ellmer Chat object. These tests drive it
# with a stub that records the prompts it is given and returns canned text, so
# the injection logic is covered without a network call or an API key.

stub_chat <- function(reply = "Cleans and returns the data.", fail_items = FALSE) {
  self <- new.env(parent = emptyenv())
  self$prompts <- character()
  self$calls <- 0L
  self$turns_reset <- 0L
  self$set_turns <- function(turns) {
    self$turns_reset <- self$turns_reset + 1L
    invisible(NULL)
  }
  self$chat <- function(prompt, ...) {
    self$calls <- self$calls + 1L
    self$prompts <- c(self$prompts, prompt)
    # The priming call carries the system prompt; everything else is an item.
    if (fail_items && !startsWith(prompt, "[SYSTEM CONTEXT]")) stop("provider exploded")
    reply
  }
  class(self) <- "stub_chat"
  self
}

# A project with target pages and function pages already written, which is the
# state generate_llm_content() expects to edit.
local_documented <- function(env = parent.frame()) {
  tmp <- withr::local_tempdir(.local_envir = env)
  cfg <- mock_cfg(tmp)
  setup_site_dirs(cfg)
  write_mock_r_file(cfg$r_scripts_dir)
  td <- mock_targets_data()
  suppressMessages(generate_all_target_pages(td, cfg))
  suppressMessages(generate_all_function_pages(cfg))
  list(cfg = cfg, td = td)
}

test_that("only undescribed targets are sent to the model", {
  skip_if_not_installed("ellmer")
  d  <- local_documented()
  ch <- stub_chat()
  suppressMessages(
    generate_llm_content(d$td, character(), d$cfg, llm_chat = ch)
  )
  # mock_targets_data has descriptions for raw_data and clean_data, and none
  # for model_fit (NA) and report (""). Only the latter two need generating.
  joined <- paste(ch$prompts, collapse = "\n")
  expect_true(grepl("model_fit", joined))
  expect_true(grepl("report", joined))
  expect_false(grepl("Raw sensor readings", joined))
})

test_that("a generated description is written into the target page", {
  skip_if_not_installed("ellmer")
  d  <- local_documented()
  ch <- stub_chat(reply = "Fits the model and returns coefficients.")
  suppressMessages(
    generate_llm_content(d$td, character(), d$cfg, llm_chat = ch)
  )
  page <- readLines(file.path(d$cfg$targets_dir, "model_fit.md"), warn = FALSE)
  expect_true(any(grepl("Fits the model and returns coefficients.", page, fixed = TRUE)))
})

test_that("a target that already has a description is left alone", {
  skip_if_not_installed("ellmer")
  d  <- local_documented()
  before <- readLines(file.path(d$cfg$targets_dir, "clean_data.md"), warn = FALSE)
  ch <- stub_chat(reply = "SHOULD NOT APPEAR")
  suppressMessages(
    generate_llm_content(d$td, character(), d$cfg, llm_chat = ch)
  )
  after <- readLines(file.path(d$cfg$targets_dir, "clean_data.md"), warn = FALSE)
  expect_false(any(grepl("SHOULD NOT APPEAR", after, fixed = TRUE)))
  expect_identical(before, after)
})

test_that("function explanations are injected into function pages", {
  skip_if_not_installed("ellmer")
  d  <- local_documented()
  ch <- stub_chat(reply = "Adds its two arguments together and returns the sum.")
  suppressMessages(
    generate_llm_content(d$td, "add", d$cfg, llm_chat = ch)
  )
  page <- readLines(file.path(d$cfg$functions_dir, "add.md"), warn = FALSE)
  expect_true(any(grepl("Adds its two arguments together", page, fixed = TRUE)))
})

test_that("the conversation is reset before each batch", {
  skip_if_not_installed("ellmer")
  d  <- local_documented()
  ch <- stub_chat()
  suppressMessages(
    generate_llm_content(d$td, "add", d$cfg, llm_chat = ch)
  )
  # Once for the description batch, once for the explanation batch -- otherwise
  # the second batch inherits the first batch's system prompt and turns.
  expect_gte(ch$turns_reset, 2L)
})

test_that("a per-item provider failure skips that item, not the whole run", {
  skip_if_not_installed("ellmer")
  d  <- local_documented()
  ch <- stub_chat(fail_items = TRUE)
  expect_no_error(suppressMessages(
    generate_llm_content(d$td, "add", d$cfg, llm_chat = ch)
  ))
  page <- readLines(file.path(d$cfg$targets_dir, "model_fit.md"), warn = FALSE)
  expect_false(any(grepl("provider exploded", page, fixed = TRUE)))
})

test_that("an unknown provider is rejected by name", {
  expect_error(
    .make_ellmer_chat("not_a_provider", NULL, NULL, NULL),
    "Unknown provider"
  )
})

# ---- not paying twice ---------------------------------------------------------

test_that("a target already described on its page is not sent to the model again", {
  skip_if_not_installed("ellmer")
  d  <- local_documented()
  .inject_description(file.path(d$cfg$targets_dir, "model_fit.md"), "model_fit", "Kept.")
  ch <- stub_chat()
  suppressMessages(generate_llm_content(d$td, character(), d$cfg, llm_chat = ch))
  expect_false(grepl("'model_fit'", paste(ch$prompts, collapse = "\n"), fixed = TRUE))
  expect_identical(.page_description(file.path(d$cfg$targets_dir, "model_fit.md")), "Kept.")
})

test_that("refresh = TRUE regenerates a description that already exists", {
  skip_if_not_installed("ellmer")
  d  <- local_documented()
  .inject_description(file.path(d$cfg$targets_dir, "model_fit.md"), "model_fit", "Old.")
  ch <- stub_chat(reply = "New sentence.")
  suppressMessages(generate_llm_content(d$td, character(), d$cfg, llm_chat = ch, refresh = TRUE))
  expect_identical(.page_description(file.path(d$cfg$targets_dir, "model_fit.md")), "New sentence.")
})

test_that("an unchanged function's explanation comes from the cache, not the model", {
  skip_if_not_installed("ellmer")
  d  <- local_documented()
  ch <- stub_chat(reply = "Adds two numbers.")
  suppressMessages(generate_llm_content(d$td, "add", d$cfg, llm_chat = ch))
  first <- ch$calls
  suppressMessages(generate_all_function_pages(d$cfg))     # wipes the block, as every run does
  ch2 <- stub_chat(reply = "SHOULD NOT BE ASKED")
  suppressMessages(generate_llm_content(d$td, "add", d$cfg, llm_chat = ch2))
  fn_prompts <- ch2$prompts[!startsWith(ch2$prompts, "[SYSTEM CONTEXT]") & grepl("function 'add'", ch2$prompts, fixed = TRUE)]
  expect_length(fn_prompts, 0L)
  expect_match(paste(readLines(file.path(d$cfg$functions_dir, "add.md")), collapse = "\n"),
               "Adds two numbers.", fixed = TRUE)
})

test_that("an edited function is explained again", {
  skip_if_not_installed("ellmer")
  d  <- local_documented()
  suppressMessages(generate_llm_content(d$td, "add", d$cfg, llm_chat = stub_chat(reply = "v1")))
  f <- file.path(d$cfg$r_scripts_dir, "helpers.R")
  writeLines(sub("x + y", "x + y + 1", readLines(f), fixed = TRUE), f)
  suppressMessages(generate_all_function_pages(d$cfg))
  ch <- stub_chat(reply = "v2")
  suppressMessages(generate_llm_content(d$td, "add", d$cfg, llm_chat = ch))
  expect_match(paste(readLines(file.path(d$cfg$functions_dir, "add.md")), collapse = "\n"), "v2", fixed = TRUE)
})

test_that("a plain rerun restores a cached explanation without a model", {
  skip_if_not_installed("ellmer")
  d <- local_documented()
  suppressMessages(generate_llm_content(d$td, "add", d$cfg, llm_chat = stub_chat(reply = "Adds two numbers.")))
  suppressMessages(generate_all_function_pages(d$cfg))        # a plain run rewrites the page
  page <- file.path(d$cfg$functions_dir, "add.md")
  expect_false(grepl("Adds two numbers.", paste(readLines(page), collapse = "\n"), fixed = TRUE))

  expect_equal(suppressMessages(.restore_cached_explanations("add", d$cfg)), 1L)
  expect_match(paste(readLines(page), collapse = "\n"), "Adds two numbers.", fixed = TRUE)
})

test_that("an edited function gets no stale explanation back", {
  skip_if_not_installed("ellmer")
  d <- local_documented()
  suppressMessages(generate_llm_content(d$td, "add", d$cfg, llm_chat = stub_chat(reply = "v1")))
  f <- file.path(d$cfg$r_scripts_dir, "helpers.R")
  writeLines(sub("x + y", "x + y + 1", readLines(f), fixed = TRUE), f)
  suppressMessages(generate_all_function_pages(d$cfg))
  expect_equal(suppressMessages(.restore_cached_explanations("add", d$cfg)), 0L)
  expect_false(grepl("v1", paste(readLines(file.path(d$cfg$functions_dir, "add.md")), collapse = "\n"), fixed = TRUE))
})

test_that("with no cache, restoring does nothing", {
  d <- local_documented()
  expect_equal(.restore_cached_explanations("add", d$cfg), 0L)
})
