# Runs once in the browser after webR has installed litedown.
#
# tardoc is pure R, so webR needs no compiler for it -- but the binary has to
# come from a WASM repository. targets and the rest of tardoc's closure are on
# repo.r-wasm.org (48 packages, nothing missing); tardoc itself comes from
# r-universe, which builds WASM binaries for the GitHub repositories it tracks.
#
# Why targets works here at all: it reads _targets.R in a subprocess by default,
# and wasm cannot spawn one. Passing callr_function = NULL reads the pipeline in
# the current session instead, and tardoc picks that path automatically when no R
# executable is present. See the webR design note on the site.

webr::install(
  c("targets", "dplyr", "purrr", "roxygen2", "Rd2md", "jsonlite", "rlang",
    "withr"),
  repos = "https://repo.r-wasm.org"
)

ok <- tryCatch({
  webr::install(
    "tardoc",
    repos = c("https://cathalbyrnegit.r-universe.dev", "https://repo.r-wasm.org")
  )
  requireNamespace("tardoc", quietly = TRUE)
}, error = function(e) FALSE)

if (!isTRUE(ok)) message(
  "tardoc could not be installed from r-universe, so the examples below will ",
  "not run. Everything else in this playground still works."
)
