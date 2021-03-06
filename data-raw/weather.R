# From https://mesonet.agron.iastate.edu/request/download.phtml?network=NY_ASOS

library(httr)
library(dplyr)
library(lubridate)
library(readr)
library(RCurl)

# Download ---------------------------------------------------------------------

last_year <- as.numeric(substr(Sys.time(), 1, 4)) - 1

get_asos <- function(station) {
  url <- "http://mesonet.agron.iastate.edu/cgi-bin/request/asos.py?"
  query <- list(
    station = station, data = "all",
    year1 = as.character(last_year), month1 = "1", day1 = "1",
    year2 = as.character(last_year), month2 = "12", day2 = "31", tz = "GMT",
    format = "comma", latlon = "no", direct = "yes")
  
  dir.create("data-raw/weather", showWarnings = FALSE, recursive = TRUE)
  r <- GET(url, query = query, write_disk(paste0("./data-raw/weather/", station, ".csv")))
  stop_for_status(r, "Can't access `weather` link in 'data-raw.weather.R' for requested location and date range. \n Check data availability at `https://mesonet.agron.iastate.edu/request/download.phtml?network=NY_ASOS`")
}

stations <- c("JFK", "LGA", "EWR")
paths <- paste0(stations, ".csv")
missing <- stations[!(paths %in% dir("data-raw/weather/"))]
lapply(missing, get_asos)

# Load ------------------------------------------------------------------------

paths <- dir("data-raw/weather", full.names = TRUE)
col_types <- cols(
  .default = col_double(),
  station = col_character(),
  valid = col_datetime(format = ""),
  skyc1 = col_character(),
  skyc2 = col_character(),
  skyc3 = col_character(),
  skyc4 = col_character(),
  wxcodes = col_character(),
  metar = col_character()
)
all <- lapply(paths, read_csv, comment = "#", na = "M",
              col_names = TRUE, col_types = col_types)
raw <- bind_rows(all)
names(raw) <- c("station", "valid", "tmpf", "dwpf", "relh", "drct", "sknt",
                "p01i", "alti", "mslp", "vsby", "gust",
                "skyc1", "skyc2", "skyc3", "skyc4",
                "skyl1", "skyl2", "skyl3", "skyl4", "wxcodes", "metar")

weather <-
  raw %>%
  rename_(time = ~valid) %>%
  select_(
    ~station, ~time, temp = ~tmpf, dewp = ~dwpf, humid = ~relh,
    wind_dir = ~drct, wind_speed = ~sknt, wind_gust = ~gust,
    precip = ~p01i, pressure = ~mslp, visib = ~vsby
  ) %>%
  mutate_(
    time = ~as.POSIXct(strptime(time, "%Y-%m-%d %H:%M")),
    wind_speed = ~as.numeric(wind_speed) * 1.15078, # convert to mpg
    wind_gust = ~as.numeric(wind_speed) * 1.15078,
    year = last_year,
    month = ~lubridate::month(time),
    day = ~lubridate::mday(time),
    hour = ~lubridate::hour(time)) %>%
  group_by_(~station, ~month, ~day, ~hour) %>%
  filter_(~ row_number() == 1) %>%
  select_(~station, ~year:hour, ~temp:visib) %>%
  ungroup() %>%
  filter_(~!is.na(month)) %>%
  mutate_(
    time_hour = ~ISOdatetime(year, month, day, hour, 0, 0))
    
write_csv(weather, "data-raw/weather.csv")
save(weather, file = "data/weather.rda")
