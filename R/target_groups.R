# R/target_groups.R
#
# Deciding what a pipeline's natural groups are.
#
# At 400 targets a flat graph is one long line and a flat sidebar is 12,000px
# of scroll. Both want the same thing: a handful of meaningful clusters. The
# question is where clusters come from, and the honest answer is that they are
# usually already there -- in how the author split their files, or how they
# named things -- and the job is to find them rather than invent them.
#
# Four signals in descending order of authority, and a score that decides
# between them, so a grouping is chosen on evidence rather than guessed. A
# grouping that fails to beat the bar is rejected: on a seven-target pipeline
# nothing applies, and nothing should.

#' Score how usable a grouping is
#'
#' A grouping earns its place when it has a handful of groups, none of them
#' swallowing the pipeline, and enough members per group to be worth
#' collapsing. Everything else -- one group of 400, or 400 groups of one -- is
#' a restatement of the flat list.
#'
#' @param g A character vector of group labels, one per target.
#' @param min_per_group Numeric. Mean members per group below which the
#'   grouping is rejected. Six groups across seven targets is arithmetically
#'   well balanced and completely useless, which is what this catches.
#' @param max_share Numeric. Largest share of the pipeline one group may hold.
#'   A 90/10 split is not a grouping, however good its other numbers look.
#' @return A numeric score; `-Inf` when the grouping is unusable.
#' @export
#' @examples
#' score_grouping(rep(c("a", "b", "c"), each = 5))
#' score_grouping(rep("everything", 20))       # -Inf: one group is no grouping
#' score_grouping(as.character(1:20))          # -Inf: all singletons
score_grouping <- function(g, min_per_group = 3, max_share = 0.7) {
  g <- g[!is.na(g) & nzchar(g)]
  if (!length(g)) return(-Inf)
  tab <- table(g)
  k   <- length(tab)
  n   <- sum(tab)
  if (k < 2 || k > 20 || n < 2) return(-Inf)
  if (n / k < min_per_group) return(-Inf)

  largest <- max(tab) / n
  if (largest > max_share) return(-Inf)

  singleton <- sum(tab == 1) / k
  # Peaks around six groups and falls away either side.
  balance_k <- 1 - abs(log(k / 6)) / log(6)

  1.0 * balance_k + 1.2 * (1 - largest) + 0.8 * (1 - singleton)
}

#' Work out how a pipeline's targets group
#'
#' Tries each signal in turn and takes the first that clears the bar:
#'
#' \describe{
#'   \item{`declaration`}{The file each target is declared in. This is the
#'     author's own structure -- how they chose to split `_targets.R` -- and so
#'     is preferred whenever a project has more than one such file.}
#'   \item{`functions`}{The source file of the functions a target calls.}
#'   \item{`prefix`}{A common name prefix, e.g. `ingest_01` and `ingest_02`.}
#'   \item{`depth`}{Bands of longest-path depth. A last resort: meaningful on
#'     a deep pipeline, arbitrary on a wide one.}
#' }
#'
#' @param targets_data Output of [load_targets_data()].
#' @param cfg A site config list; needed for `declaration` and `functions`.
#' @param method One of `"auto"` (score them all and pick), a specific signal,
#'   or `"none"`. A named method is honoured even when it scores poorly --
#'   the caller asked for it; `"auto"` holds the bar.
#' @param min_targets Integer. Below this many targets `"auto"` does not
#'   group at all. Grouping exists to manage scale, and a seven-target
#'   pipeline reads perfectly well as a list.
#' @param min_score Numeric. The bar a signal must clear for `"auto"` to
#'   accept it. See [score_grouping()].
#'
#' @return A list with `method`, `score`, and `groups` -- a named character
#'   vector of group label per target name. `groups` is empty when no signal
#'   produced a usable grouping.
#' @export
target_groups <- function(targets_data, cfg = NULL,
                          method = c("auto", "declaration", "functions",
                                     "prefix", "depth", "none"),
                          min_targets = 15L, min_score = 1.2) {
  method <- match.arg(method)
  none   <- list(method = "none", score = -Inf, groups = character())
  if (method == "none") return(none)

  nms <- as.character(targets_data$target_names)
  if (length(nms) < 2) return(none)
  if (method == "auto" && length(nms) < min_targets) return(none)

  candidates <- list(
    declaration = function() .group_by_declaration(nms, cfg),
    functions   = function() .group_by_functions(nms, targets_data, cfg),
    prefix      = function() .group_by_prefix(nms),
    depth       = function() .group_by_depth(nms, targets_data)
  )
  if (method != "auto") candidates <- candidates[method]

  # First past the bar, not best-scoring: the signals are listed in order of
  # authority, and a lower-authority one should not win merely by producing
  # tidier arithmetic. Depth bands will out-score a name prefix on a long
  # chain every time, and would still be the worse reading of the pipeline.
  for (nm in names(candidates)) {
    g <- tryCatch(candidates[[nm]](), error = function(e) NULL)
    if (is.null(g) || !length(g)) next
    s <- score_grouping(g)
    if (s >= min_score) return(list(method = nm, score = s, groups = g))
  }
  # An explicitly requested method is honoured even when it falls short --
  # the caller asked for it. "auto" holds the bar.
  if (method != "auto") {
    g <- tryCatch(candidates[[1]](), error = function(e) NULL)
    if (!is.null(g) && length(g)) {
      return(list(method = method, score = score_grouping(g), groups = g))
    }
  }
  none
}

