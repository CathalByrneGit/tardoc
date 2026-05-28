# R/dependency_tracker.R

#' Get upstream and downstream dependencies for a target
#'
#' Recursively retrieves both upstream and downstream dependencies of a target
#' with independently controlled depths, and returns relevant edges.
#'
#' @param target_name  Character. Name of the target to analyse.
#' @param network_data List from [targets::tar_network()] with `vertices` and
#'   `edges` data frames.
#' @param max_depth_up   Integer. Max depth for upstream traversal. Use `Inf`
#'   for the full graph.
#' @param max_depth_down Integer. Max depth for downstream traversal.
#' @param visited_up,visited_down Internal recursion tracking vectors — leave
#'   as `NULL` when calling directly.
#'
#' @return A list with:
#' \describe{
#'   \item{upstream}{Character vector of upstream node names.}
#'   \item{downstream}{Character vector of downstream node names.}
#'   \item{edges}{Tibble of `from`/`to` edges traversed.}
#' }
#'
#' @examples
#' network_data <- list(
#'   vertices = data.frame(name = c("A", "B", "C"), type = "target"),
#'   edges    = data.frame(from = c("A", "B"), to = c("B", "C"))
#' )
#' res <- get_target_network_dependencies("B", network_data,
#'                                        max_depth_up = 1, max_depth_down = 1)
#' print(res$edges)
#'
#' @export
get_target_network_dependencies <- function(target_name,
                                            network_data,
                                            max_depth_up   = Inf,
                                            max_depth_down = Inf,
                                            visited_up     = NULL,
                                            visited_down   = NULL) {
  edges_all        <- network_data$edges
  upstream_edges   <- dplyr::tibble(from = character(), to = character())
  downstream_edges <- dplyr::tibble(from = character(), to = character())

  get_upstream <- function(node, depth, visited) {
    if (depth < 1 || node %in% visited)
      return(list(nodes = character(), edges = upstream_edges))
    visited <- c(visited, node)
    parents <- dplyr::filter(edges_all, .data$to == node)
    result  <- lapply(parents$from, get_upstream, depth = depth - 1,
                      visited = visited)
    list(
      nodes = unique(c(parents$from, unlist(lapply(result, `[[`, "nodes")))),
      edges = dplyr::bind_rows(
        dplyr::select(parents, "from", "to"),
        do.call(dplyr::bind_rows, lapply(result, `[[`, "edges"))
      )
    )
  }

  get_downstream <- function(node, depth, visited) {
    if (depth < 1 || node %in% visited)
      return(list(nodes = character(), edges = downstream_edges))
    visited  <- c(visited, node)
    children <- dplyr::filter(edges_all, .data$from == node)
    result   <- lapply(children$to, get_downstream, depth = depth - 1,
                       visited = visited)
    list(
      nodes = unique(c(children$to, unlist(lapply(result, `[[`, "nodes")))),
      edges = dplyr::bind_rows(
        dplyr::select(children, "from", "to"),
        do.call(dplyr::bind_rows, lapply(result, `[[`, "edges"))
      )
    )
  }

  up_res   <- get_upstream(target_name,   max_depth_up,   visited_up)
  down_res <- get_downstream(target_name, max_depth_down, visited_down)

  list(
    upstream   = up_res$nodes,
    downstream = down_res$nodes,
    edges      = dplyr::distinct(dplyr::bind_rows(up_res$edges, down_res$edges))
  )
}
