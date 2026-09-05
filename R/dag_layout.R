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
#' Turns `targets_data` into the `{nodes, edges}` shape the React Flow viewer
#' consumes, with positions already assigned by [dag_layout()].
#'
#' Each node carries enough detail for the graph page to show a panel when it is
#' clicked -- description, command, status, build time, immediate neighbours,
#' and a deep link into the viewer -- so a reader can inspect a target without
#' leaving the graph.
#'
#' @param targets_data Output of [load_targets_data()].
#' @return A list with `nodes` and `edges`.
#' @export
build_dag_graph <- function(targets_data) {
  names_vec <- targets_data$target_names
  net_edges <- targets_data$network$edges
  edges <- data.frame(
    from = as.character(net_edges$from),
    to   = as.character(net_edges$to),
    stringsAsFactors = FALSE
  )
  edges <- edges[edges$from %in% names_vec & edges$to %in% names_vec, , drop = FALSE]

  pos      <- dag_layout(names_vec, edges)
  meta     <- targets_data$meta
  manifest <- targets_data$manifest

  chr1 <- function(x) {
    if (length(x) == 0 || is.na(x[1])) "" else as.character(x[1])
  }

  nodes <- lapply(seq_len(nrow(pos)), function(i) {
    nm   <- pos$name[i]
    mrow <- meta[meta$name == nm, , drop = FALSE]
    frow <- manifest[manifest$name == nm, , drop = FALSE]

    status <- if (nrow(mrow) == 0 || is.na(mrow$error[1])) "uptodate" else "errored"
    desc   <- if ("description" %in% names(frow)) chr1(frow$description) else ""

    # Branching is read from the manifest's `pattern`, not from meta's
    # `children`. A plain stem that a downstream pattern maps over also has
    # children recorded against it, so `children` would report ordinary targets
    # as branched. `pattern` is the target's own declaration and is available
    # without a store.
    pattern  <- if (nrow(frow)) chr1(frow$pattern) else ""
    branched <- nzchar(pattern)
    n_branch <- if (branched && nrow(mrow) && "children" %in% names(mrow)) {
      kids <- mrow$children[[1]]
      if (is.null(kids)) 0L else sum(!is.na(kids))
    } else {
      0L
    }

    list(
      id          = nm,
      label       = nm,
      status      = status,
      description = desc,
      command     = if (nrow(frow)) chr1(frow$command) else "",
      last_built  = if (nrow(mrow)) chr1(as.character(mrow$time)) else "",
      error       = if (nrow(mrow)) chr1(mrow$error) else "",
      warnings    = if (nrow(mrow) && "warnings" %in% names(mrow))
                      chr1(mrow$warnings) else "",
      pattern     = pattern,
      branched    = branched,
      n_branches  = n_branch,
      type        = if (nrow(mrow) && "type" %in% names(mrow))
                      chr1(mrow$type) else if (branched) "pattern" else "stem",
      format      = if (nrow(frow)) chr1(frow$format) else "",
      repository  = if (nrow(frow)) chr1(frow$repository) else "",
      iteration   = if (nrow(frow)) chr1(frow$iteration) else "",
      seconds     = if (nrow(mrow) && "seconds" %in% names(mrow) &&
                        !is.na(mrow$seconds[1])) as.numeric(mrow$seconds[1]) else NA,
      bytes       = if (nrow(mrow) && "bytes" %in% names(mrow) &&
                        !is.na(mrow$bytes[1])) as.numeric(mrow$bytes[1]) else NA,
      upstream    = as.list(edges$from[edges$to   == nm]),
      downstream  = as.list(edges$to[edges$from == nm]),
      page        = paste0("targets/", nm, ".md"),
      x = pos$x[i], y = pos$y[i], layer = pos$layer[i]
    )
  })

  edge_list <- lapply(seq_len(nrow(edges)), function(i) {
    list(id = paste0(edges$from[i], "->", edges$to[i]),
         source = edges$from[i], target = edges$to[i])
  })

  list(nodes = nodes, edges = edge_list)
}
