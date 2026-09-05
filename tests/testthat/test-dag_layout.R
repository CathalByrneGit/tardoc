# tests/testthat/test-dag_layout.R

test_that("a linear chain lands in consecutive layers", {
  pos <- dag_layout(c("a", "b", "c"),
                    data.frame(from = c("a", "b"), to = c("b", "c")))
  expect_equal(pos$layer[pos$name == "a"], 0L)
  expect_equal(pos$layer[pos$name == "b"], 1L)
  expect_equal(pos$layer[pos$name == "c"], 2L)
  expect_true(all(diff(pos$x[order(pos$layer)]) > 0))
})

test_that("a node sits one layer right of its DEEPEST parent", {
  # d has parents a (layer 0) and c (layer 2), so d must be layer 3, not 1.
  pos <- dag_layout(c("a", "b", "c", "d"),
                    data.frame(from = c("a", "b", "a"), to = c("b", "c", "d")))
  # rebuild with c -> d so d has two parents at different depths
  pos <- dag_layout(c("a", "b", "c", "d"),
                    data.frame(from = c("a", "b", "a", "c"),
                               to   = c("b", "c", "d", "d")))
  expect_equal(pos$layer[pos$name == "d"], 3L)
})

test_that("roots share layer zero", {
  pos <- dag_layout(c("r1", "r2", "child"),
                    data.frame(from = c("r1", "r2"), to = c("child", "child")))
  expect_equal(sort(pos$layer[pos$name %in% c("r1", "r2")]), c(0L, 0L))
  expect_equal(pos$layer[pos$name == "child"], 1L)
})

test_that("nodes in one layer do not overlap vertically", {
  pos <- dag_layout(c("a", "b", "c"), data.frame(from = character(), to = character()))
  expect_equal(length(unique(pos$y)), 3L)
  expect_true(all(pos$layer == 0L))
})

test_that("an empty graph returns an empty frame with the right columns", {
  pos <- dag_layout(character(), data.frame(from = character(), to = character()))
  expect_equal(nrow(pos), 0L)
  expect_named(pos, c("name", "layer", "x", "y"))
})

test_that("edges naming unknown nodes are ignored", {
  pos <- dag_layout(c("a", "b"),
                    data.frame(from = c("a", "ghost"), to = c("b", "b")))
  expect_equal(pos$layer[pos$name == "b"], 1L)
  expect_equal(nrow(pos), 2L)
})

test_that("a cyclic edge list terminates instead of looping forever", {
  # Not reachable from targets, but the layout must not hang on bad input.
  pos <- dag_layout(c("x", "y"), data.frame(from = c("x", "y"), to = c("y", "x")))
  expect_equal(nrow(pos), 2L)
  expect_false(anyNA(pos$layer))
})

test_that("build_dag_graph produces React Flow node and edge shapes", {
  td <- mock_targets_data()
  g  <- build_dag_graph(td)
  expect_setequal(vapply(g$nodes, `[[`, character(1), "id"), td$target_names)
  n1 <- g$nodes[[1]]
  expect_true(all(c("id", "label", "status", "x", "y", "layer") %in% names(n1)))
  if (length(g$edges) > 0) {
    expect_true(all(c("id", "source", "target") %in% names(g$edges[[1]])))
  }
})

test_that("build_dag_graph keeps only edges between known targets", {
  td <- mock_targets_data()   # network includes function nodes as well
  g  <- build_dag_graph(td)
  ids <- vapply(g$nodes, `[[`, character(1), "id")
  for (ed in g$edges) {
    expect_true(ed$source %in% ids)
    expect_true(ed$target %in% ids)
  }
})

test_that("nodes carry the detail the click panel renders", {
  g <- build_dag_graph(mock_targets_data())
  n <- g$nodes[[1]]
  expect_true(all(c("description", "command", "last_built", "error",
                    "upstream", "downstream", "page", "status") %in% names(n)))
})

test_that("a node's upstream and downstream match the edge list", {
  td <- mock_targets_data()
  g  <- build_dag_graph(td)
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  # clean_data is fed by raw_data and feeds model_fit in the fixture network.
  cd <- by[["clean_data"]]
  expect_true("raw_data" %in% unlist(cd$upstream))
  expect_true("model_fit" %in% unlist(cd$downstream))
})

test_that("a root has no upstream and a leaf no downstream", {
  g  <- build_dag_graph(mock_targets_data())
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  expect_length(by[["raw_data"]]$upstream, 0L)
  expect_length(by[["report"]]$downstream, 0L)
})

test_that("description and command come through from the manifest", {
  g  <- build_dag_graph(mock_targets_data())
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  expect_equal(by[["raw_data"]]$description, "Raw sensor readings")
  expect_equal(by[["clean_data"]]$command, "clean_raw(raw_data)")
})

test_that("a missing description is an empty string, never NA", {
  g  <- build_dag_graph(mock_targets_data())
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  # model_fit's description is NA in the fixture; report's is "".
  expect_identical(by[["model_fit"]]$description, "")
  expect_false(anyNA(vapply(g$nodes, `[[`, character(1), "description")))
})

