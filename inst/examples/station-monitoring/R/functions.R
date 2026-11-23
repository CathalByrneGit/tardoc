#' Read the raw station readings
#'
#' Loads the raw sensor export as delivered by the logger, without any
#' cleaning. Column names are left exactly as the device writes them.
#'
#' @param path Path to the raw CSV export.
#' @return A data frame of raw readings, one row per observation.
#' @export
read_readings <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE)
}

#' Drop impossible readings and standardise column names
#'
#' Sensors occasionally emit out-of-range values when a probe is being
#' serviced. Anything outside the instrument's rated range is dropped rather
#' than imputed, so downstream counts stay honest.
#'
#' @param readings Raw readings from [read_readings()].
#' @param min_c,max_c Rated operating range of the probe, in degrees Celsius.
#' @return A cleaned data frame with snake_case names.
#' @export
clean_readings <- function(readings, min_c = -40, max_c = 85) {
  # The logger writes "Temp (C)" and "Station ID"; downstream code expects
  # snake_case, so normalise before anything else touches the frame.
  names(readings) <- tolower(gsub("[^A-Za-z0-9]+", "_", names(readings)))

  # Out-of-range values mean a probe was being serviced, not that the station
  # was that cold. Dropping is deliberate: imputing would invent readings and
  # the station counts downstream are reported as observed.
  readings[readings$temp_c >= min_c & readings$temp_c <= max_c, ]
}

#' Summarise readings by station
#'
#' Produces one row per station with the mean, minimum and maximum
#' temperature and the number of observations behind each figure.
#'
#' @param readings Cleaned readings from [clean_readings()].
#' @return A data frame with one row per station.
#' @export
summarise_by_station <- function(readings) {
  stats::aggregate(temp_c ~ station, data = readings, FUN = mean)
}

#' Fit a linear drift model per station
#'
#' Regresses temperature on day-of-year to estimate seasonal drift. Used as a
#' crude check that a probe has not started wandering.
#'
#' @param readings Cleaned readings.
#' @return An object of class `lm`.
#' @export
fit_drift_model <- function(readings) {
  stats::lm(temp_c ~ day_of_year, data = readings)
}

#' Flag stations whose drift exceeds tolerance
#'
#' @param model A fitted drift model.
#' @param tolerance Maximum acceptable drift in degrees per day.
#' @return A character vector of station identifiers needing inspection.
#' @export
flag_drifting_stations <- function(model, tolerance = 0.05) {
  if (abs(stats::coef(model)[["day_of_year"]]) > tolerance) "all" else character()
}

#' Render the station report
#'
#' Writes a small self-contained HTML page -- the summary table, a bar per
#' station and the stations flagged for inspection -- with base R alone, so the
#' example needs no rmarkdown or pandoc. A `tarchetypes::tar_render()` target
#' publishes the same way: it is a file target whose output is an HTML.
#'
#' @param summary Per-station summary table.
#' @param flags Stations flagged for inspection.
#' @param path Where to write the report.
#' @return Path to the written report.
#' @export
render_report <- function(summary, flags, path = "report/station_report.html") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  temps <- summary$temp_c
  width <- 360
  bar_w <- 20
  scale <- (width - 140) / max(abs(temps), 1)
  bars <- vapply(seq_len(nrow(summary)), function(i) {
    y <- (i - 1) * (bar_w + 6) + 4
    sprintf(paste0(
      "<text x='0' y='%d' font-size='12' fill='#444'>%s</text>",
      "<rect x='70' y='%d' width='%.1f' height='%d' rx='3' fill='#6d28d9'/>",
      "<text x='%.1f' y='%d' font-size='11' fill='#444'>%.1f \u00b0C</text>"),
      y + 14, summary$station[i], y, max(abs(temps[i]) * scale, 1), bar_w,
      74 + max(abs(temps[i]) * scale, 1), y + 14, temps[i])
  }, character(1))
  rows <- sprintf("<tr><td>%s</td><td>%.2f</td></tr>", summary$station, temps)

  writeLines(c(
    "<!doctype html><html lang='en'><head><meta charset='utf-8'>",
    "<title>Station report</title>",
    "<style>body{font:15px system-ui,sans-serif;max-width:640px;margin:2rem auto;padding:0 1rem;color:#222}",
    "table{border-collapse:collapse;width:100%}td,th{border:1px solid #ddd;padding:6px 10px;text-align:left}",
    "th{background:#f4f1fb}.flag{background:#fef3c7;padding:.6rem 1rem;border-radius:6px}</style></head><body>",
    "<h1>Station report</h1>",
    "<p>Mean temperature per station, from the readings that passed the range filter.</p>",
    sprintf("<svg width='%d' height='%d' role='img' aria-label='Mean temperature per station'>%s</svg>",
            width, nrow(summary) * (bar_w + 6) + 8, paste(bars, collapse = "")),
    "<h2>Summary</h2><table><tr><th>Station</th><th>Mean temp (\u00b0C)</th></tr>",
    rows, "</table><h2>Needs inspection</h2>",
    if (length(flags)) sprintf("<p class='flag'>Flagged: %s</p>", paste(flags, collapse = ", "))
    else "<p>No stations flagged.</p>",
    "</body></html>"
  ), path, useBytes = TRUE)
  path
}
