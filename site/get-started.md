---
title: Get started
---

## Install

```r
# install.packages("remotes")
remotes::install_github("CathalByrneGit/tardoc")
```

Nothing beyond `targets` and a handful of pure-R packages is needed for the
documentation itself. The analytics tiers are opt-in and their packages live in
`Suggests`.

## One command

From the root of a `targets` project:

```r
tardoc::document_targets(pkg_name = "My pipeline")
tardoc::view_tardoc()
```

That writes the markdown, the self-contained [viewer](viewer.html) and the WASM
analytics page, then opens the viewer as `file://`. No server, no build step.

Useful arguments:

| Argument | Default | Description |
|---|---|---|
| `project_path` | `"."` | Targets project root |
| `site_dir` | `"tardoc"` | Output subfolder |
| `pkg_name` | `"targets docs"` | Title in viewer headers |
| `pkg_desc` | `""` | Description for `llms.txt` |
| `repo_url` | `NULL` | Repo base URL for source links, e.g. `"https://github.com/user/repo/blob/main/"` |
| `group_by` | `"auto"` | Grouping signal for the graph — see [Grouping the graph](viewer.html#sec:grouping-the-graph) |
| `check_outdated` | `TRUE` | Run `tar_outdated()` for freshness status |
| `llm` | `FALSE` | Auto-generate missing descriptions and function explanations |

The full argument list, for every exported function, is on the
[manual page](manual.html).

## What it writes

```
my_project/
├── llms.txt
└── tardoc/
    ├── viewer.html              self-contained, opens as file://
    ├── wasm_analytics.html      self-contained, opens as file://
    ├── analytics.html           tier 3 shell, needs view_tardoc_db()
    ├── search_index.json
    ├── tardoc_analytics.json
    ├── history.json             one snapshot per build, for the run diff
    ├── targets/
    │   └── clean_data.md        one .md per target
    ├── functions/
    │   └── clean_raw.md         one .md per function
    └── notes/
        ├── targets/clean_data.md    yours — never overwritten
        └── functions/clean_raw.md
```

`tardoc.duckdb` is not in that list. `document_targets()` does not build it —
[`view_tardoc_db()`](analytics.html) does, on first call.

Two conventions protect your own writing:

- **Notes.** Stub files appear under `tardoc/notes/` on the first run and are
  never touched again. Edit them freely; they are embedded into the viewer on
  the next run.
- **Markers.** Generated content sits between `<!-- tardoc:generated -->`
  markers in the `.md` files. Anything you write outside them survives a re-run.

`llms.txt` is written at the project root following
[llmstxt.org](https://llmstxt.org) — paste it into any LLM conversation for
pipeline context with no indexing step.

## Does a store need to exist?

No. `tar_manifest()` and `tar_network()` only require `_targets.R`, so the full
documentation can be generated from a pipeline that has never been run.

If a store is present, build status and timestamps appear on target pages.
Without one every target reads `Not built`, which is accurate rather than a gap.

`tar_outdated()` re-hashes files and dependencies, so on a large pipeline it
costs a few seconds. Pass `document_targets(check_outdated = FALSE)` to skip it;
status then falls back to reporting errors only.

A dynamically branched target is a special case worth knowing about: its own
metadata row carries no build time — only its branches do — and its errors live
on the branch rows too. tardoc reads the branches, so a branched target that has
run reports `Up-to-date`, and one with a failed branch reports `Errored` rather
than hiding it.

## Dependencies

Always required (`Imports`): `targets`, `dplyr`, `purrr`, `roxygen2`, `Rd2md`,
`jsonlite`, `rlang`, `withr`.

Optional (`Suggests`):

| Package | When needed |
|---|---|
| `duckdb`, `DBI` | Server analytics and `tardoc.duckdb` generation |
| `callr` | Reading `_targets.R` in a subprocess; the background Quack and MCP servers |
| `httpuv` | The local HTML server behind the server analytics viewer |
| `ellmer` | `llm = TRUE` at documentation time, or the chat tab |

`callr` is a suggestion rather than an import on purpose: where no R subprocess
can be spawned — webR, for instance — tardoc reads the pipeline in the current
session instead. See the [webR note](notes/webr-feasibility.html).

## Where next

- [The viewer](viewer.html) — what every page shows, and how the sidebar and
  graph behave on a pipeline of several hundred targets.
- [Analytics, chat and MCP](analytics.html) — SQL, semantic search, an LLM chat
  tab, and the database as an MCP server.
- [Publishing](publishing.html) — regenerating the docs in CI so they cannot
  drift from the pipeline.
