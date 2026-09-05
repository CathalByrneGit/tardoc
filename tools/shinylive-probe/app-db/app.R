library(shiny)
library(bslib)
library(DBI)
library(duckdb)

ui <- page_sidebar(
  title = "tardoc analytics (shinylive probe)",
  sidebar = sidebar(
    textAreaInput("sql", "SQL", "SELECT * FROM targets ORDER BY name", height = "120px"),
    actionButton("go", "Run", class = "btn-primary")
  ),
  card(card_header("Result"), tableOutput("out"))
)

server <- function(input, output) {
  con <- dbConnect(duckdb::duckdb())
  onStop(function() dbDisconnect(con, shutdown = TRUE))
  dbWriteTable(con, "targets", data.frame(
    name = c("raw_path", "readings", "clean", "station_summary"),
    status = "uptodate", n_upstream = c(0L, 1L, 1L, 1L)
  ))
  res <- eventReactive(input$go, dbGetQuery(con, input$sql), ignoreNULL = FALSE)
  output$out <- renderTable(res())
}

shinyApp(ui, server)
