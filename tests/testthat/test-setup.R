# tests/testthat/test-setup.R

test_that("build_site_config returns all required keys", {
  cfg      <- build_site_config()
  expected <- c("project_path","site_path","targets_dir","functions_dir",
                "notes_dir","notes_targets","notes_functions",
                "targets_store","r_scripts_dir","repo_url")
  expect_true(all(expected %in% names(cfg)))
})

test_that("build_site_config resolves project_path to absolute", {
  expect_true(startsWith(build_site_config()$project_path, "/"))
})

test_that("build_site_config site_path is inside project_path", {
  cfg <- build_site_config(site_dir = "tardoc")
  expect_true(startsWith(cfg$site_path, cfg$project_path))
})

test_that("build_site_config uses custom site_dir", {
  expect_match(build_site_config(site_dir = "my_docs")$site_path, "my_docs")
})

test_that("build_site_config notes_targets is inside notes_dir", {
  cfg <- build_site_config()
  expect_true(startsWith(cfg$notes_targets, cfg$notes_dir))
})

test_that("build_site_config has no renderer field", {
  expect_false("renderer" %in% names(build_site_config()))
})

test_that("build_site_config normalises repo_url trailing slash", {
  cfg <- build_site_config(repo_url = "https://github.com/user/repo/blob/main")
  expect_match(cfg$repo_url, "/$")
})

test_that("build_site_config repo_url NULL by default", {
  expect_null(build_site_config()$repo_url)
})

test_that("setup_site_dirs creates all required directories", {
  tmp <- withr::local_tempdir()
  cfg <- mock_cfg(tmp)
  setup_site_dirs(cfg)
  expect_true(dir.exists(cfg$targets_dir))
  expect_true(dir.exists(cfg$functions_dir))
  expect_true(dir.exists(cfg$notes_targets))
  expect_true(dir.exists(cfg$notes_functions))
})

test_that("setup_site_dirs returns cfg invisibly", {
  tmp <- withr::local_tempdir()
  cfg <- mock_cfg(tmp)
  expect_identical(setup_site_dirs(cfg), cfg)
})

test_that("setup_site_dirs is idempotent", {
  tmp <- withr::local_tempdir()
  cfg <- mock_cfg(tmp)
  expect_no_error(setup_site_dirs(cfg))
  expect_no_error(setup_site_dirs(cfg))
})
