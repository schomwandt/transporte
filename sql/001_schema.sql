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

CREATE TABLE IF NOT EXISTS gtfs_static.trips (
  trip_id       TEXT PRIMARY KEY,
  route_id      TEXT NOT NULL REFERENCES gtfs_static.routes(route_id),
  service_id    TEXT,
  trip_headsign TEXT,
  direction_id  SMALLINT,
  shape_id      TEXT
);
CREATE INDEX IF NOT EXISTS idx_trips_route_id ON gtfs_static.trips(route_id);

CREATE TABLE IF NOT EXISTS gtfs_static.shapes (
  shape_id            TEXT NOT NULL,
  shape_pt_sequence   INTEGER NOT NULL,
  geom                GEOMETRY(Point, 4326) NOT NULL,
  PRIMARY KEY (shape_id, shape_pt_sequence)
);
CREATE INDEX IF NOT EXISTS idx_shapes_geom ON gtfs_static.shapes USING GIST(geom);

-- Recorrido de cada línea como LineString, derivado de shapes (ver 002_funciones.sql)
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
  id              BIGSERIAL PRIMARY KEY,
  vehicle_id      TEXT,
  trip_id         TEXT,             -- viene del feed RT, puede no matchear directo con trips.trip_id
  route_id_raw    TEXT,             -- route_id tal cual lo entrega el feed RT (puede diferir del estático)
  route_id        TEXT,             -- resuelto vía fn_resolver_route_id() antes de insertar
  lat             DOUBLE PRECISION,
  lon             DOUBLE PRECISION,
  geom            GEOMETRY(Point, 4326),
  bearing         DOUBLE PRECISION,
  speed           DOUBLE PRECISION,
  timestamp_feed  TIMESTAMP,
  ingested_at     TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_vp_geom ON gtfs_rt.vehicle_positions USING GIST(geom);
CREATE INDEX IF NOT EXISTS idx_vp_route_id ON gtfs_rt.vehicle_positions(route_id);
CREATE INDEX IF NOT EXISTS idx_vp_ingested_at ON gtfs_rt.vehicle_positions(ingested_at);

-- Tabla de crosswalk manual para casos donde route_id_raw no resuelve por trip_id
-- ni por route_short_name (mismatches conocidos entre estático y RT)
CREATE TABLE IF NOT EXISTS app_config.route_id_crosswalk (
  route_id_raw TEXT PRIMARY KEY,   -- valor tal cual llega del feed RT
  route_id     TEXT NOT NULL REFERENCES gtfs_static.routes(route_id),
  notas        TEXT,
  created_at   TIMESTAMP DEFAULT NOW()
);
