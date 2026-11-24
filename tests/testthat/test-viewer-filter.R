# tests/testthat/test-viewer-filter.R
#
# The graph filter takes dbt-style selectors: "clean+" for a node and
# everything downstream, "+clean" for everything upstream, "2+report" to limit
# depth, "ingest_*" wildcards, "-name" to exclude. The logic is plain
# JavaScript in the viewer template, so it is run under node against a small
# graph rather than only grepped for.

tpl <- function() {
  paste(readLines(system.file("templates", "viewer.html", package = "tardoc"),
                  warn = FALSE), collapse = "\n")
}

# Source of one top-level `function name(...) { ... }`, by brace matching.
js_function <- function(src, name) {
  start <- regexpr(paste0("function ", name, "\\("), src)
  chars <- strsplit(substring(src, start), "")[[1]]
  depth <- 0L; opened <- FALSE
  for (i in seq_along(chars)) {
    if (chars[i] == "{") { depth <- depth + 1L; opened <- TRUE }
    if (chars[i] == "}") depth <- depth - 1L
    if (opened && depth == 0L) return(paste(chars[seq_len(i)], collapse = ""))
  }
  stop("no closing brace for ", name)
}

select_with_node <- function(query) {
  s <- tpl()
  harness <- c(
    vapply(c("reach", "parseTerm", "nameMatcher", "selectNodes"),
           function(f) js_function(s, f), character(1)),
    'const ids = ["raw_path","readings","clean","station_summary","drift_model",',
    '             "drift_flags","report","helper"];',
    'const GRAPH = { nodes: ids.map(id => ({ id, kind: id === "helper" ? "function" : "stem" })) };',
    'const edges = [["raw_path","readings"],["readings","clean"],["clean","station_summary"],',
    '  ["clean","drift_model"],["drift_model","drift_flags"],["station_summary","report"],',
    '  ["drift_flags","report"],["helper","clean"]];',
    'const FOCUS_UP = {}, FOCUS_DOWN = {};',
    'edges.forEach(e => { (FOCUS_DOWN[e[0]] = FOCUS_DOWN[e[0]] || []).push(e[1]);',
    '                     (FOCUS_UP[e[1]] = FOCUS_UP[e[1]] || []).push(e[0]); });',
    'const RF_BY_ID = {}; GRAPH.nodes.forEach(n => { RF_BY_ID[n.id] = n; });',
    'const document = { getElementById: () => ({ checked: false }) };',
    sprintf('const r = selectNodes(%s, false);', jsonlite::toJSON(query, auto_unbox = TRUE)),
    'console.log(JSON.stringify({ ids: [...r.ids].sort(), unmatched: r.unmatched }));'
  )
  f <- withr::local_tempfile(fileext = ".js")
  writeLines(harness, f)
  jsonlite::fromJSON(system2("node", f, stdout = TRUE))
}

test_that("selectors pick the right neighbourhood", {
  skip_if(Sys.which("node") == "", "node is not available")

  expect_identical(select_with_node("clean")$ids, "clean")
  expect_setequal(select_with_node("clean+")$ids,
                  c("clean", "drift_model", "station_summary", "drift_flags", "report"))
  expect_setequal(select_with_node("+clean")$ids, c("clean", "readings", "raw_path"))
  expect_setequal(select_with_node("1+clean")$ids, c("clean", "readings"))
  expect_setequal(select_with_node("clean+1")$ids,
                  c("clean", "drift_model", "station_summary"))
})

test_that("wildcards, exclusion and unions work", {
  skip_if(Sys.which("node") == "", "node is not available")

  expect_setequal(select_with_node("drift_*")$ids, c("drift_model", "drift_flags"))
  expect_setequal(select_with_node("clean+ -report")$ids,
                  c("clean", "drift_model", "station_summary", "drift_flags"))
  expect_setequal(select_with_node("raw_path report")$ids, c("raw_path", "report"))
  # Exclusion alone starts from everything.
  expect_false("raw_path" %in% select_with_node("-raw_path")$ids)
})

