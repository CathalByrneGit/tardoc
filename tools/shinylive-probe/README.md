# shinylive probe

Reproducible harness for [`docs/shinylive-evaluation.md`](../../docs/shinylive-evaluation.md).
Nothing here is part of the tardoc package; it exists so the numbers in that
document can be re-measured instead of trusted.

| File | Purpose |
|---|---|
| `app-min/app.R` | Minimal Shiny app: `shiny` + `bslib` only. Establishes the floor. |
| `app-db/app.R`  | Opens a DuckDB connection and runs user-supplied SQL. |
| `serve.py`      | Static server that sets the COOP/COEP headers webR needs. |
| `probe.mjs`     | Boots the export in headless Chromium, times it, runs a query. |

```sh
Rscript -e 'install.packages("shinylive")'
Rscript -e 'shinylive::export("app-db", "site-db")'
du -sh site-db

python3 serve.py &     # http://127.0.0.1:8811
node probe.mjs         # requires playwright
```

Two things to know before you interpret the output:

- **The export will not run from `file://`.** It needs an HTTP server *and*
  cross-origin isolation. `serve.py` sets those headers; most static hosts do
  not.
- **The app renders inside an iframe.** Selectors against the top-level
  document find an empty body and look like a boot failure. `probe.mjs`
  searches `page.frames()` for this reason.
