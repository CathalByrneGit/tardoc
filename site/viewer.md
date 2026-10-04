---
title: The viewer
---

`document_targets()` writes `tardoc/viewer.html`: one self-contained file that
opens in any browser with no server and no R. All pipeline content is inlined;
the rendering libraries — `marked`, `fuse.js`, and React with React Flow for the
graph — load from jsDelivr and cdnjs at pinned versions with subresource
integrity, so the page needs network access the first time it is opened and comes
from the browser cache afterwards.

```r
tardoc::document_targets(pkg_name = "My pipeline")
tardoc::view_tardoc()
```

![The tardoc viewer showing an interactive targets pipeline dependency graph](man/figures/viewer-overview.png)

Everything below was generated from the runnable example pipeline in
`inst/examples/station-monitoring` — nothing is hand-written. The
[live demo](example/) is that pipeline, rebuilt on every push.

## The pipeline graph

The home page opens on the whole pipeline: drag to pan, scroll to zoom, a
minimap, and a **show functions** toggle that adds the functions each target
calls as dashed nodes.

Clicking a node opens an inspect panel rather than navigating away.

![The inspect panel open on a target, showing its description, command, build details and neighbours](man/figures/viewer-inspect.png)

The panel shows the target's description and command, its branching `pattern`
when it is a dynamic target, any error or warnings, build details (format,
repository, iteration, last built, runtime, size), and its neighbours as
clickable chips. **Open full page →** navigates the viewer to that target.

The graph is React Flow, not mermaid — the
[design note](notes/visualisation-prototypes.html) has the reasoning, what a node
exposes, and where the branching fields come from. The generated `.md` files
still carry a `mermaid` fence so they render on GitHub and anywhere else markdown
is read; the viewer replaces that fence with a live graph built from the same
data.

## Freshness, not just errors

