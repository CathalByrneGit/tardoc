# R/load_targets_data.R

#' Load all targets project data
#'
#' `tar_manifest()` and `tar_network()` only require `_targets.R` to exist —
#' they parse the pipeline definition without needing a store. `tar_meta()`
#' requires the store (i.e. the pipeline has been run at least once) and
#' provides run history: status, timestamps, and errors. If no store is found
#' `meta` is filled with `NA`s so all downstream functions still work.
#'
#' @param cfg A site config list produced by [build_site_config()].
#'
#' @return A named list with:
#' \describe{
#'   \item{meta}{Tibble of target metadata. Status/time columns are `NA` if
#'     no store exists.}
#'   \item{target_names}{Character vector of stem/pattern target names.}
#'   \item{network}{List from [targets::tar_network()].}
#'   \item{manifest}{Tibble from [targets::tar_manifest()].}
#'   \item{has_store}{Logical. Whether a store was found.}
#' }
#' @export
load_targets_data <- function(cfg) {
  # All targets:: calls must run from the project directory so they find
  # _targets.R and the store, regardless of the caller's working directory.
  withr::with_dir(cfg$project_path, {
    targets::tar_config_set(store = cfg$targets_store)

    # These two only need _targets.R ---------------------------------------
    manifest     <<- targets::tar_manifest()
    network      <<- targets::tar_network(targets_only = FALSE, reporter = "silent")
    target_names <<- dplyr::pull(manifest, name)

    # Meta needs the store -------------------------------------------------
    has_store <<- file.exists(cfg$targets_store)

    if (has_store) {
      meta <<- targets::tar_meta(fields = targets::everything())
      message("Store found — run metadata loaded.")
    } else {
      message("No store found — status and timestamps will be unavailable.")
      meta <<- .empty_meta(target_names)
    }
  })

  message("Loaded ", length(target_names), " targets.")

  list(
    meta         = meta,
    target_names = target_names,
    network      = network,
    manifest     = manifest,
    has_store    = has_store
  )
}

# ---- private ----------------------------------------------------------------

#' Build a meta tibble of NAs when no store exists
#' @keywords internal
.empty_meta <- function(target_names) {
  dplyr::tibble(
    name   = target_names,
    type   = "stem",
    time   = NA_character_,
    error  = NA_character_,
    bytes  = NA_real_,
    format = NA_character_
  )
}
