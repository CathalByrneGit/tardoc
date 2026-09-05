# Two visualisation prototypes

Working code, not a proposal. Both came out of reading
[dplyneage](https://github.com/tgerke/dplyneage) and
[blockr](https://github.com/BristolMyersSquibb/blockr.core), and both are
additive — nothing existing changed, and `document_targets()` still produces
exactly what it did before.

| | From | Status |
|---|---|---|
| React Flow pipeline graph | dplyneage | Working, rendered, screenshotted |
| shinylive.io URL embedding | blockr / roxy.shinylive | Working, encoding verified; live render **not** verified here |

---

## 1. React Flow instead of mermaid

`generate_reactflow_graph()` writes `reactflow_graph.html` — the target DAG as
an interactive graph.

![The target DAG rendered with React Flow: layered nodes with status colouring, minimap and zoom controls](figures/reactflow-graph.png)

### Why

mermaid is the single heaviest thing tardoc's viewer loads.

| Asset | Size |
|---|---:|
| `mermaid@11.17.2` | **3,488.9 KB** |
| `reactflow@11.11.4` UMD | 151.6 KB |
| `react-dom@18.3.1` UMD | 128.7 KB |
| `react@18.3.1` UMD | 10.5 KB |
| React Flow `style.css` | 9.0 KB |
| **React Flow total** | **299.8 KB** |

**11.6× smaller**, and the result is genuinely interactive: drag nodes, pan,
zoom, minimap, per-node status colouring — rather than a static SVG inside the
expand-modal the current viewer hand-rolls around mermaid.

The generated page itself is 6.3 KB for the example pipeline.

### The cost, stated plainly

**React Flow does no layout.** Every node must arrive with an `(x, y)`. mermaid
does that for you, and giving it up is the real price of the swap.

It is a small price here because a targets pipeline is a layered DAG.
`dag_layout()` assigns each node a column by longest-path depth from a root,
stacks nodes within a column, and centres each column against the tallest. That
is ~40 lines, and it is the same approach dplyneage uses in its
`layout_positions()`.

```r
dag_layout(
  nodes = c("a", "b", "c"),
  edges = data.frame(from = c("a", "b"), to = c("b", "c"))
)
#>   name layer   x  y
#> 1    a     0   0  0
#> 2    b     1 220  0
#> 3    c     2 440  0
```

`build_dag_graph()` turns `load_targets_data()` output into the
`{nodes, edges}` shape the page consumes.

### One finding worth recording

**Use React Flow v11, not v12.** The v12 UMD build's browser branch expects a
`jsxRuntime` global:

```js
t((e=globalThis).ReactFlow={}, e.jsxRuntime, e.React, e.ReactDOM)
```

React 18's UMD build does not expose one (checked — no `jsxRuntime` in the
bundle), so v12 needs a shim or a bundler. v11 asks only for `React` and
`ReactDOM` and drops straight in.

That is also why dplyneage ships its own 347 KB webpack bundle with React rolled
in. tardoc doesn't need to: v11's UMD loads from CDN with subresource integrity,
matching how `viewer.html` already loads mermaid and fuse.js.

### Not done

This is a **separate page**, not a replacement. `viewer.html` still uses mermaid
for both the overview and the per-target graphs. Swapping it properly means
porting the per-target local graphs and the expand modal too, and deciding
whether to keep mermaid for the markdown pages, which embed ```mermaid fences.

---

## 2. Embedding live Shiny demos without hosting anything

`shinylive_url()` and `shinylive_iframe()` compress app source into a
`https://shinylive.io/r/app/#code=…` fragment. shinylive.io supplies the webR
runtime, so the documentation page carries only a URL.

```r
shinylive_iframe(list("app.R" = readLines("demo/app.R")), height = "500px")
```

This is blockr's pattern, via
[`roxy.shinylive`](https://github.com/insightsengineering/roxy.shinylive), which
does the same thing behind an `@examplesShinylive` roxygen tag.

### Why it matters

A previous evaluation (on the `claude/shinylive-evaluation` branch) measured the
**self-hosted** route — `shinylive::export()` — at **66–77 MB** plus a server
setting cross-origin isolation headers, and recommended against adopting it.

The URL route has a completely different cost profile. Nothing is hosted; the
page holds a string. For a documentation generator that wants a runnable example
on a function page, that is a far better fit than the "replace tier 3" framing
that was rejected.

The trade is real, not absent:

- the page needs internet access when viewed, so this can never belong in tier 1
- it depends on a third party staying up
- the app's source travels in the URL, so nothing private belongs in it
- URLs grow with app size; a large app makes an unwieldy link

### What is verified, and what is not

**Verified:** the encoding round-trips. Tests compress a payload, decompress it
back and assert the files match exactly — including multi-file apps and
multi-line sources. shinylive.io will only run what it can decode, so this is
the property that matters most.

**Not verified:** that shinylive.io actually renders these URLs. Chromium's
outbound network is blocked in the container this was built in (`curl` reaches
`shinylive.io` fine and returns 200; the browser gets `ERR_CONNECTION_RESET`
with and without the proxy). The format matches what roxy.shinylive documents,
but **someone should open one of these URLs in a real browser before this is
relied on.**

---

## Reproducing

```r
# React Flow graph for the bundled example pipeline
setwd(system.file("examples/station-monitoring", package = "tardoc"))
targets::tar_make()
cfg <- build_site_config(".")
generate_reactflow_graph(load_targets_data(cfg), cfg, "Station Monitoring Pipeline")

# A shinylive URL
shinylive_url("library(shiny)\nshinyApp(fluidPage('hi'), function(i, o) {})")
```

Both are exported and covered by tests (`test-dag_layout.R`,
`test-shinylive_url.R`). `lzstring` is in `Suggests` and guarded with
`requireNamespace()`, like `duckdb` and `ellmer`.
