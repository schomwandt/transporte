#' Listado de líneas activas (para selectInput)
qry_get_lineas <- function(pool) {
  tryCatch({
    con <- poolCheckout(pool)
    on.exit(poolReturn(con))
    dbGetQuery(con, "
      SELECT route_id, route_short_name, route_long_name
      FROM   gtfs_static.routes
      WHERE  activo = TRUE
      ORDER  BY route_short_name
    ")
  }, warning = function(w) { log_warning("qry_get_lineas", w); NULL },
     error   = function(e) { log_error("qry_get_lineas", e); NULL })
}

#' Recorrido geográfico (GeoJSON) de una o más líneas, para dibujar en leaflet
qry_get_recorrido <- function(pool, route_ids) {
  tryCatch({
    con <- poolCheckout(pool)
    on.exit(poolReturn(con))
    dbGetQuery(con, "
      SELECT route_id, route_short_name,
             ST_AsGeoJSON(geom)::json AS geometry
      FROM   gtfs_static.vw_lineas_recorrido
      WHERE  route_id = ANY($1)
    ", params = list(route_ids))
  }, warning = function(w) { log_warning("qry_get_recorrido", w); NULL },
     error   = function(e) { log_error("qry_get_recorrido", e); NULL })
}

#' Últimas posiciones conocidas (últimos 10 min) filtradas por línea, para el mapa en vivo
#' Requiere que gtfs_rt.vehicle_positions esté recibiendo datos (API RT activa)
qry_get_posiciones_actuales <- function(pool, route_ids = NULL) {
  tryCatch({
    con <- poolCheckout(pool)
    on.exit(poolReturn(con))

    query  <- "SELECT vehicle_id, route_id, lat, lon, bearing, speed, timestamp_feed
               FROM   gtfs_rt.vw_ultimas_posiciones"
    params <- list()

    if (!is.null(route_ids)) {
      query  <- paste(query, "WHERE route_id = ANY($1)")
      params <- list(route_ids)
    }

    dbGetQuery(con, query, params = params)
  }, warning = function(w) { log_warning("qry_get_posiciones_actuales", w); NULL },
     error   = function(e) { log_error("qry_get_posiciones_actuales", e); NULL })
}

#' Agregar un mapeo manual al crosswalk cuando fn_resolver_route_id no matchea
db_agregar_crosswalk <- function(pool, route_id_raw, route_id, notas = NULL) {
  tryCatch({
    con <- poolCheckout(pool)
    on.exit(poolReturn(con))
    dbExecute(con, "
      INSERT INTO app_config.route_id_crosswalk (route_id_raw, route_id, notas)
      VALUES ($1, $2, $3)
      ON CONFLICT (route_id_raw) DO UPDATE SET route_id = EXCLUDED.route_id
    ", params = list(route_id_raw, route_id, notas))
    list(ok = TRUE)
  }, error = function(e) {
    log_error("db_agregar_crosswalk", e)
    list(ok = FALSE, mensaje = "No se pudo guardar el mapeo.")
  })
}
