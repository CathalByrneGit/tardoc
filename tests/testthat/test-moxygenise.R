# tests/testthat/test-moxygenise.R

# ---- .list_r_files ----------------------------------------------------------

test_that(".list_r_files finds R files recursively", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "sub"), recursive = TRUE)
  file.create(file.path(tmp, "a.R"))
  file.create(file.path(tmp, "sub", "b.R"))
  file.create(file.path(tmp, "notes.txt"))

  result <- tardoc:::.list_r_files(tmp)
  expect_length(result, 2)
  expect_true(all(endsWith(result, ".R")))
})

test_that(".list_r_files errors on non-existent path", {
  expect_error(tardoc:::.list_r_files("/does/not/exist"))
})

# ---- .file_to_rd ------------------------------------------------------------

test_that(".file_to_rd returns named list of Rd strings", {
  tmp  <- withr::local_tempdir()
  path <- write_mock_r_file(tmp)
  result <- tardoc:::.file_to_rd(path)
  expect_type(result, "list")
  expect_true(length(result) >= 1)
  expect_true(all(endsWith(names(result), ".Rd")))
})

test_that(".file_to_rd only documents functions with roxygen comments", {
  tmp  <- withr::local_tempdir()
  path <- write_mock_r_file(tmp)
  result <- tardoc:::.file_to_rd(path)
  expect_true("add.Rd" %in% names(result))
  expect_false("internal_helper.Rd" %in% names(result))
})

# ---- get_fn_docs ------------------------------------------------------------

test_that("get_fn_docs returns a string for a documented function", {
  tmp  <- withr::local_tempdir()
  path <- write_mock_r_file(tmp)
  result <- get_fn_docs("add", path)
  expect_type(result, "character")
  expect_true(nchar(result) > 0)
})

test_that("get_fn_docs returns NULL with a warning for undocumented function", {
  tmp  <- withr::local_tempdir()
  path <- write_mock_r_file(tmp)
  expect_warning(
    result <- get_fn_docs("internal_helper", path),
    "no roxygen docs"
  )
  expect_null(result)
})

test_that("get_fn_docs warning lists available topics", {
  tmp  <- withr::local_tempdir()
  path <- write_mock_r_file(tmp)
  expect_warning(get_fn_docs("nonexistent_fn", path), "add.Rd")
})

test_that("get_fn_docs output contains function name", {
  tmp  <- withr::local_tempdir()
  path <- write_mock_r_file(tmp)
  result <- get_fn_docs("add", path)
  expect_match(result, "add")
})

# ---- moxygenise_file --------------------------------------------------------

test_that("moxygenise_file writes Rd for documented function", {
  tmp     <- withr::local_tempdir()
  r_path  <- write_mock_r_file(tmp)
  man_dir <- file.path(tmp, "man")
  dir.create(man_dir)
  moxygenise_file(r_path, man_dir)
  expect_true(file.exists(file.path(man_dir, "add.Rd")))
})

test_that("moxygenise_file does not write Rd for undocumented function", {
  tmp     <- withr::local_tempdir()
  r_path  <- write_mock_r_file(tmp)
  man_dir <- file.path(tmp, "man")
  dir.create(man_dir)
  moxygenise_file(r_path, man_dir)
  expect_false(file.exists(file.path(man_dir, "internal_helper.Rd")))
})

# ---- moxygenise (whole directory) -------------------------------------------

test_that("moxygenise writes Rd files for all documented functions", {
  tmp     <- withr::local_tempdir()
  r_dir   <- file.path(tmp, "R")
  man_dir <- file.path(tmp, "man")
  write_mock_r_file(r_dir, "helpers.R")
  dir.create(man_dir)
  moxygenise(r_dir, man_dir)
  expect_true(file.exists(file.path(man_dir, "add.Rd")))
})
