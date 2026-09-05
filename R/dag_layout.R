# R/dag_layout.R
#
# Layered layout for a target DAG.
#
# React Flow, unlike mermaid, performs no layout of its own: every node must
# arrive with an (x, y). That is the price of the swap, and it is small, because
# a targets pipeline is already a layered DAG -- longest-path depth from the
# roots gives the column, and nodes are then stacked within their column.
#
# The approach mirrors layout_positions() in dplyneage, which solves the same
# problem for column-level lineage graphs.

#' Assign layered (x, y) positions to a DAG
#'
#' Computes a left-to-right layered layout: each node's column is its
#' longest-path depth from a root, and nodes sharing a column are stacked
#' vertically and centred against the tallest column.
#'
#' Cycles cannot occur in a `targets` pipeline, but a malformed edge list could
#' contain one. Rather than looping forever, any node still unresolved once no
#' further progress is possible is placed in the last computed layer.
#'
#' @param nodes Character vector of node names.
#' @param edges A data frame or list with `from` and `to` character columns.
#' @param x_spacing Horizontal distance between layers, in pixels.
#' @param y_spacing Vertical distance between stacked nodes, in pixels.
#'
#' @return A data frame with `name`, `layer`, `x` and `y`.
#' @export
#' @examples
#' dag_layout(
#'   nodes = c("a", "b", "c"),
#'   edges = data.frame(from = c("a", "b"), to = c("b", "c"))
#' )
dag_layout <- function(nodes, edges, x_spacing = 220, y_spacing = 90) {
  nodes <- unique(as.character(nodes))
  if (length(nodes) == 0) {
    return(data.frame(name = character(), layer = integer(),
                      x = numeric(), y = numeric(), stringsAsFactors = FALSE))
  }

  from <- as.character(edges$from %||% character())
  to   <- as.character(edges$to   %||% character())
  keep <- from %in% nodes & to %in% nodes
  from <- from[keep]
  to   <- to[keep]

  # Longest-path depth: a node sits one layer right of its deepest parent.
  layer   <- stats::setNames(rep(NA_integer_, length(nodes)), nodes)
  parents <- split(from, factor(to, levels = nodes))

  repeat {
    progressed <- FALSE
    for (n in nodes) {
      if (!is.na(layer[[n]])) next
      p <- parents[[n]]
      if (length(p) == 0) {
        layer[[n]] <- 0L
        progressed <- TRUE
      } else if (all(!is.na(layer[p]))) {
        layer[[n]] <- max(layer[p]) + 1L
        progressed <- TRUE
      }
    }
    if (!anyNA(layer) || !progressed) break
  }
  # Unreachable in a valid DAG; guards against a cyclic edge list. When every
  # node is in a cycle nothing resolved at all, so fall back to a single layer
  # rather than taking max() of an all-NA vector.
  if (anyNA(layer)) {
    settled <- layer[!is.na(layer)]
    layer[is.na(layer)] <- if (length(settled) > 0) max(settled) else 0L
  }

  # Stack within each layer, then centre every column on the tallest one.
  counts  <- table(layer)
  tallest <- max(as.integer(counts))
  x <- numeric(length(nodes))
  y <- numeric(length(nodes))
  for (l in sort(unique(layer))) {
    idx <- which(layer == l)
    x[idx] <- l * x_spacing
    y[idx] <- (seq_along(idx) - 1) * y_spacing +
      (tallest - length(idx)) * y_spacing / 2
  }

  data.frame(
    name  = nodes,
    layer = as.integer(layer),
    x     = x,
    y     = y,
    stringsAsFactors = FALSE
  )
}

