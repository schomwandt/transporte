sanitize_error <- function(msg) {
  msg <- gsub("(?i)password=\\S+", "password=[REDACTED]", msg, perl = TRUE)
  msg <- gsub("/(?:home|srv|var|etc|usr)/[^\\s:,]+", "[REDACTED_PATH]", msg, perl = TRUE)
  msg
}

log_error <- function(contexto, error_obj) {
  message(format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          " [ERROR] [", contexto, "] ", sanitize_error(conditionMessage(error_obj)))
}

log_warning <- function(contexto, warning_obj) {
  message(format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          " [WARNING] [", contexto, "] ", sanitize_error(conditionMessage(warning_obj)))
}
