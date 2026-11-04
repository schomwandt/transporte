-- Resuelve route_id real (gtfs_static.routes) a partir de lo que entrega el feed RT.
-- Orden: 1) crosswalk manual (override explícito) 2) route_short_name (más confiable:
-- el route_id_raw del feed es un ID interno propio de la API, no el GTFS estático)
-- p_trip_id_raw se mantiene en la firma por compatibilidad, pero ya no se usa:
-- el "tip_id" del feed no tiene formato GTFS estándar y no matcheaba trips.trip_id.
CREATE OR REPLACE FUNCTION app_config.fn_resolver_route_id(
  p_route_short_name TEXT,
  p_route_id_raw      TEXT,
  p_trip_id_raw        TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_route_id TEXT;
BEGIN
  -- 1) crosswalk manual, keyed por el route_id_raw interno del feed
  IF p_route_id_raw IS NOT NULL THEN
    SELECT route_id INTO v_route_id
    FROM app_config.route_id_crosswalk
    WHERE route_id_raw = p_route_id_raw;

    IF v_route_id IS NOT NULL THEN
      RETURN v_route_id;
    END IF;
  END IF;

  -- 2) match directo por route_short_name (ej "57J")
  IF p_route_short_name IS NOT NULL THEN
    SELECT route_id INTO v_route_id
    FROM gtfs_static.routes
    WHERE route_short_name = p_route_short_name
    LIMIT 1;

    IF v_route_id IS NOT NULL THEN
      RETURN v_route_id;
    END IF;
  END IF;

  RETURN v_route_id;  -- NULL si no resolvió nada: revisar/agregar al crosswalk
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'fn_resolver_route_id error: % | route_short_name=% route_id_raw=%',
      SQLERRM, p_route_short_name, p_route_id_raw;
    RETURN NULL;
END;
$$;

-- Inserción de una posición RT ya resuelta (llamar desde el poller)
CREATE OR REPLACE FUNCTION gtfs_rt.fn_insertar_posicion(
  p_vehicle_id          TEXT,
  p_trip_id_raw          TEXT,
  p_route_id_raw         TEXT,
  p_route_short_name_raw TEXT,
  p_agency_id_raw        INTEGER,
  p_lat                  DOUBLE PRECISION,
  p_lon                  DOUBLE PRECISION,
  p_direction            SMALLINT,
  p_speed                DOUBLE PRECISION,
  p_timestamp_feed       TIMESTAMP
)
RETURNS TABLE(ok BOOLEAN, mensaje TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_route_id TEXT;
BEGIN
  IF p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    RETURN QUERY SELECT FALSE, 'Coordenadas fuera de rango.';
    RETURN;
  END IF;

  v_route_id := app_config.fn_resolver_route_id(p_route_short_name_raw, p_route_id_raw, p_trip_id_raw);

  INSERT INTO gtfs_rt.vehicle_positions
    (vehicle_id, trip_id_raw, route_id_raw, route_short_name_raw, agency_id_raw,
     route_id, lat, lon, geom, direction, speed, timestamp_feed)
  VALUES
    (p_vehicle_id, p_trip_id_raw, p_route_id_raw, p_route_short_name_raw, p_agency_id_raw,
     v_route_id, p_lat, p_lon, ST_SetSRID(ST_Point(p_lon, p_lat), 4326),
     p_direction, p_speed, p_timestamp_feed);

  IF v_route_id IS NULL THEN
    RETURN QUERY SELECT TRUE,
      'Insertado sin resolver route_id — agregar a app_config.route_id_crosswalk.';
  ELSE
    RETURN QUERY SELECT TRUE, 'Posición insertada correctamente.';
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'fn_insertar_posicion error: %', SQLERRM;
    RETURN QUERY SELECT FALSE, 'Error interno al insertar posición.';
END;
$$;

-- Vista: recorrido completo de cada línea con su nombre visible
CREATE OR REPLACE VIEW gtfs_static.vw_lineas_recorrido AS
SELECT DISTINCT ON (r.route_id)
  r.route_id,
  r.route_short_name,
  r.route_long_name,
  r.agency_id,
  sl.geom
FROM gtfs_static.routes r
JOIN gtfs_static.route_shapes rs ON rs.route_id = r.route_id
JOIN gtfs_static.shape_lines sl  ON sl.shape_id = rs.shape_id
WHERE r.activo = TRUE;

-- Vista: últimas posiciones conocidas por vehículo (para el mapa en vivo)
CREATE OR REPLACE VIEW gtfs_rt.vw_ultimas_posiciones AS
SELECT DISTINCT ON (vehicle_id)
  vehicle_id, route_id, route_short_name_raw, lat, lon, geom, direction, speed, timestamp_feed
FROM gtfs_rt.vehicle_positions
WHERE ingested_at > NOW() - INTERVAL '10 minutes'
ORDER BY vehicle_id, timestamp_feed DESC;