#' Build the node and edge lists a React Flow graph needs
#'
#' Turns `targets_data` into the `{nodes, edges}` shape the viewer's graph
#' consumes, with positions already assigned by [dag_layout()].
#'
#' Nodes come from `tar_network()`'s vertices, which already carry `type`
#' (`stem` / `pattern` / `function`), a branch count, runtime and size. They are
#' enriched from the manifest (command, branching pattern, storage settings) and
#' the metadata (errors, warnings, build time) so a reader can inspect a target
#' without leaving the graph.
#'
#' @param targets_data Output of [load_targets_data()].
#' @param include_functions Logical. Include function vertices as nodes.
#'   `tar_network()` reports the functions a target calls, and the viewer can
#'   toggle them.
#' @return A list with `nodes` and `edges`.
#' @export
build_dag_graph <- function(targets_data, include_functions = TRUE) {
  verts <- as.data.frame(targets_data$network$vertices, stringsAsFactors = FALSE)
  if (is.null(verts$type)) verts$type <- "stem"
  if (!include_functions) verts <- verts[verts$type != "function", , drop = FALSE]

  keep_names <- as.character(verts$name)
  net_edges  <- targets_data$network$edges
  edges <- data.frame(
    from = as.character(net_edges$from),
    to   = as.character(net_edges$to),
    stringsAsFactors = FALSE
  )
  edges <- edges[edges$from %in% keep_names & edges$to %in% keep_names, , drop = FALSE]

  pos      <- dag_layout(keep_names, edges)
  meta     <- targets_data$meta
  manifest <- targets_data$manifest

  nodes <- lapply(seq_len(nrow(pos)), function(i) {
    .dag_node(pos[i, ], verts, meta, manifest, edges)
  })

  edge_list <- lapply(seq_len(nrow(edges)), function(i) {
    list(id = paste0(edges$from[i], "->", edges$to[i]),
         source = edges$from[i], target = edges$to[i])
  })

  list(nodes = nodes, edges = edge_list)
}

#' Build one graph node
#'
#' Split out of [build_dag_graph()] so that function stays within the project's
#' complexity budget: assembling a node touches four data sources and a dozen
#' optional fields.
#'
#' @param prow One row of the [dag_layout()] result.
#' @param verts,meta,manifest,edges Data frames from [build_dag_graph()].
#' @return A list describing one node.
#' @keywords internal
.dag_node <- function(prow, verts, meta, manifest, edges) {
  nm   <- prow$name
  vrow <- verts[verts$name == nm, , drop = FALSE]
  mrow <- meta[meta$name == nm, , drop = FALSE]
  frow <- manifest[manifest$name == nm, , drop = FALSE]

  chr1 <- function(x) if (length(x) == 0 || is.na(x[1])) "" else as.character(x[1])
  num1 <- function(df, col) {
    if (!is.null(df) && nrow(df) && col %in% names(df) && !is.na(df[[col]][1])) {
      as.numeric(df[[col]][1])
    } else {
      NA
    }
  }
  fld <- function(df, col) if (nrow(df) && col %in% names(df)) chr1(df[[col]]) else ""

  kind <- chr1(vrow$type)
  if (!nzchar(kind)) kind <- "stem"

  status <- if (kind == "function") {
    "function"
  } else if (nrow(mrow) == 0 || is.na(mrow$error[1])) {
    "uptodate"
  } else {
    "errored"
  }

  # Branching comes from the vertex type or the manifest's `pattern` -- the
  # target's own declaration, known without a store. meta$children is only ever
  # a count, never the signal: targets records branch names against a plain stem
  # that a pattern maps over.
  pattern  <- fld(frow, "pattern")
  branched <- kind == "pattern" || nzchar(pattern)
  n_branch <- num1(vrow, "branches")
  if (is.na(n_branch) && branched && nrow(mrow) && "children" %in% names(mrow)) {
    kids <- mrow$children[[1]]
    n_branch <- if (is.null(kids)) 0 else sum(!is.na(kids))
  }
  if (is.na(n_branch) || !branched) n_branch <- 0

  desc <- fld(frow, "description")
  if (!nzchar(desc)) desc <- fld(vrow, "description")

  secs  <- num1(vrow, "seconds"); if (is.na(secs))  secs  <- num1(mrow, "seconds")
  bytes <- num1(vrow, "bytes");   if (is.na(bytes)) bytes <- num1(mrow, "bytes")

  list(
    id          = nm,
    label       = nm,
    kind        = kind,
    status      = status,
    description = desc,
    command     = fld(frow, "command"),
    last_built  = if (nrow(mrow)) chr1(as.character(mrow$time)) else "",
    error       = fld(mrow, "error"),
    warnings    = fld(mrow, "warnings"),
    pattern     = pattern,
    branched    = branched,
    n_branches  = as.integer(n_branch),
    format      = fld(frow, "format"),
    repository  = fld(frow, "repository"),
    iteration   = fld(frow, "iteration"),
    seconds     = secs,
    bytes       = bytes,
    upstream    = as.list(edges$from[edges$to   == nm]),
    downstream  = as.list(edges$to[edges$from == nm]),
    page        = paste0(if (kind == "function") "functions/" else "targets/",
                         nm, ".md"),
    x = prow$x, y = prow$y, layer = prow$layer
  )
}
