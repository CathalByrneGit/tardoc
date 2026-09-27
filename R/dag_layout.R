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
#' @param groups Optional named character vector of group label per target,
#'   from [target_groups()]. When supplied each node carries its `group`, and
#'   the result gains a `groups` element: a collapsed graph of one node per
#'   group, plus a per-group layout so the viewer can drill into one without
#'   laying anything out itself.
#' @return A list with `nodes` and `edges`, and `groups` when grouped.
#' @export
build_dag_graph <- function(targets_data, include_functions = TRUE,
                            groups = NULL) {
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

  pos <- dag_layout(keep_names, edges)

  nodes <- lapply(seq_len(nrow(pos)), function(i) {
    .dag_node(pos[i, ], targets_data, verts, edges)
  })

  edge_list <- lapply(seq_len(nrow(edges)), function(i) {
    list(id = paste0(edges$from[i], "->", edges$to[i]),
         source = edges$from[i], target = edges$to[i])
  })

  if (length(groups)) {
    nodes <- lapply(nodes, function(n) {
      n$group <- if (!is.na(groups[n$id])) unname(groups[n$id]) else ""
      n
    })
  }

  out <- list(nodes = nodes, edges = edge_list)
  if (length(groups)) out$groups <- .collapse_graph(nodes, edges, groups)
  out
}

#' Collapse a graph to one node per group
#'
#' At 400 targets the layered layout is a line nobody can read. Collapsing to
#' a handful of group nodes makes the shape legible, and a per-group layout is
#' emitted alongside so clicking into one is a drill-down the viewer can
#' render directly -- no layout algorithm duplicated in JavaScript.
#'
#' @param nodes The node list from [build_dag_graph()].
#' @param edges The edge data frame.
#' @param groups Named character vector of group label per target.
#'
#' @return A list with `nodes` (one per group, carrying counts and a status
#'   rollup), `edges` (deduplicated between groups), and `layout` (per group,
#'   the positions of its members laid out on their own).
#' @keywords internal
.collapse_graph <- function(nodes, edges, groups) {
  gof <- function(id) if (!is.na(groups[id])) unname(groups[id]) else ""
  ids <- vapply(nodes, function(n) n$id, character(1))
  gs  <- vapply(ids, gof, character(1))
  keep <- nzchar(gs)
  if (!any(keep)) return(NULL)

  labels <- unique(gs[keep])

  # Edges between distinct groups, deduplicated. Within-group edges disappear
  # into the node, which is the point of collapsing.
  e_from <- gs[match(edges$from, ids)]
  e_to   <- gs[match(edges$to,   ids)]
  ok <- !is.na(e_from) & !is.na(e_to) & nzchar(e_from) & nzchar(e_to) &
        e_from != e_to
  pairs <- unique(data.frame(from = e_from[ok], to = e_to[ok],
                             stringsAsFactors = FALSE))

  pos <- dag_layout(labels, pairs, x_spacing = 260, y_spacing = 110)

  gnodes <- lapply(seq_len(nrow(pos)), function(i) {
    lab <- pos$name[i]
    mem <- nodes[gs == lab]
    st  <- vapply(mem, function(n) n$status %||% "", character(1))
    # The worst status in the group is what a collapsed node must show:
    # a group of 70 with one failure is not a healthy group.
    roll <- if (any(st == "errored")) "errored"
            else if (any(st == "outdated")) "outdated"
            else if (any(st == "unbuilt")) "unbuilt" else "uptodate"
    secs <- vapply(mem, function(n) {
      v <- n$seconds; if (is.null(v) || is.na(v)) 0 else as.numeric(v)
    }, numeric(1))
    list(id = lab, label = lab, kind = "group", status = roll,
         status_label = .status_label(roll),
         n_targets = length(mem),
         n_errored = sum(st == "errored"),
         n_outdated = sum(st == "outdated"),
         seconds = sum(secs),
         members = as.list(vapply(mem, function(n) n$id, character(1))),
         x = pos$x[i], y = pos$y[i], layer = pos$layer[i])
  })

  gedges <- lapply(seq_len(nrow(pairs)), function(i) {
    list(id = paste0(pairs$from[i], "=>", pairs$to[i]),
         source = pairs$from[i], target = pairs$to[i])
  })

  # Each group laid out on its own, so drilling in does not require the
  # browser to run a layout.
  layout <- lapply(labels, function(lab) {
    mem <- ids[gs == lab]
    sub <- edges[edges$from %in% mem & edges$to %in% mem, , drop = FALSE]
    lp  <- dag_layout(mem, sub)
    lapply(seq_len(nrow(lp)), function(i)
      list(id = lp$name[i], x = lp$x[i], y = lp$y[i]))
  })
  names(layout) <- labels

  list(nodes = gnodes, edges = gedges, layout = layout)
}

#' Build one graph node
#'
#' Split out of [build_dag_graph()] so that function stays within the
#' project's complexity budget. The node's content comes from
#' [.target_facts()], the same call the target's markdown page makes, so the
#' inspect panel and the page cannot drift apart.
#'
#' @param prow One row of the [dag_layout()] result.
#' @param targets_data Output of [load_targets_data()].
#' @param verts,edges Data frames from [build_dag_graph()].
#' @return A list describing one node.
#' @keywords internal
.dag_node <- function(prow, targets_data, verts, edges) {
  nm   <- prow$name
  vrow <- verts[verts$name == nm, , drop = FALSE]
  kind <- if (nrow(vrow) && "type" %in% names(vrow) &&
              !is.na(vrow$type[1])) as.character(vrow$type[1]) else "stem"

  f <- .target_facts(nm, targets_data, kind = kind)

  c(f, list(
    id         = nm,
    label      = nm,
    upstream   = as.list(edges$from[edges$to   == nm]),
    downstream = as.list(edges$to[edges$from == nm]),
    page       = paste0(if (kind == "function") "functions/" else "targets/",
                        nm, ".md"),
    x = prow$x, y = prow$y, layer = prow$layer
  ))
}
