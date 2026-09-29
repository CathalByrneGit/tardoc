# Can targets run in webR, and what would that mean for tardoc?

Yes to the first, and the second is more interesting than expected: **the entire
of `document_targets()` already runs in a browser**, and making it do so took a
one-function change.

Everything below was executed in headless Chromium against webR 0.6.0 (R 4.6.0),
not inferred from documentation.

---

## Is targets available?

`repo.r-wasm.org` serves 22,741 wasm binaries for R 4.6, and `targets` 1.12.0 is
one of them. So is every package tardoc needs:

| Closure | Packages | Missing |
|---|---:|---|
| `targets` alone | 33 | none |
| tardoc's Imports + targets | **48** | none |
| \+ tier 3/4 Suggests (duckdb, httpuv, ellmer) | 192 | `curl`, `mnormt` |

Tiers 3 and 4 are moot anyway — `httpuv` and `curl` want sockets, which wasm
does not have — but tier 1, the part that matters, is fully installable.

## Does it work?

Installing `targets` and its 33 dependencies took **3.6 seconds**. Then, in the
browser, against a two-target pipeline written to webR's virtual filesystem:

| Call | Default | `callr_function = NULL` |
|---|---|---|
| `tar_manifest()` | ✗ `Cannot find R executable at /usr/lib/R/bin/R` | ✓ `seed, doubled` |
| `tar_network()` | ✗ same | ✓ 3 vertices, 2 edges |
| `tar_outdated()` | ✗ same | ✓ 2 outdated |
| `tar_make()` | ✗ same | ✓ built, `doubled = 42` |
| `tar_meta()` | ✓ | — |
| `tar_progress()` | ✓ | — |

One cause for every failure. `targets` reads `_targets.R` in a subprocess by
default, which keeps the pipeline's environment out of the caller's session.
wasm cannot spawn processes, so `callr` looks for `R.home("bin")/R`, finds
nothing, and stops. Passing `callr_function = NULL` tells `targets` to read the
pipeline in the current session instead, and everything works.

Nothing else about `targets` needed changing. The virtual filesystem, the store,
`qs` serialisation and the metadata all behave.

## What it took in tardoc

One internal function, `.callr_fn()`, and three call sites in
`load_targets_data()`.

The check is deliberately for the *capability*, not the platform:

```r
any(file.exists(file.path(R.home("bin"), c("R", "R.exe"))))
```

That is exactly what `callr` itself looks for — `FALSE` under webR, `TRUE` on
this machine — so any environment without a spawnable R gets the in-process
reader without tardoc having to know its name. Detecting `R.version$os ==
"emscripten"` would have worked too and would have been wrong: it hard-codes one
answer to a question that is really about whether a subprocess can start.

## The whole thing runs

With that change, `document_targets()` completes in the browser:

```
install tardoc + closure   5.2s
library(tardoc)            ok 0.6.0
load_targets_data          2 targets
generate target pages      2 pages
generate fn pages          double_it
search index               ok
build_dag_graph            7 nodes
pipeline_profile           critical: seed->doubled
generate_viewer            56 KB
comments survived?         TRUE
document_targets()         9 files written
outdated detected          0 outdated
```

`tar_make()` ran in the browser first, so this is documentation of a pipeline
that was *built* in the browser, with real metadata behind it.

"comments survived" is the srcref source extraction working under wasm — worth
checking, because it is the one part of tardoc that depends on how R parses
files rather than on any package.

## What it would cost

Measured from the network, cold:

| | |
|---|---:|
| R packages (49) | 31.4 MB |
| `R.wasm` | 17.2 MB |
| BLAS / LAPACK | 1.9 MB |
| webR JavaScript | 0.9 MB |
| **Total** | **51.5 MB** |

For comparison, the current tier 1 viewer loads about 300 KB of CDN libraries
and a self-contained HTML file. So a browser-native tardoc is **two orders of
magnitude** more download than the thing it would be generating.

That number decides the shape of any product built on this. It is absurd for
"open some docs". It is entirely reasonable for "paste a `_targets.R` and get
docs without installing R", where the alternative is installing R.

## So what should tardoc do?

**Keep the change.** `.callr_fn()` costs nothing on the desktop, is the correct
behaviour anywhere a subprocess cannot start, and means tardoc is not the reason
this cannot work. 511 tests still pass unchanged.

**Do not build a webR viewer.** 51.5 MB to document a pipeline whose docs are
300 KB is the wrong trade for the current product, and tiers 3 and 4 cannot
follow regardless.

**Where it would genuinely pay** is a different product from the one that
exists: a "try tardoc without installing R" page, where the visitor pastes or
uploads a `_targets.R` and gets the viewer back. There the 51.5 MB replaces an R
installation rather than a 300 KB file, and the trade inverts. Worth doing only
if lowering the trial barrier is a goal — it is a demo, not a feature.

One more consequence worth recording: because this works, **CI has an option it
did not have**. A docs build needs no R installation at all — a Node script with
webR can generate `tardoc/` from a repository. Slower than `r-lib/actions`, and
probably never worth it, but it means the Pages workflow is not the only way.

## Reproducing

The container blocks browser egress, so webR and the 49 packages were vendored
locally and served from a cross-origin-isolated static server (webR needs
`Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp` for `SharedArrayBuffer`). tardoc
itself is pure R, so it installs into webR as a binary simply by tarring an
`R CMD INSTALL` tree — no compilation involved.
