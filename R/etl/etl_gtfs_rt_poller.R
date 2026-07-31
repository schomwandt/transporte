# Poll periódico de posiciones de colectivos vía API Transporte (vehiclePositionsSimple)
# y carga a PostGIS resolviendo route_id vía route_short_name (fn_insertar_posicion).
#
# Uso: Rscript R/etl/etl_gtfs_rt_poller.R
# Para actualización continua, programar en Windows Task Scheduler (ver README),
# no dejarlo corriendo en loop infinito dentro de una sesión de R.

library(httr)
library(jsonlite)
library(DBI)
library(RPostgres)
library(dotenv)

source("R/utils/utils_log.R")
if (file.exists(".env")) dotenv::load_dot_env(".env")

client_id     <- Sys.getenv("API_TRANSPORTE_CLIENT_ID")
client_secret <- Sys.getenv("API_TRANSPORTE_CLIENT_SECRET")
if (client_id == "" || client_secret == "") stop("Faltan credenciales API_TRANSPORTE_* en .env")

con <- dbConnect(RPostgres::Postgres(),
  host = Sys.getenv("DB_HOST"), port = as.integer(Sys.getenv("DB_PORT")),
  dbname = Sys.getenv("DB_NAME"), user = Sys.getenv("DB_USER"),
  password = Sys.getenv("DB_PASS"),
  connect_timeout = 10)
message("Conexión a DB: OK")
on.exit(dbDisconnect(con))

fetch_posiciones <- function() {
  message("Llamando a la API...")
  url <- paste0("https://apitransporte.buenosaires.gob.ar/colectivos/vehiclePositionsSimple",
                "?client_id=", client_id, "&client_secret=", client_secret)
  resp <- GET(url, timeout(35))
  message("Respuesta de la API recibida.")
  if (status_code(resp) != 200) {
    stop(sprintf("API respondió %s", status_code(resp)))
  }
  fromJSON(content(resp, as = "text", encoding = "UTF-8"))
}

insertar_posiciones <- function(df) {
  if (is.null(df) || nrow(df) == 0) { message("Sin posiciones en esta corrida."); return(invisible()) }
  message(sprintf("Insertando %d posiciones (en bloque)...", nrow(df)))

  raw <- data.frame(
    vehicle_id           = as.character(df$id),
    trip_id_raw           = as.character(df$tip_id),
    route_id_raw           = as.character(df$route_id),
    route_short_name_raw   = as.character(df$route_short_name),
    agency_id_raw           = as.integer(df$agency_id),
    lat                     = as.numeric(df$latitude),
    lon                     = as.numeric(df$longitude),
    direction               = as.integer(df$direction),
    speed                   = as.numeric(df$speed),
    timestamp_feed          = as.POSIXct(as.numeric(df$timestamp), origin = "1970-01-01", tz = "UTC")
  )

  dbExecute(con, "DROP TABLE IF EXISTS _vp_raw")
  dbWriteTable(con, "_vp_raw", raw, temporary = TRUE, row.names = FALSE)

  # Resolución vectorizada, mismo orden de prioridad que fn_resolver_route_id:
  # crosswalk manual -> route_short_name -> trip_id
  res <- dbGetQuery(con, "
    WITH resueltas AS (
      SELECT v.*,
        COALESCE(cw.route_id, r_short.route_id, r_base.route_id, r_trip.route_id,
                 'RT-' || v.route_short_name_raw) AS route_id
      FROM _vp_raw v
      LEFT JOIN app_config.route_id_crosswalk cw ON cw.route_id_raw = v.route_id_raw
      LEFT JOIN gtfs_static.routes r_short ON r_short.route_short_name = v.route_short_name_raw
      LEFT JOIN gtfs_static.routes r_base
        ON r_short.route_id IS NULL
       AND r_base.route_short_name = regexp_replace(v.route_short_name_raw, '^([0-9]+).*', '\\1')
      LEFT JOIN gtfs_static.trips t ON t.trip_id = v.trip_id_raw
      LEFT JOIN gtfs_static.routes r_trip ON r_trip.route_id = t.route_id
      WHERE v.lat BETWEEN -90 AND 90 AND v.lon BETWEEN -180 AND 180
    ),
    ins AS (
      INSERT INTO gtfs_rt.vehicle_positions
        (vehicle_id, trip_id_raw, route_id_raw, route_short_name_raw, agency_id_raw,
         route_id, lat, lon, geom, direction, speed, timestamp_feed)
      SELECT vehicle_id, trip_id_raw, route_id_raw, route_short_name_raw, agency_id_raw,
             route_id, lat, lon, ST_SetSRID(ST_Point(lon, lat), 4326),
             direction, speed, timestamp_feed
      FROM resueltas
      RETURNING route_id
    )
    SELECT count(*) AS total, count(route_id) AS resueltas FROM ins
  ")

  message(sprintf("Insertadas: %d | sin route_id resuelto: %d",
                  as.integer(res$total), as.integer(res$total - res$resueltas)))
}

tryCatch({
  datos <- fetch_posiciones()
  insertar_posiciones(datos)
}, error = function(e) log_error("etl_gtfs_rt_poller", e))
