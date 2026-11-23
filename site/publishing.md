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

## Publishing reports

A pipeline that ends in a rendered report — `tarchetypes::tar_render()`,
`tar_quarto()`, or any target that writes an HTML or PDF — can publish it with
the docs, so the people reading the pipeline's page can open its output.

```r
document_targets(reports = TRUE)                       # every such target
document_targets(reports = c("report", "eda"))         # only these
```

A report target is a `format = "file"` target whose recorded paths include an
`.html`, `.htm` or `.pdf`; `tar_render()` records the rendered file, its source
`.Rmd` and its `<name>_files/` folder. tardoc copies the output and its supporting
folders to `tardoc/reports/<target>/` (the source is not published), adds an
**Output** section with an **Open report** link to the target's page, and a button
to the graph's inspect panel. It opens in a new tab and works from `file://`.

What gets a link:

- **Only a target that has built without error.** A failed render never shows
  one. An out-of-date report keeps its link, marked *out of date*, so an old report
  is not mistaken for a current one.
- **Nothing without a store.** A CI run that skips `tar_make()` publishes no
  reports, because nothing has run.
- **Only paths inside the project.** A file target may name any path; one that
  points outside the project is ignored, not copied into a site that gets
  deployed.

It is off by default on purpose. A report can contain data you would not put on a
public site, and the docs folder is exactly what the Pages workflow publishes.
Turn it on knowing that, and name the targets you want rather than using `TRUE`
if you are unsure. `tardoc/reports/` is cleared on every run, so turning
`reports` off removes what was published, and a folder called `reports` that
tardoc did not create is never touched. Published reports are also listed in
`llms.txt` and the search index.

To publish them from CI, build the pipeline first — the report needs a store —
and pass `reports = TRUE` in the workflow's `document_targets()` call. Over
about 25 MB in total, tardoc warns: the reports are committed and deployed with
the docs.

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
