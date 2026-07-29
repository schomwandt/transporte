library(shiny)
library(bslib)
library(leaflet)
library(DT)
library(sf)
library(dplyr)
library(DBI)
library(RPostgres)
library(pool)
library(dotenv)

source("R/config/config.R")
source("R/utils/utils_log.R")

pool <- tryCatch({
  dbPool(
    drv = RPostgres::Postgres(),
    host = Sys.getenv("DB_HOST"), port = as.integer(Sys.getenv("DB_PORT")),
    dbname = Sys.getenv("DB_NAME"), user = Sys.getenv("DB_USER"),
    password = Sys.getenv("DB_PASS"),
    minSize = 2, maxSize = 10, idleTimeout = 600000
  )
}, error = function(e) stop(paste("Error al conectar con la base de datos:", sanitize_error(e$message))))
onStop(function() poolClose(pool))

source_dir <- function(path) {
  invisible(lapply(list.files(path, pattern = "\\.R$", full.names = TRUE, recursive = TRUE), source))
}
source_dir("R/queries")
source_dir("R/modules")
