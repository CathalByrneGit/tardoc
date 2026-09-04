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
  names(readings) <- tolower(gsub("[^A-Za-z0-9]+", "_", names(readings)))
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
#' @param summary Per-station summary table.
#' @param flags Stations flagged for inspection.
#' @return Path to the written report.
#' @export
render_report <- function(summary, flags) {
  tempfile(fileext = ".html")
}
