# tardoc

Auto-generate documentation for any [targets](https://docs.ropensci.org/targets/) pipeline. Point tardoc at your project and get structured markdown, a browsable HTML viewer, and — optionally — a full analytics stack with SQL queries, semantic search, git history, code intelligence, and an LLM chat interface.

---

## Four tiers, all from one command

```r
tardoc::document_targets(pkg_name = "My pipeline")
```

This generates everything. Which tier you _use_ depends on how much you need.

| Tier | How | Server? | Extra packages |
|---|---|---|---|
| **1 — Static viewer** | `view_tardoc()` | No — `file://` | None |
| **2 — WASM analytics** | `view_wasm_analytics()` | No — `file://` | None (CDN) |
| **3 — Server analytics** | `view_tardoc_db()` | Yes | duckdb, callr, httpuv |
| **4 — LLM chat** | `view_tardoc_db(llm_chat=...)` | Yes | + ellmer |

MCP (bonus): `serve_tardoc_mcp()` exposes the database to Claude Desktop and Claude Code.

---



## Tier 1 — Static viewer

```r
tardoc::document_targets(pkg_name = "My pipeline")
tardoc::view_tardoc()
```

Writes `tardoc/viewer.html` — a single self-contained file that opens in any browser with no internet connection, no server, and no dependencies beyond what `document_targets()` already requires.

**Output structure:**

```
my_project/
├── llms.txt
└── tardoc/
    ├── viewer.html              self-contained, opens as file://
    ├── search_index.json
    ├── targets/
    │   └── clean_data.md        one .md per target
    ├── functions/
    │   └── clean_raw.md         one .md per function
    └── notes/
        ├── targets/clean_data.md    yours — never overwritten
        └── functions/clean_raw.md
```

**What the viewer includes:**

- Fuzzy search across targets, functions, descriptions, and commands
- Per target: R command, build status, last built timestamp, functions called, mermaid local dependency graph
- Per function: rendered roxygen docs, full source code
- Notes panel — content from `notes/` files appears at the bottom of each page

**Notes:**

Stub files are created under `tardoc/notes/` on first run and never touched again. Edit them freely — they are embedded into the viewer on the next `document_targets()` run.

**Marker preservation:**

Generated content sits between `<!-- tardoc:generated -->` markers. Anything you write outside those markers in the `.md` files survives re-runs.

**`llms.txt`:**

Written at the project root following [llmstxt.org](https://llmstxt.org). Paste it into any LLM conversation for instant pipeline context — no indexing required.

**With LLM-generated descriptions:**

```r
# Auto-generate descriptions for undescribed targets and explain all functions
# Reads OPENAI_API_KEY env var by default
tardoc::document_targets(llm = TRUE)

# Ollama — local, free, no API key
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

Requires [`ellmer`](https://ellmer.tidyverse.org/). LLM calls only happen for targets where `description = ""` and for every function page. Results are written back into the `.md` files inside the generated block.

---

## Tier 2 — WASM analytics viewer

```r
tardoc::view_wasm_analytics()
```

Opens `tardoc/wasm_analytics.html` — a self-contained HTML file that embeds all pipeline data and loads [DuckDB WASM](https://duckdb.org/docs/api/wasm/overview.html) from CDN. Opens as `file://`. No R process, no server, no installation required on the viewer's side.

This is the right tier for:
- Sharing docs with stakeholders who don't have R installed
- Deploying to GitHub Pages or any static host
- Including analytics in CI-generated documentation sites

**What you get beyond the static viewer:**

- **Full SQL editor** against `targets`, `functions`, and `edges` tables
- **dplyr syntax** — the dplyr DuckDB community extension is loaded automatically
- **BM25 full-text search** — scores results by relevance, not just fuzzy matching
- **Recursive lineage queries** — upstream / downstream at any depth via CTEs
- **Pre-built queries** — status summary, errored targets, most connected, missing descriptions, function usage

**With code intelligence (if built):** a Call graph tab shows which functions call which, along with complexity metrics. A Git history tab shows recent commits touching R files.

```sql
-- Examples of what you can write in the SQL editor:
targets %>% filter(status == "errored") %>% select(name, command, last_built)

WITH RECURSIVE up AS (
  SELECT from_target name, 1 depth FROM edges WHERE to_target = 'report'
  UNION ALL
  SELECT e.from_target, u.depth+1 FROM edges e JOIN up u ON e.to_target = u.name
)
SELECT DISTINCT name, depth FROM up ORDER BY depth, name
```

> **Note:** The viewer shows a "Snapshot" banner. The data was embedded at `document_targets()` time. Re-run to update it.

---

## Tier 3 — Server analytics viewer

```r
install.packages(c("duckdb", "callr", "DBI", "httpuv"))
tardoc::view_tardoc_db()
```

Starts two local services:

- A **DuckDB Quack server** (`callr::r_bg()`) serving `tardoc/tardoc.duckdb` on port 9494. The browser DuckDB WASM connects directly using the [Quack protocol](https://duckdb.org/2026/05/12/quack-remote-protocol) — all queries run server-side.
- A minimal **httpuv** server on port 9000 delivering the session HTML.

Falls back to WASM + JSON mode if Quack is unavailable.

**Additional capabilities over Tier 2:**

- **Semantic search** — if `quackformers` and `faiss` were available at build time, BERT embeddings (all-MiniLM-L6-v2, 384-dim) and a HNSW32 FAISS index are stored in the database. "Find targets related to outlier removal" works even when those words don't appear in descriptions.
- **Live data** — queries run against the current database state, not a snapshot
- **Code intelligence** — `sitting_duck` (R code AST via tree-sitter) and `duck_tails` (git history) run at build time and are served from the database

**`tardoc.duckdb` capability flags** — check what was built:

```r
con  <- duckdb::dbConnect(duckdb::duckdb(), "tardoc/tardoc.duckdb", read_only = TRUE)
DBI::dbGetQuery(con, "SELECT * FROM _meta")
#   has_fts  has_embeddings  has_faiss  has_ast  has_git  has_mcp
#      TRUE           FALSE      FALSE     TRUE     TRUE     TRUE
```

**Community extensions used at build time (all optional):**

| Extension | Provides | Install |
|---|---|---|
| `quackformers` | BERT embeddings | `INSTALL quackformers FROM community` |
| `faiss` | HNSW32 ANN index | `INSTALL faiss FROM community` |
| `sitting_duck` | R code AST → function call graph | `INSTALL sitting_duck FROM community` |
| `duck_tails` | Git history | `INSTALL duck_tails FROM community` |
| `duckdb_mcp` | MCP server + config | `INSTALL duckdb_mcp FROM community` |

These are installed automatically inside the DuckDB process at build time when the R `duckdb` package is available. Each step is wrapped in `tryCatch` — if an extension is unavailable the build continues and `_meta` records the result.

---

## Tier 4 — LLM chat

```r
# Cloud providers
tardoc::view_tardoc_db(llm_chat = ellmer::chat_openai())
tardoc::view_tardoc_db(llm_chat = ellmer::chat_anthropic())
tardoc::view_tardoc_db(llm_chat = ellmer::chat_google_gemini())

# Local — Ollama (free, manages models)
tardoc::view_tardoc_db(llm_chat = ellmer::chat_ollama("llama3.2"))

# Local — llama.cpp server
tardoc::view_tardoc_db(
  llm_chat = ellmer::chat_openai_compatible(
    base_url = "http://localhost:8080/v1",
    model    = "my-model"
  )
)
```

Adds a **Chat** tab to the analytics viewer. The LLM runs entirely server-side via [ellmer](https://ellmer.tidyverse.org/) — no API keys in the browser, no provider-specific JavaScript.

The browser sends a plain text message to the `/chat` httpuv endpoint. ellmer processes it with a `run_sql` tool registered against the live DuckDB connection. The LLM decides whether to run one query, several queries, or just answer from context. All SQL executed is shown inline in the chat alongside the LLM's interpretation.

**Built-in conversation starters:**

- **Onboarding** — "Give me an overview of this pipeline, the main data flow, and targets I should know about first"
- **Impact analysis** — "If I change how `clean_data` works, which downstream targets would be affected and why?"
- **Health check** — "Are there any problems? Look for errored targets, missing descriptions, or anything unusual"
- **Explore** — "What are the most critical targets — the ones that the most downstream work depends on?"

**Provider support via ellmer:**

| Call | Provider |
|---|---|
| `ellmer::chat_openai()` | OpenAI — reads `OPENAI_API_KEY` |
| `ellmer::chat_anthropic()` | Anthropic — reads `ANTHROPIC_API_KEY` |
| `ellmer::chat_ollama("llama3.2")` | Ollama — local, free, no key |
| `ellmer::chat_openai_compatible(base_url=...)` | llama.cpp, vLLM, any OAI-compatible |
| `ellmer::chat_google_gemini()` | Google Gemini |

> **Local model caveat:** Description and explanation generation (`llm = TRUE`) are simple completions that work with any model. The analytics chat requires reliable tool calling, which smaller local models handle inconsistently. Cloud models (GPT-4o, Claude, Gemini) work well.

---

## MCP — Claude Desktop and Claude Code

```r
tardoc::serve_tardoc_mcp()
```

Starts the `duckdb_mcp` extension as an MCP server, exposing `tardoc.duckdb` as a live data source. Prints a config snippet to paste into your Claude Desktop `claude_desktop_config.json`. Once configured, Claude Desktop and Claude Code can query the pipeline database directly via tool use — no tardoc viewer needed.

A `tardoc/tardoc_mcp_config.json` file is also written at `document_targets()` time for reference.

**What this enables:**

In Claude Desktop or Claude Code, questions like *"which targets depend on `clean_raw`?"* or *"show me all errored targets"* are answered by running SQL against the live database rather than relying on the LLM's context window.

---

## Full function reference

### `document_targets()`

| Argument | Default | Description |
|---|---|---|
| `project_path` | `"."` | Targets project root |
| `site_dir` | `"tardoc"` | Output subfolder |
| `pkg_name` | `"targets docs"` | Title in viewer headers |
| `pkg_desc` | `""` | Description for `llms.txt` |
| `repo_url` | `NULL` | Repo base URL for source links, e.g. `"https://github.com/user/repo/blob/main/"` |
| `llm` | `FALSE` | Auto-generate missing descriptions and function explanations |
| `llm_chat` | `NULL` | Pre-configured ellmer Chat object |
| `llm_provider` | `"openai"` | `"openai"`, `"anthropic"`, `"ollama"`, `"openai_compatible"` |
| `llm_model` | `NULL` | Model name — NULL uses ellmer's default |
| `llm_api_key` | `NULL` | API key — NULL reads env var |
| `llm_base_url` | `NULL` | Base URL for `openai_compatible` |

### `view_tardoc()`

Opens `viewer.html` as `file://`. No server. No dependencies.

### `view_wasm_analytics()`

Opens `wasm_analytics.html` as `file://`. DuckDB WASM from CDN. Data embedded at build time.

### `view_tardoc_db()`

| Argument | Default | Description |
|---|---|---|
| `port` | `9000` | httpuv HTML server port |
| `quack_port` | `9494` | Quack DuckDB server port |
| `llm_chat` | `NULL` | ellmer Chat for the chat tab |

### `serve_tardoc_mcp()`

| Argument | Default | Description |
|---|---|---|
| `port` | `8765` | MCP server port |

### `get_fn_docs(fn_name, file)`

Returns roxygen documentation for a single function as a markdown string.

### `moxygenise(codepath, manpath)` / `moxygenise_file(file, manpath)`

Generate `.Rd` files from roxygen comments without a formal package structure.

---

## Package dependencies

### Always required (Imports)

`targets`, `dplyr`, `purrr`, `stringr`, `roxygen2`, `Rd2md`, `jsonlite`

### Optional (Suggests)

| Package | When needed |
|---|---|
| `duckdb`, `DBI` | Tier 3 server analytics + `tardoc.duckdb` generation |
| `callr` | Tier 3 background Quack server + MCP server |
| `httpuv` | Tier 3 HTML server |
| `ellmer` | `llm = TRUE` at build time, or Tier 4 chat |

---

## Does a store need to exist?

No. `tar_manifest()` and `tar_network()` only require `_targets.R`. The full documentation can be generated from a pipeline that has never been run.

If a store is present, build status and timestamps appear on target pages.

---


