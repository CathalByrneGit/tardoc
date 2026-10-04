---
title: Publishing
---

Documentation that lives on one laptop goes stale. A workflow ships with the
package that regenerates the docs from `_targets.R` on every push and publishes
the viewer to GitHub Pages:

```r
file.copy(
  system.file("templates", "pipeline-docs.yaml", package = "tardoc"),
  ".github/workflows/docs.yaml"
)
```

Then enable **Settings → Pages → Source: GitHub Actions**. The site rebuilds on
every push to `main`, so it cannot drift from the pipeline.

**Running the pipeline in CI is optional.** `tar_manifest()` and `tar_network()`
read `_targets.R` alone, so the docs build without a store — every page renders,
with status `Not built`. Keep the `tar_make()` step and you additionally get build
status, timings, sizes and the outdated flags. Drop it if your pipeline is slow,
needs credentials, or touches data CI cannot reach.

The template also carries an optional **staleness job** that fails the build when
a committed `tardoc/` no longer matches what `document_targets()` produces — the
same idea as the `man/` freshness check in this repository's own CI. Delete that
job if you do not commit the generated docs.

## This site dogfoods it

The [live demo](example/) is the example pipeline in
[`inst/examples/station-monitoring`](https://github.com/CathalByrneGit/tardoc/tree/main/inst/examples/station-monitoring),
built and documented by
[`.github/workflows/github-pages.yml`](https://github.com/CathalByrneGit/tardoc/blob/main/.github/workflows/github-pages.yml)
on every push to `main`. Nothing in it is hand-written, and it doubles as the
end-to-end test that `document_targets()` works on a clean machine with no store
to start from.

That workflow publishes two things from one Pages deployment: this documentation
site at the root, and the generated viewer under `example/`. For your own
pipeline repository, copy `pipeline-docs.yaml` as above rather than that file —
it builds the project at the repository root.

## Publishing the pipeline itself

A static viewer is a description of a pipeline. The next step is shipping the
pipeline: a reader opens a URL, gets the built store and the code, edits a
function, and gets a correct incremental rebuild — no R, no Docker, no server.

That works. `targets` runs under webR once it is told to read `_targets.R` in the
current session, a built example pipeline ships in 26 KB, and GitHub Pages can
host it without the cross-origin isolation headers webR is usually said to need.
The measurements, the costs, and what a `publish_webr()` command would still have
to settle are in the
[webR design note](notes/webr-feasibility.html).
