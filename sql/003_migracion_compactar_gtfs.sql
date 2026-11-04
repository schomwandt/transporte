-- Migración: compactar GTFS estático (ejecutar UNA vez sobre la base existente).
-- Reemplaza trips (436k filas) por route_shapes y elimina la tabla de puntos de shapes.
-- Requisito previo: gtfs_static.shape_lines completa (verificar el conteo abajo).

BEGIN;

-- 0) Control: si shape_lines está vacía, abortar
DO $$
BEGIN
  IF (SELECT count(*) FROM gtfs_static.shape_lines) = 0 THEN
    RAISE EXCEPTION 'shape_lines está vacía: no continuar';
  END IF;
END $$;

-- 1) Nueva tabla ruta -> recorrido, a partir de trips
CREATE TABLE IF NOT EXISTS gtfs_static.route_shapes (
  route_id     TEXT NOT NULL REFERENCES gtfs_static.routes(route_id),
  direction_id SMALLINT,
  shape_id     TEXT NOT NULL,
  PRIMARY KEY (route_id, shape_id)
);

INSERT INTO gtfs_static.route_shapes (route_id, direction_id, shape_id)
SELECT DISTINCT ON (route_id, shape_id) route_id, direction_id, shape_id
FROM gtfs_static.trips
WHERE shape_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- 2) Vista apuntando a route_shapes (deja de depender de trips)
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

-- 3) Resolver sin el fallback por trip_id (firma sin cambios)
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
  IF p_route_id_raw IS NOT NULL THEN
    SELECT route_id INTO v_route_id
    FROM app_config.route_id_crosswalk
    WHERE route_id_raw = p_route_id_raw;

    IF v_route_id IS NOT NULL THEN
      RETURN v_route_id;
    END IF;
  END IF;

  IF p_route_short_name IS NOT NULL THEN
    SELECT route_id INTO v_route_id
    FROM gtfs_static.routes
    WHERE route_short_name = p_route_short_name
    LIMIT 1;
  END IF;

  RETURN v_route_id;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'fn_resolver_route_id error: % | route_short_name=% route_id_raw=%',
      SQLERRM, p_route_short_name, p_route_id_raw;
    RETURN NULL;
END;
$$;

-- 4) Eliminar lo que ya no se usa
DROP FUNCTION IF EXISTS gtfs_static.fn_build_shape_lines();
DROP TABLE IF EXISTS gtfs_static.trips;
DROP TABLE IF EXISTS gtfs_static.shapes;   -- en la base actual es el duplicado en LineString

COMMIT;

-- Verificación
SELECT (SELECT count(*) FROM gtfs_static.route_shapes)        AS route_shapes,
       (SELECT count(*) FROM gtfs_static.shape_lines)         AS shape_lines,
       (SELECT count(*) FROM gtfs_static.vw_lineas_recorrido) AS lineas_en_vista,
       pg_size_pretty(pg_database_size(current_database()))   AS tamano_base;