test_that("the page path points at the target's markdown file", {
  g  <- build_dag_graph(mock_targets_data())
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  expect_equal(by[["clean_data"]]$page, "targets/clean_data.md")
})

test_that("generate_reactflow_graph embeds the graph and no placeholders", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  p <- suppressMessages(
    generate_reactflow_graph(mock_targets_data(), cfg, pkg_name = "Zebra pipeline")
  )
  html <- paste(readLines(p, warn = FALSE), collapse = "\n")
  expect_true(grepl("Zebra pipeline", html, fixed = TRUE))
  expect_false(grepl("\\{\\{[A-Z_]+\\}\\}", html))
  expect_true(grepl("clean_data", html, fixed = TRUE))
  expect_true(grepl("onNodeClick", html, fixed = TRUE))
})

test_that("the graph page pins its CDN assets with integrity", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  p <- suppressMessages(generate_reactflow_graph(mock_targets_data(), cfg))
  html <- paste(readLines(p, warn = FALSE), collapse = "\n")
  srcs <- regmatches(html, gregexpr('(src|href)="https://[^"]+"', html))[[1]]
  expect_true(length(srcs) > 0)
  expect_false(any(grepl("jsdelivr|cdnjs", srcs) & !grepl("@[0-9]|/[0-9]+\\.", srcs)))
  expect_equal(
    length(regmatches(html, gregexpr('integrity="sha384-', html))[[1]]),
    length(srcs)
  )
})

# ---- dynamic branching -----------------------------------------------------

test_that("a target with a pattern is marked branched, with its branch count", {
  g  <- build_dag_graph(mock_branched_data())
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  expect_true(by[["chunk"]]$branched)
  expect_equal(by[["chunk"]]$pattern, "map(files)")
  expect_equal(by[["chunk"]]$n_branches, 3L)
  expect_equal(by[["combos"]]$pattern, "cross(grid_a, grid_b)")
  expect_equal(by[["combos"]]$n_branches, 4L)
})

test_that("a stem is not branched even when children are recorded against it", {
  # targets records branch names against a stem that a pattern maps over, so
  # `children` alone would wrongly report ordinary targets as branched.
  # `pattern` is the target's own declaration and is the honest signal.
  g  <- build_dag_graph(mock_branched_data())
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  expect_false(by[["files"]]$branched)
  expect_equal(by[["files"]]$n_branches, 0L)
  expect_equal(by[["files"]]$pattern, "")
})

test_that("a target with no children at all reports zero branches", {
  g  <- build_dag_graph(mock_branched_data())
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  expect_false(by[["summary_all"]]$branched)
  expect_equal(by[["summary_all"]]$n_branches, 0L)
})

test_that("storage and iteration settings come through", {
  g  <- build_dag_graph(mock_branched_data())
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  expect_equal(by[["summary_all"]]$format, "qs")
  expect_equal(by[["combos"]]$repository, "aws")
  expect_equal(by[["combos"]]$iteration, "list")
})

test_that("runtime figures come through as numbers, not strings", {
  g  <- build_dag_graph(mock_branched_data())
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  expect_equal(by[["combos"]]$seconds, 1.5)
  expect_equal(by[["chunk"]]$bytes, 174)
})

test_that("warnings are carried through when present", {
  g  <- build_dag_graph(mock_branched_data())
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  expect_equal(by[["chunk"]]$warnings, "one warning")
  expect_equal(by[["files"]]$warnings, "")
})

test_that("build_dag_graph works when no store exists", {
  # No meta rows: everything should still resolve, with runtime fields absent.
  td <- mock_branched_data()
  td$meta <- td$meta[0, ]
  g <- build_dag_graph(td)
  by <- stats::setNames(g$nodes, vapply(g$nodes, `[[`, character(1), "id"))
  expect_true(by[["chunk"]]$branched)      # pattern is static, still known
  expect_equal(by[["chunk"]]$n_branches, 0L)
  expect_true(is.na(by[["chunk"]]$seconds))
})

test_that("the viewer embeds the graph and keeps its navigation functions", {
  tmp <- withr::local_tempdir(); cfg <- mock_cfg(tmp); setup_site_dirs(cfg)
  generate_viewer(mock_branched_data(), character(), cfg, pkg_name = "Branchy")
  html <- paste(readLines(file.path(cfg$site_path, "viewer.html"), warn = FALSE),
                collapse = "\n")
  expect_true(grepl("rf-graph", html, fixed = TRUE))
  expect_true(grepl("map(files)", html, fixed = TRUE))
  # The React Flow block once ate these when its boundary was wrong.
  for (fn in c("function showTab", "function renderNavList", "function loadPage",
               "function expandMermaid", "function closeMermaid")) {
    expect_true(grepl(fn, html, fixed = TRUE), info = fn)
  }
})
