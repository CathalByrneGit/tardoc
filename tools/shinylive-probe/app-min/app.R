library(shiny)
library(bslib)

targets <- data.frame(
  name = c("raw_path", "readings", "clean", "station_summary",
           "drift_model", "drift_flags", "report"),
  status = "uptodate",
  command = c('"data/readings.csv"', "read_readings(raw_path)",
              "clean_readings(readings)", "summarise_by_station(clean)",
              "fit_drift_model(clean)", "flag_drifting_stations(drift_model)",
              "render_report(station_summary, drift_flags)"),
  stringsAsFactors = FALSE
)

ui <- page_sidebar(
  title = "tardoc (shinylive probe)",
  sidebar = sidebar(selectInput("target", "Target", targets$name)),
  card(card_header("Target"), verbatimTextOutput("detail")),
  card(card_header("All targets"), tableOutput("tbl"))
)

server <- function(input, output) {
  output$detail <- renderPrint({
    row <- targets[targets$name == input$target, ]
    cat("name:   ", row$name, "\ncommand:", row$command, "\nstatus: ", row$status, "\n")
  })
  output$tbl <- renderTable(targets)
}

shinyApp(ui, server)
