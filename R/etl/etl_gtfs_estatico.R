# Carga GTFS estático de colectivos a PostGIS.
# Fuente: descarga directa del zip GTFS desde data.buenosaires.gob.ar/dataset/colectivos-gtfs
# (independiente de la API, que está suspendida al momento de escribir esto).
#
# Uso: Rscript R/etl/etl_gtfs_estatico.R /ruta/al/gtfs.zip

library(DBI)
library(RPostgres)
library(dplyr)
library(dotenv)

args <- commandArgs(trailingOnly = TRUE)
zip_path <- if (length(args) >= 1) args[1] else stop("Falta ruta al zip GTFS")

dotenv::load_dot_env(".env")
con <- dbConnect(RPostgres::Postgres(),
  host = Sys.getenv("DB_HOST"), port = as.integer(Sys.getenv("DB_PORT")),
  dbname = Sys.getenv("DB_NAME"), user = Sys.getenv("DB_USER"),
  password = Sys.getenv("DB_PASS"))
on.exit(dbDisconnect(con))

tmp_dir <- tempfile("gtfs_")
unzip(zip_path, exdir = tmp_dir)

leer_gtfs <- function(nombre) {
  path <- file.path(tmp_dir, nombre)
  if (!file.exists(path)) stop(paste("No se encontró", nombre, "en el zip"))
  readr::read_csv(path, show_col_types = FALSE)
}

# --- agency ---
agency <- leer_gtfs("agency.txt") %>%
  transmute(agency_id, agency_name, agency_url, agency_timezone)
dbWriteTable(con, DBI::Id(schema = "gtfs_static", table = "agency"),
             agency, append = TRUE, row.names = FALSE)

# --- routes ---
routes <- leer_gtfs("routes.txt") %>%
  transmute(route_id, agency_id, route_short_name, route_long_name,
            route_type = as.integer(route_type))
dbWriteTable(con, DBI::Id(schema = "gtfs_static", table = "routes"),
             routes, append = TRUE, row.names = FALSE)

# --- route_shapes (solo la relación ruta -> shape; trips completo no se guarda) ---
route_shapes <- leer_gtfs("trips.txt") %>%
  filter(!is.na(shape_id)) %>%
  distinct(route_id, direction_id = as.integer(direction_id), shape_id)
dbWriteTable(con, DBI::Id(schema = "gtfs_static", table = "route_shapes"),
             route_shapes, append = TRUE, row.names = FALSE)

# --- shapes: los puntos van a una tabla temporal y se guardan solo como LineString ---
shapes <- leer_gtfs("shapes.txt")
dbExecute(con, "CREATE TEMP TABLE _shapes_raw (
  shape_id TEXT, shape_pt_lat DOUBLE PRECISION,
  shape_pt_lon DOUBLE PRECISION, shape_pt_sequence INTEGER)")
dbWriteTable(con, "_shapes_raw", shapes %>%
  select(shape_id, shape_pt_lat, shape_pt_lon, shape_pt_sequence),
  append = TRUE, row.names = FALSE)
dbExecute(con, "TRUNCATE gtfs_static.shape_lines")
n <- dbExecute(con, "
  INSERT INTO gtfs_static.shape_lines (shape_id, geom)
  SELECT shape_id,
         ST_MakeLine(ST_SetSRID(ST_Point(shape_pt_lon, shape_pt_lat), 4326)
                     ORDER BY shape_pt_sequence)
  FROM _shapes_raw
  GROUP BY shape_id")
message(sprintf("shape_lines cargadas: %s", n))

# --- stops ---
stops <- leer_gtfs("stops.txt")
dbExecute(con, "CREATE TEMP TABLE _stops_raw (
  stop_id TEXT, stop_name TEXT, stop_lat DOUBLE PRECISION, stop_lon DOUBLE PRECISION)")
dbWriteTable(con, "_stops_raw", stops %>%
  select(stop_id, stop_name, stop_lat, stop_lon), append = TRUE, row.names = FALSE)
dbExecute(con, "
  INSERT INTO gtfs_static.stops (stop_id, stop_name, geom)
  SELECT stop_id, stop_name, ST_SetSRID(ST_Point(stop_lon, stop_lat), 4326)
  FROM _stops_raw
  ON CONFLICT (stop_id) DO NOTHING")

unlink(tmp_dir, recursive = TRUE)
message("Carga GTFS estático completa.")
