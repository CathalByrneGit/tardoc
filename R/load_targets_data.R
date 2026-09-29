# R/load_targets_data.R

#' Load all targets project data
#'
#' `tar_manifest()` and `tar_network()` only require `_targets.R` to exist --
#' they parse the pipeline definition without needing a store. `tar_meta()`
#' requires the store (i.e. the pipeline has been run at least once) and
#' provides run history: status, timestamps, and errors. If no store is found
#' `meta` is filled with `NA`s so all downstream functions still work.
#'
#' @param cfg A site config list produced by [build_site_config()].
#' @param check_outdated Logical. Call [targets::tar_outdated()] to find which
#'   targets are stale. This is what separates "did not error last run" from
#'   "still current": a target whose upstream changed is outdated even though
#'   it never errored. It re-hashes files and dependencies, so on a large
#'   pipeline it costs a few seconds -- pass `FALSE` to skip it and fall back
#'   to the error-only classification.
#'
#' @return A named list with:
#' \describe{
#'   \item{meta}{Tibble of target metadata. Status/time columns are `NA` if
#'     no store exists.}
#'   \item{target_names}{Character vector of stem/pattern target names.}
#'   \item{network}{List from [targets::tar_network()].}
#'   \item{manifest}{Tibble from [targets::tar_manifest()].}
#'   \item{has_store}{Logical. Whether a store was found.}
#'   \item{outdated}{Character vector of stale target names, or `NULL` when
#'     the check was skipped or failed.}
#'   \item{progress}{Tibble from [targets::tar_progress()] -- what each target
#'     did on the last run -- or `NULL` without a store.}
#' }
#' @export
load_targets_data <- function(cfg, check_outdated = TRUE) {
  # All targets:: calls must run from the project directory so they find
  # _targets.R and the store, regardless of the caller's working directory.
  withr::with_dir(cfg$project_path, {
    targets::tar_config_set(store = cfg$targets_store)

    # targets reads the pipeline in a subprocess by default, which isolates
    # _targets.R from the calling session. Where no subprocess can be spawned
    # -- webR, where R.home("bin")/R does not exist -- it reads it in place
    # instead. See .callr_fn().
    cf <- .callr_fn()

    # These two only need _targets.R ---------------------------------------
    manifest     <- targets::tar_manifest(callr_function = cf)
    network      <- targets::tar_network(targets_only = FALSE, reporter = "silent",
                                         callr_function = cf)
    target_names <- dplyr::pull(manifest, "name")

    # Meta needs the store -------------------------------------------------
    has_store <- file.exists(cfg$targets_store)

    progress <- NULL
    if (has_store) {
      meta <- targets::tar_meta(fields = targets::everything())
      progress <- tryCatch(targets::tar_progress(), error = function(e) NULL)
      message("Store found -- run metadata loaded.")
    } else {
      message("No store found -- status and timestamps will be unavailable.")
      meta <- .empty_meta(target_names)
    }

    # Staleness is a property of the pipeline definition, not the store, so
    # this is worth asking even before a first run -- it then reports every
    # target, which is correct. Wrapped because it evaluates _targets.R and a
    # pipeline that cannot be loaded should degrade, not abort the docs build.
    outdated <- NULL
    if (isTRUE(check_outdated)) {
      outdated <- tryCatch(
        as.character(targets::tar_outdated(reporter = "silent",
                                           callr_function = cf)),
        error = function(e) {
          message("Could not determine outdated targets (", conditionMessage(e),
                  ") -- falling back to error-only status.")
          NULL
        }
      )
      if (!is.null(outdated)) {
        message(length(outdated), " of ", length(target_names),
                " targets are outdated.")
      }
    }
  })

  message("Loaded ", length(target_names), " targets.")

  list(
    meta         = meta,
    target_names = target_names,
    network      = network,
    manifest     = manifest,
    has_store    = has_store,
    outdated     = outdated,
    progress     = progress
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

#' The `callr_function` to hand `targets`
#'
#' `targets` reads `_targets.R` in a subprocess by default, which keeps the
#' pipeline's environment out of the caller's session. That needs an R
#' executable, and some R builds have none: in webR, `R.home("bin")/R` does
#' not exist and every such call fails with "Cannot find R executable".
#'
#' The check is the capability rather than the platform -- it is exactly what
#' `callr` itself looks for -- so any environment without a spawnable R gets
#' the in-process reader without tardoc having to know its name.
#'
#' @return `callr::r` when a subprocess can be spawned, otherwise `NULL`,
#'   which tells `targets` to read the pipeline in the current session.
#' @keywords internal
.callr_fn <- function() {
  # callr is a hard dependency of targets, so it is present wherever targets
  # is; the guard is for the odd install where it is not.
  spawnable <- any(file.exists(file.path(R.home("bin"), c("R", "R.exe"))))
  if (spawnable && requireNamespace("callr", quietly = TRUE)) {
    return(callr::r)
  }
  NULL
}
