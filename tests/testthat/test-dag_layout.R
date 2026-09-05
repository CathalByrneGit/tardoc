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
