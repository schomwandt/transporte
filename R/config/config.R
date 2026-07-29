env <- Sys.getenv("SHINY_ENV", unset = "local")

env_file <- switch(env,
  "prod" = ".env.prod",
  "dev"  = ".env.dev",
  ".env"
)

if (file.exists(env_file)) {
  dotenv::load_dot_env(env_file)
} else {
  warning(paste("Archivo de entorno no encontrado:", env_file))
}
