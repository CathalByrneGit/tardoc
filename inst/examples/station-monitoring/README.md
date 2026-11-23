# Station monitoring — example pipeline

A small, runnable `targets` pipeline used to generate the screenshots in the
project README. Seven targets and six documented functions, with a mix of
described and undescribed targets so the LLM description path has something to
fill in.

To reproduce the screenshots:

```r
setwd(system.file("examples/station-monitoring", package = "tardoc"))
targets::tar_make()          # build the store, so status and timestamps appear
tardoc::document_targets(pkg_name = "Station Monitoring Pipeline", reports = TRUE)
tardoc::view_tardoc()
```

The `report` target is a file target that writes an HTML page, so
`document_targets(reports = TRUE)` publishes it: the report's page gets an
**Open report** button, as on the [live demo](https://cathalbyrnegit.github.io/tardoc/example/).
A `tarchetypes::tar_render()` target would be published the same way.

`data/readings.csv` is synthetic — 400 rows of temperature readings across six
stations, generated with `set.seed(42)`. Nothing here is real sensor data.
