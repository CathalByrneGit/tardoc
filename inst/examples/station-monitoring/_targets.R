library(targets)
tar_source("R")

list(
  tar_target(
    raw_path,
    "data/readings.csv",
    format = "file",
    description = "Path to the raw logger export, tracked as a file target"
  ),
  tar_target(
    readings,
    read_readings(raw_path),
    description = "Raw sensor readings exactly as the logger wrote them"
  ),
  tar_target(
    clean,
    clean_readings(readings),
    description = "Readings with out-of-range values dropped and names standardised"
  ),
  tar_target(
    station_summary,
    summarise_by_station(clean)
  ),
  tar_target(
    drift_model,
    fit_drift_model(clean),
    description = "Per-station linear drift model used as a probe health check"
  ),
  tar_target(
    drift_flags,
    flag_drifting_stations(drift_model)
  ),
  tar_target(
    report,
    render_report(station_summary, drift_flags),
    description = "Final station report rendered for the operations team"
  )
)