test_that("commas intersect and spaces union, as in dbt", {
  skip_if(Sys.which("node") == "", "node is not available")

  # Downstream of clean AND upstream of report: the nodes on the way between.
  expect_setequal(select_with_node("clean+,+report")$ids,
                  c("clean", "drift_model", "station_summary", "drift_flags", "report"))
  expect_setequal(select_with_node("+drift_flags,clean+")$ids,
                  c("clean", "drift_model", "drift_flags"))
  # Wildcard intersected with a chain.
  expect_setequal(select_with_node("drift_*,+report")$ids,
                  c("drift_model", "drift_flags"))
  # An exclusion inside a group still applies to the whole result.
  expect_setequal(select_with_node("clean+,-report")$ids,
                  c("clean", "drift_model", "station_summary", "drift_flags"))
  # Disjoint intersection is empty, not an error.
  expect_length(select_with_node("raw_path,report")$ids, 0L)
})

test_that("a term that names nothing is reported, not silently dropped", {
  skip_if(Sys.which("node") == "", "node is not available")
  r <- select_with_node("clean nope")
  expect_identical(r$ids, "clean")
  expect_identical(r$unmatched, "nope")
})

test_that("functions stay out of the result while they are hidden", {
  skip_if(Sys.which("node") == "", "node is not available")
  # `helper` feeds clean, but upstream of clean must not include a function the
  # reader has not switched on.
  expect_false("helper" %in% select_with_node("+clean")$ids)
})

test_that("the filter is wired into the overview and the generated viewer", {
  s <- tpl()
  expect_match(s, "(!graphFilter || graphFilter.has(n.id))", fixed = TRUE)
  expect_match(s, 'id="graph-filter"', fixed = TRUE)
})

# ---- focus counts follow the filter --------------------------------------------

reach_with_node <- function(start, direction, within = NULL) {
  s <- tpl()
  harness <- c(
    js_function(s, "reach"),
    'const nodes = ["a","b","c","d","e"];',
    'const RF_BY_ID = {}; nodes.forEach(id => { RF_BY_ID[id] = { id, kind: "stem" }; });',
    'const document = { getElementById: () => ({ checked: false }) };',
    'const DOWN = { a: ["b"], b: ["c"], c: ["d"], d: ["e"] };',
    'const UP = { b: ["a"], c: ["b"], d: ["c"], e: ["d"] };',
    sprintf('const within = %s;',
            if (is.null(within)) "undefined" else
              sprintf("new Set(%s)", jsonlite::toJSON(within))),
    sprintf('console.log(JSON.stringify(reach(%s, %s, 0, within)));',
            jsonlite::toJSON(start, auto_unbox = TRUE),
            if (direction == "down") "DOWN" else "UP")
  )
  f <- withr::local_tempfile(fileext = ".js")
  writeLines(harness, f)
  as.character(jsonlite::fromJSON(system2("node", f, stdout = TRUE)))
}

test_that("without a filter, reach() walks the whole chain", {
  skip_if(Sys.which("node") == "", "node is not available")
  expect_identical(reach_with_node("a", "down"), c("b", "c", "d", "e"))
})

test_that("with a filter, reach() counts only nodes on screen", {
  skip_if(Sys.which("node") == "", "node is not available")
  # c is filtered out: b is reachable, and d and e are not, because the visible
  # graph has no edge leading to them.
  expect_identical(reach_with_node("a", "down", c("a", "b", "d", "e")), "b")
  expect_identical(reach_with_node("e", "up", c("a", "b", "d", "e")), "d")
})

test_that("focus passes the filter and the filter itself does not use it", {
  s <- tpl()
  expect_match(s, "reach(id, FOCUS_UP, depth, graphFilter)", fixed = TRUE)
  expect_match(s, "reach(id, FOCUS_DOWN, depth, graphFilter)", fixed = TRUE)
  # selectNodes builds the filter, so it must not be limited by the previous one.
  expect_match(s, "reach(id, FOCUS_UP,   t.up)", fixed = TRUE)
})