# ---- signals ----------------------------------------------------------------

#' Group by the file each target is declared in
#'
#' Parses `_targets.R` and every other R file in the project, attributing each
#' `tar_target()` call to the file it appears in. Nothing in `tar_manifest()`
#' records this, but it is the strongest signal available: a project split
#' into `targets/ingest.R`, `targets/model.R` and `targets/report.R` has
#' already declared its own grouping.
#'
#' @param nms Character vector of target names.
#' @param cfg A site config list.
#' @return A named character vector, or `NULL`.
#' @keywords internal
.group_by_declaration <- function(nms, cfg) {
  if (is.null(cfg)) return(NULL)
  files <- .project_r_files(cfg)
  if (!length(files)) return(NULL)

  sites <- character()
  for (f in files) {
    for (nm in .file_declares(f)) sites[nm] <- .group_label(f, cfg)
  }
  sites <- sites[names(sites) %in% nms]
  if (!length(sites)) return(NULL)
  sites
}

#' Group by the file defining the functions a target calls
#'
#' `tar_network()` reports the functions each target depends on, and
#' `.find_function_file()` says where each is defined. A target is attributed
#' to the file supplying most of its functions.
#'
#' @param nms Character vector of target names.
#' @param targets_data Output of [load_targets_data()].
#' @param cfg A site config list.
#' @return A named character vector, or `NULL`.
#' @keywords internal
.group_by_functions <- function(nms, targets_data, cfg) {
  if (is.null(cfg)) return(NULL)
  verts <- as.data.frame(targets_data$network$vertices, stringsAsFactors = FALSE)
  if (is.null(verts$type)) return(NULL)
  fn_names <- as.character(verts$name[verts$type == "function"])
  if (!length(fn_names)) return(NULL)

  r_files <- list.files(cfg$r_scripts_dir, pattern = "\\.[Rr]$", full.names = TRUE)
  if (length(r_files) < 2) return(NULL)   # one file cannot partition anything

  home <- character()
  for (fn in fn_names) {
    f <- .find_function_file(fn, r_files)
    if (!is.null(f)) home[fn] <- basename(f)
  }
  if (!length(home)) return(NULL)

  edges <- targets_data$network$edges
  out <- character()
  for (nm in nms) {
    callers <- as.character(edges$from[edges$to == nm])
    files   <- home[intersect(callers, names(home))]
    if (length(files)) out[nm] <- names(sort(table(files), decreasing = TRUE))[1]
  }
  if (!length(out)) NULL else out
}

