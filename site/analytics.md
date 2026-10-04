---
title: Analytics, chat and MCP
---

Three optional layers sit on top of the documentation, each answering a question
the static viewer cannot: *query the pipeline*, *ask it in English*, *hand it to
an agent*. They share one artifact — `tardoc/tardoc.duckdb` — which
`document_targets()` does **not** build; `view_tardoc_db()` does, on its first
call.

| Layer | How | Server? | Extra packages |
|---|---|---|---|
| WASM analytics | `view_wasm_analytics()` | No — `file://` | None (CDN) |
| Server analytics | `view_tardoc_db()` | Yes | duckdb, callr, DBI, httpuv |
| LLM chat | `view_tardoc_db(llm_chat = ...)` | Yes | + ellmer |
| MCP | `serve_tardoc_mcp()` | Yes | duckdb, callr |

## WASM analytics — no server

```r
tardoc::view_wasm_analytics()
```

Opens `tardoc/wasm_analytics.html`: a self-contained file that embeds all pipeline
data and loads
[DuckDB WASM](https://duckdb.org/docs/api/wasm/overview.html) from CDN. It opens
as `file://` with no R process and nothing installed on the reader's side, which
makes it the right choice for sharing with people who do not have R, for static
hosting, and for CI-generated documentation.

What it adds over the static viewer:

- **A full SQL editor** against `targets`, `functions` and `edges` tables
- **dplyr syntax** — the dplyr DuckDB community extension is loaded automatically
- **BM25 full-text search**, scoring by relevance rather than fuzzy matching
- **Recursive lineage queries** — upstream or downstream at any depth
- **Pre-built queries** — status summary, errored targets, most connected,
  missing descriptions, function usage

```sql
-- Both of these work in the editor:
targets %>% filter(status == "errored") %>% select(name, command, last_built)

WITH RECURSIVE up AS (
  SELECT from_target name, 1 depth FROM edges WHERE to_target = 'report'
  UNION ALL
  SELECT e.from_target, u.depth+1 FROM edges e JOIN up u ON e.to_target = u.name
)
SELECT DISTINCT name, depth FROM up ORDER BY depth, name
```

The page shows a **Snapshot** banner, because the data was embedded at
`document_targets()` time. Re-run to update it.

## Server analytics — live queries and semantic search

```r
install.packages(c("duckdb", "callr", "DBI", "httpuv"))
tardoc::view_tardoc_db()
```

**The first call builds the database** from the same `_targets.R` and roxygen
sources, if `tardoc/tardoc.duckdb` is not already there. Later calls reuse it;
`db_extensions = TRUE` rebuilds with the community extensions.

Then two local services start:

- A **DuckDB Quack server** (`callr::r_bg()`) serving the database on port 9494.
  The browser's DuckDB WASM attaches with the
  [Quack protocol](https://duckdb.org/2026/05/12/quack-remote-protocol) and runs
  every query server-side.
- A minimal **httpuv** server on port 9000 delivering the session HTML.

`view_tardoc_db()` waits for the Quack port to accept a connection before handing
the page over — typically a few seconds, most of it the one-off extension
install. If the server does not come up it says why, and the viewer serves the
JSON snapshot instead, with the reason on the **JSON** chip's tooltip and in the
browser console.

> **Quack needs a recent DuckDB WASM.** The viewer pins the newest stable
> `@duckdb/duckdb-wasm` (1.32.0), which bundles DuckDB **1.4.3**. The `quack`
> extension loads there, but the engine has no `quack` secret type, so
> `CREATE SECRET (TYPE quack, …)` fails and the viewer falls back to JSON.
> Verified working on DuckDB **1.5.5**, which today ships only in
> `@duckdb/duckdb-wasm` prereleases. Until a stable release carries 1.5.3 or
> newer, this tier serves the snapshot — rebuilt on every `view_tardoc_db()`
> call, so it is current, just not live. The R-side server itself works: any
> DuckDB 1.5.3+ client can attach to it. Evidence, and the one-line change to
> make when a stable build ships, are in the
> [Quack design note](notes/quack-remote-access.html).

### Semantic search

Off by default. `db_extensions` is `FALSE`, so the first build installs no
community extensions. Run `view_tardoc_db(db_extensions = TRUE)` once and, if
`quackformers` and `faiss` can be installed, BERT embeddings (all-MiniLM-L6-v2,
384-dim) and a HNSW32 FAISS index are stored in the database. "Find targets
related to outlier removal" then works even when those words appear in no
description.

| Extension | Provides | Install |
|---|---|---|
| `quackformers` | BERT embeddings | `INSTALL quackformers FROM community` |
| `faiss` | HNSW32 ANN index | `INSTALL faiss FROM community` |
| `duckdb_mcp` | MCP server + config | `INSTALL duckdb_mcp FROM community` |

Each step is wrapped in `tryCatch`. If an extension is unavailable the build
continues, `_meta` records the flag, and `_meta_detail` records *why* the layer
was skipped:

```r
con <- duckdb::dbConnect(duckdb::duckdb(), "tardoc/tardoc.duckdb", read_only = TRUE)

DBI::dbGetQuery(con, "SELECT * FROM _meta")
#   has_fts  has_embeddings  has_faiss  has_mcp
#      TRUE            TRUE       TRUE     TRUE

DBI::dbGetQuery(con, "SELECT * FROM _meta_detail")
#   capability  available  reason
#   embeddings       TRUE  NA
#   faiss            TRUE  NA
#   fts              TRUE  NA
#   mcp              TRUE  NA
```

After a plain `view_tardoc_db()` only `has_fts` is `TRUE` — FTS is a core DuckDB
extension and the other three are community ones that `db_extensions` gates. A
layer that did not build carries its reason instead of `NA`: the extension
manager's own error, `requires embeddings` for FAISS when the embedding step
failed, or `db_extensions = FALSE` when you never asked for it.

The FAISS index is stored beside the database as `tardoc/*.faiss` rather than
inside it — that is how the extension persists indexes. Keep those files next to
the database; `view_tardoc_db()` reloads them on startup and disables semantic
search if they are missing.

## LLM chat

```r
# Cloud providers
tardoc::view_tardoc_db(llm_chat = ellmer::chat_openai())
tardoc::view_tardoc_db(llm_chat = ellmer::chat_anthropic())
tardoc::view_tardoc_db(llm_chat = ellmer::chat_google_gemini())

# Local - Ollama (free, manages models)
tardoc::view_tardoc_db(llm_chat = ellmer::chat_ollama("llama3.2"))

# Local - llama.cpp server
tardoc::view_tardoc_db(
  llm_chat = ellmer::chat_openai_compatible(
    base_url = "http://localhost:8080/v1",
    model    = "my-model"
  )
)
```

Adds a **Chat** tab to the analytics viewer. The LLM runs entirely server-side via
[ellmer](https://ellmer.tidyverse.org/) — no API keys in the browser, no
provider-specific JavaScript. The browser sends plain text to the `/chat` httpuv
endpoint; ellmer processes it with a `run_sql` tool registered against the live
DuckDB connection and decides whether to run one query, several, or none. Every
statement executed is shown inline in the chat beside the interpretation.

Built-in conversation starters cover onboarding ("overview of this pipeline, the
main data flow, and targets I should know about first"), impact analysis ("if I
change how `clean_data` works, which downstream targets would be affected"), a
health check, and finding the most depended-upon targets.

> **Local model caveat.** Description and explanation generation (`llm = TRUE`)
> are simple completions that work with any model. The chat requires reliable
> tool calling, which smaller local models handle inconsistently.

## MCP — Claude Desktop and Claude Code

```r
tardoc::serve_tardoc_mcp()
```

Starts the `duckdb_mcp` extension as an MCP server, exposing `tardoc.duckdb` as a
live data source, and prints a config snippet to paste into
`claude_desktop_config.json`. Questions like *"which targets depend on
`clean_raw`?"* are then answered by running SQL against the database rather than
from the model's context window.

**This needs a database built with extensions.** `serve_tardoc_mcp()` reads
`tardoc/tardoc.duckdb` and the `tardoc/tardoc_mcp_config.json` written beside it,
and both come from `view_tardoc_db(db_extensions = TRUE)` — neither is produced by
`document_targets()`.
