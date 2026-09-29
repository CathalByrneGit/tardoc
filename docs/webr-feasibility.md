# Publishing a whole targets project to the browser

A reader opens a URL and gets the pipeline itself: the built store, the values,
the code, the docs — and can change the code and re-run it, with correct
incremental rebuild. No R, no Docker, no server.

**It works.** Everything below was executed in headless Chromium against webR
0.6.0 (R 4.6.0), not inferred from documentation.

---

## Does targets run under webR?

`repo.r-wasm.org` carries `targets` 1.12.0 for R 4.6 and every package tardoc
imports — a 48-package closure with nothing missing. Installing it takes about
four seconds in the browser.

One thing stopped it, and the same thing every time. `targets` reads
`_targets.R` in a subprocess by default, which keeps the pipeline's environment
out of the caller's session. wasm cannot spawn processes, so `callr` looks for
`R.home("bin")/R`, finds nothing, and fails:

| Call | Default | `callr_function = NULL` |
|---|---|---|
| `tar_manifest()` | ✗ `Cannot find R executable` | ✓ |
| `tar_network()` | ✗ | ✓ |
| `tar_outdated()` | ✗ | ✓ |
| `tar_make()` | ✗ | ✓ |
| `tar_meta()`, `tar_progress()` | ✓ | — |

Nothing else about `targets` needed changing. The virtual filesystem, the store,
serialisation and the metadata all behave.

## Can you ship a built project?

Yes — and the bundle is nothing. The example pipeline, source and built store
together, is **26 KB gzipped**. Untarred into webR's filesystem:

```
files unpacked                14
tar_read(station_summary)     6 rows, 2 cols
tar_read(clean)               station, temp_c, day_of_year
tar_outdated()                none - store is current
tar_meta() rows               13
tar_make() no-op              7 skipped
```

So a visitor arrives at a pipeline that is *already built*, and can read any
target's value.

## Is it live?

That is the part that matters, and yes. Editing a threshold in `R/functions.R`
from inside the browser:

```
before: clean rows            400
now outdated                  report, clean, station_summary, drift_model, drift_flags
rebuild                       5 completed, 2 skipped
after: clean rows             326
now outdated again?           none - rebuilt and current
```

`targets` invalidated exactly the five downstream targets, left the two upstream
ones alone, re-ran, and settled. Then `document_targets()` regenerated the docs
on top of the new state — 9 files, a 77 KB viewer.

This is not a demo of R in a browser. It is a targets pipeline behaving like a
targets pipeline, published as static files.

## GitHub Pages can host it

The obvious worry: webR wants `SharedArrayBuffer`, which needs
`Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers, and
**GitHub Pages cannot set headers**.

Tested on a server sending neither:

```
crossOriginIsolated: false
SharedArrayBuffer  : undefined
```

Everything above still ran — the shipped store, the edit, the rebuild, the docs.
webR 0.6's PostMessage channel covers this case. Cross-origin isolation makes it
faster; it is not required.

## What it costs

| | |
|---|---:|
| The project bundle | **26 KB** |
| `R.wasm` + BLAS/LAPACK + webR JS | 20.0 MB |
| R packages for tardoc's stack (49) | 31.4 MB |
| **Total, cold** | **51.5 MB** |

The publisher hosts the 26 KB and one HTML file. The 51.5 MB comes from
r-wasm's CDN on demand and caches, so hosting is free and the repository stays
small.

A pipeline's own packages add to it. Measured against the same index:

| Pipeline stack | Packages | Available |
|---|---:|---|
| tardoc alone | 48 | all |
| \+ tidyverse core (ggplot2, tidyr, readr, …) | 70 | all — about 16 MB more |
| \+ modelling (broom, glmnet, randomForest) | 67 | all |
| \+ `sf` | 60 | all |
| \+ `data.table` | 48 | all |
| \+ `arrow` | — | **`arrow` unavailable** |
| \+ `rstan` | — | **`rstan` unavailable** |

So a tidyverse pipeline lands around 68 MB, and the practical rule is that most
pipelines work while heavyweight compiled ones do not.

## Judging it

The right comparison is not tardoc's 300 KB viewer — it is the other ways to
hand someone a runnable pipeline. Binder needs a server and cold-starts in
minutes. Docker needs Docker. "Install R and these fourteen packages" needs R.
Against those, 51.5 MB of cached static files with no server is a good trade,
and the 26 KB bundle means the project itself costs nothing to publish.

It is a bad trade only if all the reader wanted was the docs, which the existing
viewer already delivers for 300 KB. These are two products, not one, and the
existing one should not grow 51.5 MB to become the other.

## The bug this found

Worth recording on its own, because it affects every tardoc user and nothing to
do with webR.

`load_targets_data()` called `targets::tar_config_set(store = cfg$targets_store)`.
`cfg$targets_store` is absolute, and `tar_config_set()` writes `_targets.yaml`
**in the user's project**. So running tardoc once left a line like

```yaml
main:
  store: /home/someone/analysis/_targets
```

committed in their repository — breaking the project on every other machine, in
CI, and under webR, where it is what made `tar_read()` fail on a shipped store.
Reproduced on the desktop against a project that had no `_targets.yaml` before.

It was gratuitous as well as harmful: everything in `load_targets_data()` already
runs inside the project directory via `withr::with_dir()`, where the default
relative `_targets` is what `targets` would have used anyway. The store is now
passed per call — `tar_network()`, `tar_meta()`, `tar_progress()` and
`tar_outdated()` all take `store`; `tar_manifest()` needs none, reading
`_targets.R` alone — and no `_targets.yaml` is written.

## What tardoc should do

**Keep both changes.** `.callr_fn()` and the store fix cost nothing on the
desktop, and the second is a bug fix regardless of any of this.

**A publishing command is worth building, as its own thing.** Something like
`publish_webr()` writing a directory of static files: an HTML page that boots
webR, the project tarball, and the viewer. Not a change to
`document_targets()` — the existing tiers stay as they are.

**Two things to settle before building it**, neither answered here: what the
page should look like when webR is still loading twenty seconds in, and whether
the reader gets an editor or only a re-run button. The second is a product
question, not a technical one — everything needed for either already works.

## Reproducing

The container blocks browser egress, so webR and the packages were vendored and
served locally. tardoc is pure R, so it installs into webR as a binary by
tarring an `R CMD INSTALL` tree — no compilation. Two gotchas cost time and are
worth knowing: `untar()` shells out by default and `system()` is unsupported
under Emscripten, so `tar = "internal"` is required; and webR's browser entry
point is `dist/webr.js`, not `dist/webr.mjs`, which imports Node built-ins.