#' Group by a shared name prefix
#'
#' `ingest_01`, `ingest_02`, `model_01` group as `ingest` and `model`. Cheap,
#' and hostage to the author's naming -- which is why it sits below the two
#' structural signals rather than above them.
#'
#' @param nms Character vector of target names.
#' @param sep Character. The separator to split on.
#' @return A named character vector, or `NULL` when any name lacks the
#'   separator: a partial split is worse than none.
#' @keywords internal
.group_by_prefix <- function(nms, sep = "_") {
  pat <- paste0("^([^", sep, "]+)", sep, ".+$")
  p   <- sub(pat, "\\1", nms)
  if (any(p == nms)) return(NULL)
  stats::setNames(p, nms)
}

#' Group by bands of dependency depth
#'
#' The fallback. On a deep pipeline "stage 1 / stage 2" is a real reading of
#' the structure; on a wide one it is arbitrary, which the score will catch.
#'
#' @param nms Character vector of target names.
#' @param targets_data Output of [load_targets_data()].
#' @param bands Integer. How many bands to cut the depth range into.
#' @return A named character vector, or `NULL`.
#' @keywords internal
.group_by_depth <- function(nms, targets_data, bands = 6L) {
  edges <- targets_data$network$edges
  pos <- dag_layout(nms, data.frame(from = as.character(edges$from),
                                    to   = as.character(edges$to),
                                    stringsAsFactors = FALSE))
  if (!nrow(pos)) return(NULL)
  span <- max(pos$layer) - min(pos$layer) + 1L
  if (span < 2) return(NULL)
  k    <- min(bands, span)
  cuts <- cut(pos$layer, breaks = k, labels = FALSE)
  stats::setNames(paste0("stage ", cuts), pos$name)
}

# ---- helpers ----------------------------------------------------------------

#' R files belonging to the project, excluding generated output
#' @param cfg A site config list.
#' @return A character vector of paths.
#' @keywords internal
.project_r_files <- function(cfg) {
  files <- list.files(cfg$project_path, pattern = "\\.[Rr]$",
                      recursive = TRUE, full.names = TRUE)
  # The store holds serialised objects and the site directory holds our own
  # output; neither declares targets.
  drop <- c(cfg$targets_store, cfg$site_path)
  keep <- !vapply(files, function(f) {
    any(startsWith(normalizePath(f, winslash = "/", mustWork = FALSE),
                   normalizePath(drop, winslash = "/", mustWork = FALSE)))
  }, logical(1))
  unname(files[keep])
}

#' Target names declared by `tar_target()` calls in one file
#' @param path Path to an R file.
#' @return A character vector of target names, possibly empty.
#' @keywords internal
.file_declares <- function(path) {
  exprs <- tryCatch(parse(path, keep.source = FALSE), error = function(e) NULL)
  if (is.null(exprs)) return(character())

  found <- character()
  walk <- function(e) {
    if (!is.call(e)) return(invisible())
    head <- e[[1]]
    fname <- if (is.name(head)) as.character(head)
             else if (is.call(head) &&
                      as.character(head[[1]])[1] %in% c("::", ":::"))
                  as.character(head[[3]])
             else ""
    if (fname %in% c("tar_target", "tar_target_raw") && length(e) >= 2) {
      tgt <- e[[2]]
      if (is.name(tgt) || is.character(tgt)) found <<- c(found, as.character(tgt))
    }
    for (i in seq_along(e)) {
      sub <- tryCatch(e[[i]], error = function(err) NULL)
      if (!is.null(sub) && is.call(sub)) walk(sub)
    }
    invisible()
  }
  for (e in exprs) walk(e)
  unique(found)
}

#' A readable group label for a declaring file
#'
#' `_targets.R` keeps its name; anything else is shown relative to the project
#' root, so `targets/ingest.R` reads as the directory the author chose.
#'
#' @param path Path to the declaring file.
#' @param cfg A site config list.
#' @return A label string.
#' @keywords internal
.group_label <- function(path, cfg) {
  rel <- sub(paste0("^", cfg$project_path, "/?"), "",
             normalizePath(path, winslash = "/", mustWork = FALSE))
  sub("\\.[Rr]$", "", rel)
}
