# tests/testthat/test-target_groups.R
#
# Grouping exists so a 400-target graph is not one unreadable line. The risk
# is not failing to find groups -- it is inventing them. These pin both the
# scorer that rejects a useless grouping and the order of precedence among
# the signals, checked against pipelines built for the purpose.

# ---- score_grouping --------------------------------------------------------

test_that("a balanced grouping scores well", {
  expect_gt(score_grouping(rep(c("a", "b", "c"), each = 5)), 1)
})

test_that("one group is not a grouping", {
  expect_equal(score_grouping(rep("everything", 20)), -Inf)
})

test_that("all singletons is not a grouping", {
  expect_equal(score_grouping(as.character(1:20)), -Inf)
})

test_that("six groups across seven targets is rejected", {
  # Arithmetically well balanced and completely useless: the case that got
  # through before the mean-group-size floor.
  expect_equal(score_grouping(c("a", "a", "b", "c", "d", "e", "f")), -Inf)
})

test_that("a dominant group scores below an even split", {
  even <- score_grouping(rep(c("a", "b", "c"), each = 10))
  lop  <- score_grouping(c(rep("a", 26), rep("b", 2), rep("c", 2)))
  expect_gt(even, lop)
})

test_that("too many groups is rejected", {
  expect_equal(score_grouping(rep(as.character(1:25), each = 4)), -Inf)
})

test_that("empty and degenerate input does not error", {
  expect_equal(score_grouping(character()), -Inf)
  expect_equal(score_grouping(c(NA_character_, "")), -Inf)
})

# ---- the signals -----------------------------------------------------------

test_that("prefix grouping splits on the separator", {
  g <- tardoc:::.group_by_prefix(c("a_1", "a_2", "b_1"))
  expect_equal(unname(g), c("a", "a", "b"))
})

test_that("prefix grouping refuses a partial split", {
  # One name without the separator means the grouping would leave a target
  # homeless, which is worse than not grouping.
  expect_null(tardoc:::.group_by_prefix(c("a_1", "a_2", "solo")))
})

test_that("declaration parsing finds targets wherever they are nested", {
  dir <- withr::local_tempdir()
  writeLines(c(
    "stage_targets <- list(",
    "  tar_target(alpha, f()),",
    "  targets::tar_target(beta, g())",
    ")"
  ), file.path(dir, "stage.R"))
  expect_setequal(tardoc:::.file_declares(file.path(dir, "stage.R")),
                  c("alpha", "beta"))
})

test_that("a file declaring no targets yields nothing", {
  dir <- withr::local_tempdir()
  writeLines("helper <- function() 1", file.path(dir, "h.R"))
  expect_equal(tardoc:::.file_declares(file.path(dir, "h.R")), character())
})

test_that("an unparseable file is skipped rather than fatal", {
  dir <- withr::local_tempdir()
  writeLines("list( tar_target(", file.path(dir, "broken.R"))
  expect_equal(tardoc:::.file_declares(file.path(dir, "broken.R")), character())
})

# ---- the cascade -----------------------------------------------------------

grouped_data <- function(n_per = 8, prefixes = c("ingest", "model", "report")) {
  nms <- as.vector(outer(seq_len(n_per), prefixes,
                         function(i, p) sprintf("%s_%02d", p, i)))
  list(
    target_names = nms,
    meta = dplyr::tibble(name = nms, type = "stem", time = "2026-01-01",
                         error = NA_character_, warnings = NA_character_,
                         seconds = 1, bytes = 10),
    manifest = dplyr::tibble(name = nms, command = "f()",
                             description = "", pattern = ""),
    network = list(vertices = dplyr::tibble(name = nms, type = "stem"),
                   edges = dplyr::tibble(from = nms[-length(nms)],
                                         to   = nms[-1])),
    outdated = NULL, progress = NULL, has_store = TRUE
  )
}

test_that("auto finds a prefix grouping on a pipeline large enough to need it", {
  g <- target_groups(grouped_data())
  expect_equal(g$method, "prefix")
  expect_setequal(unique(unname(g$groups)), c("ingest", "model", "report"))
})

