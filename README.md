# Movilidad de colectivos - CABA/AMBA

App Shiny + PostgreSQL/PostGIS para visualizar recorridos y (cuando esté
disponible) posiciones en tiempo real de colectivos de CABA/AMBA.

## Estado de la fuente de datos

La API Transporte (data.buenosaires.gob.ar) tiene **suspendidos** los
datasets de formato API y GTFS (colectivos, subte, trenes) por revisión y
corrección, según el propio portal (última actualización: 17/06/2026). Por
eso el proyecto arranca por la capa de **GTFS estático** (descarga directa
del zip, no depende de la API) y deja preparada `gtfs_rt.vehicle_positions`
para cuando se reanude el feed en tiempo real.

## Problema de vinculación de líneas — cómo se resuelve acá

`fn_resolver_route_id()` en `sql/002_funciones.sql` resuelve el `route_id`
de una posición RT en este orden:
1. `trip_id` → `gtfs_static.trips.route_id` (la vía más confiable)
2. `app_config.route_id_crosswalk` (mapeos manuales para mismatches conocidos)
3. match directo por `route_id` o `route_short_name`

Si un `route_id_raw` no resuelve, la fila se inserta igual (con `route_id`
NULL) para no perder datos, y queda para agregar al crosswalk manualmente
con `db_agregar_crosswalk()`.

## Setup

```bash
createdb movilidad_amba
psql movilidad_amba -c "CREATE EXTENSION postgis;"
psql movilidad_amba -f sql/001_schema.sql
psql movilidad_amba -f sql/002_funciones.sql

cp .env.example .env   # completar credenciales

# Descargar el zip GTFS desde:
# https://data.buenosaires.gob.ar/dataset/colectivos-gtfs
Rscript R/etl/etl_gtfs_estatico.R /ruta/al/gtfs.zip

R -e "shiny::runApp()"
```

## Estructura

```
app.R                   # entry point
global.R                # librerías, pool, sourcing
R/config/               # detección de entorno (.env)
R/queries/               # todas las queries a PostgreSQL
R/modules/               # módulos Shiny (mapa)
R/ui/, R/server/         # UI y server principal
R/etl/                   # carga de GTFS estático
sql/                      # esquema y funciones PL/pgSQL
```
