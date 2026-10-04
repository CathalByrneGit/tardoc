# Quack remote access

Tier 3 serves `tardoc.duckdb` over [Quack](https://duckdb.org/2026/05/12/quack-remote-protocol),
so the browser runs SQL against the live database instead of an embedded
snapshot. This note records why that path did not work, what changed, and the
one constraint still outstanding.

Prompted by [tgerke's ducklake-r write-up](https://tgerke.github.io/ducklake-r/articles/quack-remote-access.html),
whose first line — quack is a *core* extension as of DuckDB 1.5.3 — is what
surfaced the first bug.

## What was broken

**The extension came from the wrong repository.** Both the R server and the
browser client ran `INSTALL quack FROM core_nightly`. That repository no longer
carries quack, for any platform or engine version:

| URL | Status |
|---|---|
| `nightly-extensions.duckdb.org/v1.5.5/linux_amd64/quack.duckdb_extension.gz` | 403 |
| `nightly-extensions.duckdb.org/v1.5.5/wasm_eh/quack.duckdb_extension.wasm` | 403 |
| `extensions.duckdb.org/v1.5.5/linux_amd64/quack.duckdb_extension.gz` | 200 |
| `extensions.duckdb.org/v1.4.3/wasm_eh/quack.duckdb_extension.wasm` | 200 |

In R the nightly install raises `HTTP Error: Failed to download extension
"quack"`. Now both sides `LOAD quack;` and fall back to a plain `INSTALL
quack;` against the default repository.

**The server process exited about a second after starting.** `quack_serve()`
returns as soon as the listener is bound — the server runs on a thread inside
the DuckDB instance, which is what "runs in the background of the DuckDB
instance" means in the article. The `callr::r_bg()` function therefore fell off
its own end, and callr exits the process when its function returns. Measured on
a reproduction of the original call: **exit at t=1.34s, status 0.**

The old readiness check was `Sys.sleep(1.5)` then `is_alive()` — a race against
that exit, and in any case liveness says nothing about whether the port is
bound. Two changes: the background function now parks (`repeat Sys.sleep`) so
the server outlives `quack_serve()`, and `.await_quack()` polls the port with
`socketConnection()` until it accepts, reporting the process's last stderr line
if it died. A real start takes about **4 seconds**, most of it the one-off
extension install — longer than the 1.5s the old code allowed even without the
exit bug.

**The browser hid the failure.** The attach was wrapped in a bare
`catch { loadJson() }`, so a dead server looked exactly like an ordinary
snapshot. The reason is now logged to the console and attached to the JSON
chip's tooltip.

## What still constrains it

The client needs a DuckDB engine of **1.5.3 or newer**. Verified in a headless
browser against a live Quack server:

| duckdb-wasm | engine | `LOAD quack` | `CREATE SECRET (TYPE quack)` | `ATTACH` |
|---|---|---|---|---|
| 1.32.0 (newest stable) | 1.4.3 | ok | **`Secret type 'quack' not found`** | — |
| 1.33.1-dev64.0 | 1.5.5 | ok | ok | ok, rows returned |

So the extension loads on 1.4.3 but the engine has no quack secret type, and
there is no way to authenticate. `1.32.0` is the newest stable
`@duckdb/duckdb-wasm`; every build carrying 1.5.x is a prerelease. The viewer
stays on the stable pin, which means tier 3 currently serves the JSON snapshot
— rebuilt on each `view_tardoc_db()` call, so current, just not live.

The R-side server is unaffected: it is a normal Quack server, and any DuckDB
1.5.3+ client can attach to it.

```r
con <- duckdb::dbConnect(duckdb::duckdb())
DBI::dbExecute(con, "INSTALL quack; LOAD quack;")
DBI::dbExecute(con, "CREATE SECRET qs (TYPE quack, TOKEN '<token printed at startup>');")
DBI::dbExecute(con, "ATTACH 'quack:localhost:9494' AS tardoc (READ_ONLY);")
DBI::dbGetQuery(con, "SELECT name, status FROM tardoc.targets")
```

When a stable duckdb-wasm ships 1.5.3 or newer, bumping the pin in
`inst/templates/analytics.html` is the only change needed.

## How this was checked

The container blocks browser egress to `extensions.duckdb.org`, so the wasm
tests vendored `@duckdb/duckdb-wasm` locally and pointed DuckDB at a local copy
of the extension repository with `SET custom_extension_repository`. Same files,
same layout, same `INSTALL` statement the template runs. The server under test
was a real `quack_serve()` over tardoc's own `tardoc.duckdb`, and the rows that
came back were the example pipeline's targets.

`tests/testthat/test-await_quack.R` pins the three `.await_quack()` outcomes —
port bound, process died, port never bound — using a plain `serverSocket()`
stand-in, so it needs neither DuckDB nor network access. It also guards both
call sites against `core_nightly` returning.