test_that("auto declines to group a small pipeline", {
  # Seven targets read perfectly well as a list; grouping them is noise.
  g <- target_groups(grouped_data(n_per = 2))
  expect_equal(g$method, "none")
  expect_length(g$groups, 0L)
})

test_that("method = none groups nothing regardless of size", {
  expect_equal(target_groups(grouped_data(), method = "none")$method, "none")
})

test_that("an explicitly named method is honoured even below the auto bar", {
  # The caller asked for it; only "auto" holds the bar.
  g <- target_groups(grouped_data(n_per = 2), method = "prefix")
  expect_equal(g$method, "prefix")
  expect_length(unique(unname(g$groups)), 3L)
})

test_that("a pipeline with no usable signal is left ungrouped", {
  td <- grouped_data()
  td$target_names <- paste0("t", seq_along(td$target_names))   # no separator
  td$meta$name <- td$target_names
  td$manifest$name <- td$target_names
  td$network$vertices <- dplyr::tibble(name = td$target_names, type = "stem")
  td$network$edges <- dplyr::tibble(from = character(), to = character())
  g <- target_groups(td)
  # Depth cannot help either: with no edges every target is at layer 0.
  expect_equal(g$method, "none")
})

# ---- collapsing ------------------------------------------------------------

test_that("the graph collapses to one node per group", {
  td <- grouped_data()
  g  <- target_groups(td)
  graph <- build_dag_graph(td, groups = g$groups)
  expect_length(graph$groups$nodes, 3L)
  expect_true(all(vapply(graph$groups$nodes, function(n) n$n_targets, 0) == 8))
  expect_setequal(names(graph$groups$layout), c("ingest", "model", "report"))
})

test_that("every flat node carries its group", {
  td <- grouped_data()
  graph <- build_dag_graph(td, groups = target_groups(td)$groups)
  expect_true(all(vapply(graph$nodes, function(n) nzchar(n$group), logical(1))))
})

test_that("within-group edges disappear and between-group edges survive", {
  td <- grouped_data()
  graph <- build_dag_graph(td, groups = target_groups(td)$groups)
  srcs <- vapply(graph$groups$edges, function(e) e$source, character(1))
  tgts <- vapply(graph$groups$edges, function(e) e$target, character(1))
  expect_true(all(srcs != tgts))
  expect_equal(length(graph$groups$edges), length(unique(paste(srcs, tgts))))
})

test_that("a collapsed group reports the worst status among its members", {
  # A group of eight with one failure is not a healthy group.
  td <- grouped_data()
  td$meta$error[td$meta$name == "model_03"] <- "boom"
  graph <- build_dag_graph(td, groups = target_groups(td)$groups)
  model <- Filter(function(n) n$id == "model", graph$groups$nodes)[[1]]
  expect_equal(model$status, "errored")
  expect_equal(model$n_errored, 1L)
})

test_that("without groups the graph is unchanged", {
  td <- grouped_data()
  expect_null(build_dag_graph(td)$groups)
})

test_that("each group gets a layout of its own members only", {
  td <- grouped_data()
  graph <- build_dag_graph(td, groups = target_groups(td)$groups)
  ids <- vapply(graph$groups$layout$ingest, function(p) p$id, character(1))
  expect_true(all(startsWith(ids, "ingest_")))
  expect_length(ids, 8L)
})

test_that("authority beats arithmetic: a prefix outranks depth bands", {
  # A chain of 24 targets gives depth six tidy bands of four, which scores
  # better than three prefix groups of eight. Choosing on score alone picked
  # depth -- the less meaningful reading. Order of authority decides.
  g <- target_groups(grouped_data())
  expect_equal(g$method, "prefix")
  expect_gt(score_grouping(tardoc:::.group_by_depth(
    grouped_data()$target_names, grouped_data())), g$score)
})

test_that("a grouping where one group swallows the pipeline is rejected", {
  expect_equal(score_grouping(c(rep("a", 90), rep("b", 10))), -Inf)
})
