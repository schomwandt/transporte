source("global.R")
source("R/ui/ui_main.R")
source("R/server/server_main.R")
shinyApp(ui = ui, server = server)
