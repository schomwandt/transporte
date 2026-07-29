mod_mapa_ui <- function(id) {
  ns <- NS(id)
  tagList(
    selectizeInput(ns("lineas"), "Líneas", choices = NULL, multiple = TRUE,
                    options = list(placeholder = "Seleccioná una o más líneas")),
    leafletOutput(ns("mapa"), height = "650px")
  )
}

mod_mapa_server <- function(id, pool) {
  moduleServer(id, function(input, output, session) {

    observe({
      lineas <- qry_get_lineas(pool)
      req(lineas)
      choices <- setNames(lineas$route_id,
                           paste0(lineas$route_short_name, " - ", lineas$route_long_name))
      updateSelectizeInput(session, "lineas", choices = choices, server = TRUE)
    })

    recorridos <- reactive({
      req(input$lineas)
      qry_get_recorrido(pool, input$lineas)
    })

    # Posiciones en vivo — vacío mientras la API GTFS-RT esté suspendida
    posiciones <- reactive({
      req(input$lineas)
      invalidateLater(15000, session)
      qry_get_posiciones_actuales(pool, input$lineas)
    })

    output$mapa <- renderLeaflet({
      leaflet() %>%
        addProviderTiles("CartoDB.Positron") %>%
        setView(lng = -58.44, lat = -34.61, zoom = 12)
    })

    observe({
      req(recorridos())
      proxy <- leafletProxy(session$ns("mapa")) %>% clearGroup("recorridos")
      for (i in seq_len(nrow(recorridos()))) {
        geo <- recorridos()$geometry[[i]]
        coords <- geo$coordinates[[1]]
        lats <- sapply(coords, `[[`, 2); lngs <- sapply(coords, `[[`, 1)
        proxy <- proxy %>% addPolylines(lng = lngs, lat = lats, group = "recorridos",
                                         color = "#2c3e50", weight = 3,
                                         label = recorridos()$route_short_name[i])
      }
    })

    observe({
      leafletProxy(session$ns("mapa")) %>% clearGroup("vehiculos")
      df <- posiciones()
      if (!is.null(df) && nrow(df) > 0) {
        leafletProxy(session$ns("mapa")) %>%
          addCircleMarkers(data = df, lng = ~lon, lat = ~lat, radius = 5,
                            color = "#e74c3c", fillOpacity = 0.9, group = "vehiculos",
                            popup = ~paste("Vehículo:", vehicle_id, "<br>Línea:", route_id))
      }
    })
  })
}
