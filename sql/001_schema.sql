-- Esquema para GTFS estático de colectivos CABA/AMBA + staging para GTFS-RT
-- Requiere extensión PostGIS habilitada en la DB

CREATE SCHEMA IF NOT EXISTS gtfs_static;
CREATE SCHEMA IF NOT EXISTS gtfs_rt;
CREATE SCHEMA IF NOT EXISTS app_config;

-- === GTFS estático (según spec oficial GTFS) ===

CREATE TABLE IF NOT EXISTS gtfs_static.agency (
  agency_id    TEXT PRIMARY KEY,
  agency_name  TEXT NOT NULL,
  agency_url   TEXT,
  agency_timezone TEXT
);

CREATE TABLE IF NOT EXISTS gtfs_static.routes (
  route_id         TEXT PRIMARY KEY,
  agency_id        TEXT REFERENCES gtfs_static.agency(agency_id),
  route_short_name TEXT,       -- ej: "60" (el número de línea que ve la gente)
  route_long_name  TEXT,
  route_type       SMALLINT,
  activo           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMP DEFAULT NOW(),
  updated_at       TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_routes_short_name ON gtfs_static.routes(route_short_name);

-- Relación ruta -> sentido -> recorrido, derivada de trips.txt.
-- Reemplaza a la tabla trips completa (cientos de miles de filas) porque la app
-- solo necesita saber qué shape corresponde a cada ruta.
CREATE TABLE IF NOT EXISTS gtfs_static.route_shapes (
  route_id     TEXT NOT NULL REFERENCES gtfs_static.routes(route_id),
  direction_id SMALLINT,
  shape_id     TEXT NOT NULL,
  PRIMARY KEY (route_id, shape_id)
);

-- Recorrido de cada línea como LineString, armado en la carga desde shapes.txt
-- (los puntos no se guardan; ver R/etl/etl_gtfs_estatico.R)
CREATE TABLE IF NOT EXISTS gtfs_static.shape_lines (
  shape_id TEXT PRIMARY KEY,
  geom     GEOMETRY(LineString, 4326) NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_shape_lines_geom ON gtfs_static.shape_lines USING GIST(geom);

CREATE TABLE IF NOT EXISTS gtfs_static.stops (
  stop_id   TEXT PRIMARY KEY,
  stop_name TEXT,
  geom      GEOMETRY(Point, 4326) NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_stops_geom ON gtfs_static.stops USING GIST(geom);

-- === Staging para GTFS-RT (vehicle positions) — se activa cuando la API se reanude ===
-- Nota: la API está suspendida (revisión/corrección) al momento de este diseño.
-- Esta tabla queda lista para recibir el feed apenas se reanude el servicio.

CREATE TABLE IF NOT EXISTS gtfs_rt.vehicle_positions (
  id                  BIGSERIAL PRIMARY KEY,
  vehicle_id          TEXT,
  trip_id_raw         TEXT,             -- "tip_id" del feed, no matchea trips.trip_id directo
  route_id_raw        TEXT,             -- route_id interno del feed RT (NO es gtfs_static.route_id)
  route_short_name_raw TEXT,            -- ej "57J" — fuente más confiable para vincular
  agency_id_raw       INTEGER,
  route_id            TEXT,             -- resuelto vía fn_resolver_route_id() antes de insertar
  lat                 DOUBLE PRECISION,
  lon                 DOUBLE PRECISION,
  geom                GEOMETRY(Point, 4326),
  direction           SMALLINT,         -- 0/1, no es bearing en grados
  speed               DOUBLE PRECISION,
  timestamp_feed      TIMESTAMP,
  ingested_at         TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_vp_geom ON gtfs_rt.vehicle_positions USING GIST(geom);
CREATE INDEX IF NOT EXISTS idx_vp_route_id ON gtfs_rt.vehicle_positions(route_id);
CREATE INDEX IF NOT EXISTS idx_vp_ingested_at ON gtfs_rt.vehicle_positions(ingested_at);

-- Tabla de crosswalk manual — override explícito cuando route_short_name
-- no alcanza (ambigüedad entre agencias, línea renombrada, etc.)
CREATE TABLE IF NOT EXISTS app_config.route_id_crosswalk (
  route_id_raw TEXT PRIMARY KEY,   -- valor tal cual llega del feed RT
  route_id     TEXT NOT NULL REFERENCES gtfs_static.routes(route_id),
  notas        TEXT,
  created_at   TIMESTAMP DEFAULT NOW()
);