Every target is classified `Up-to-date`, `Outdated`, `Errored` or `Not built`.
Outdated comes from
[`tar_outdated()`](https://docs.ropensci.org/targets/reference/tar_outdated.html):
a target whose command, dependencies or upstream targets changed since it was
built, even though it never errored.

![The viewer after an upstream function changed: two targets up to date, five marked outdated](man/figures/viewer-outdated.png)

Staleness propagates. Editing one function marked `clean` and everything
downstream of it outdated, while `raw_path` and `readings` stayed current — the
distinction an error-only status cannot draw.

## Target pages

![A target page showing status, command, functions called and a local dependency graph](man/figures/viewer-target.png)

Per target: status, last built, what it did on the last run, branching pattern,
runtime, size, errors, warnings, the R command, the functions it calls, and a
local dependency graph centred on that target with its immediate upstream and
downstream neighbours. Functions appear with a dashed border and a `function`
label; clicking any neighbour navigates to it.

A dynamic target additionally lists **each branch** with its own runtime, size
and error. Failed branches are always listed, however many branches there are.

Deep links work: `viewer.html#targets:clean` opens that page directly, and
selecting a page updates the hash.

## Function pages

![A function page showing rendered roxygen documentation above the function source](man/figures/viewer-function.png)

Roxygen is rendered to HTML — title, description, arguments, return value — with
the **verbatim source** underneath: comments, blank lines and the author's own
formatting intact. The source is read from the file by srcref rather than
reconstructed with `deparse()`, which discards every comment inside a function.

Code blocks over 40 lines are clamped with a *Show all N lines* control, and
every block has an **Expand** pop-out for a full-screen read.

![A long function clamped, with a fade, a Show all 113 lines bar and an Expand button in the corner](man/figures/viewer-code-clamp.png)

A 113-line function: clamped from 2.6 screens to 1.5, with the full text one
click away and a pop-out for reading it at full width. Short blocks are left
exactly as they are — the median function in real R code is about a dozen lines,
and capping those would add a scrollbar to something that already fits.

## Search

![Fuzzy search results across targets and functions](man/figures/viewer-search.png)

Fuse.js indexes names, descriptions and commands across targets and functions
together, since you rarely know in advance whether what you want is a target or
the function behind it. It is weighted toward names, so exact matches rank first.

## Where the time goes

![The critical path highlighted on the graph, with the run diff and the slowest and largest targets below](man/figures/viewer-profile.png)

- **The critical path** — the longest dependency chain, whose total is the floor
  on a full rebuild however many workers you give it. Toggling it on the graph
  dims everything off that chain.
- **Slowest and largest targets** — every bar is a link to that target's page.
- **Since the last build** — what rebuilt, what changed status, what got
  meaningfully slower or larger. One snapshot per build is appended to
  `tardoc/history.json`, and only when something differs from the previous build.

## LLM-generated descriptions

```r
# Auto-generate descriptions for undescribed targets and explain all functions
# Reads OPENAI_API_KEY env var by default
tardoc::document_targets(llm = TRUE)

# Ollama - local, free, no API key
tardoc::document_targets(llm = TRUE, llm_provider = "ollama", llm_model = "llama3.2")

# Anthropic
tardoc::document_targets(llm = TRUE, llm_provider = "anthropic")

# llama.cpp or any OpenAI-compatible server
tardoc::document_targets(
  llm          = TRUE,
  llm_provider = "openai_compatible",
  llm_base_url = "http://localhost:8080/v1",
  llm_model    = "my-model"
)

# Pass an ellmer Chat object directly
tardoc::document_targets(llm = TRUE, llm_chat = ellmer::chat_groq())
```

Requires [ellmer](https://ellmer.tidyverse.org/). Calls are made only for
targets where `description = ""` and for every function page, and the results are
written back into the `.md` files inside the generated block — so they are
reviewable in a diff, and editable.

## On large pipelines

Checked against a synthetic pipeline of **420 targets and 120 functions**.

A flat sidebar does not survive that: it was 420 rows and 12,600px of scroll, of
which a 900px viewport showed 7%. The default list is grouped by status and
capped at 40 — **errored and outdated targets are never truncated**, because they
are the reason you opened the page, while the healthy majority is summarised as
*Showing 40 of 420 · show all*. Functions group by the file that defines them.

![The sidebar grouped by status: five outdated targets listed first, then the two that are up to date](man/figures/viewer-sidebar-groups.png)

The default view answers "what needs attention" rather than listing everything
alphabetically. Navigating to something the cap hides pins it at the top under
**Current**, so the sidebar always shows where you are. Search reaches the rest.

### Grouping the graph

420 nodes in a layered layout is a line nobody can read. When tardoc can find a
grouping worth offering, the overview gets a **group** toggle that collapses it to
one node per group; clicking a group drills into it, and *back to groups*
returns. The flat graph stays the default — grouping is an option, not a rewrite
of the view.

![The 420-target pipeline collapsed to six group nodes, each labelled with its file and target count](man/figures/viewer-grouped.png)

The groups are found rather than configured. `target_groups()` tries four signals
in descending order of authority and takes the first that clears a quality bar:

| Signal | What it uses |
|---|---|
| `declaration` | The file each target is declared in — parsed from `_targets.R` and everything it sources. A project split into `targets/ingest.R`, `targets/model.R` has already declared its grouping |
| `functions` | The source file of the functions a target calls |
| `prefix` | A shared name prefix: `ingest_01`, `ingest_02` → `ingest` |
| `depth` | Bands of dependency depth. A last resort |

A grouping only counts if it has 2–20 groups, averages at least three members
each, and has no group holding more than 70% of the pipeline — so a bad grouping
is rejected rather than shown. Below 15 targets `auto` does not group at all:
seven targets read fine as a list.

**Authority beats arithmetic.** On a long chain, depth bands score *better* than a
name prefix — six tidy bands against three uneven groups — but they are the worse
reading of the pipeline. Taking the first signal past the bar rather than the
highest-scoring one is what keeps the precedence meaningful. There is a test
pinning exactly that.

Force or disable it with `document_targets(group_by = "declaration")`,
`"prefix"`, `"none"` and so on. A named method is honoured even when it falls
short of the bar; only `"auto"` is fussy.

### Still open

The viewer is a single self-contained file — 1.1 MB for the 420-target pipeline —
and it grows with the number of pages. Roughly a third of that is the graph
payload, much of which duplicates the search index, so slimming it is the next
move. Splitting pages into separately fetched files would scale further but costs
`file://` support, which is worth more.
