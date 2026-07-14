-- yr.no API consumer, using the new unofficial API
import urlEncode, simplehttp, json, red, lightblue, utf8, split, trim from require'util'

apiBase = 'http://www.yr.no'
-- default
default_lang = 'en'

weatherEmoji = {
  clear_day: '☀️', clear_night: '🌙',
  clearsky_day: '☀️', clearsky_night: '🌙',
  fair_day: '🌤️', fair_night: '🌙',
  partlycloudy_day: '⛅', partlycloudy_night: '⛅',
  cloudy: '☁️', overcast: '🌥️',
  fog: '🌫️',
  rain_shower_day: '🌦️', rain_shower_night: '🌦️',
  snow_shower_day: '🌨️', snow_shower_night: '🌨️',
  sleet_shower_day: '🌨️', sleet_shower_night: '🌨️',
  rain_light_day: '🌧️', rain_light_night: '🌧️',
  rain_moderate_day: '🌧️', rain_moderate_night: '🌧️',
  rain_heavy_day: '🌧️', rain_heavy_night: '🌧️',
  snow_light_day: '❄️', snow_light_night: '❄️',
  snow_moderate_day: '❄️', snow_moderate_night: '❄️',
  snow_heavy_day: '❄️', snow_heavy_night: '❄️',
  rainandshowers_light_day: '🌧️', rainandshowers_light_night: '🌧️',
  rainandshowers_moderate_day: '🌧️', rainandshowers_moderate_night: '🌧️',
  rainandshowers_heavy_day: '🌧️', rainandshowers_heavy_night: '🌧️',
  snowandshowers_light_day: '🌨️', snowandshowers_light_night: '🌨️',
  snowandshowers_moderate_day: '🌨️', snowandshowers_moderate_night: '🌨️',
  snowandshowers_heavy_day: '🌨️', snowandshowers_heavy_night: '🌨️',
  sleet_light_day: '🌨️', sleet_light_night: '🌨️',
  sleet_moderate_day: '🌨️', sleet_moderate_night: '🌨️',
  sleet_heavy_day: '🌨️', sleet_heavy_night: '🌨️',
  rainandsnow_light_day: '🌧️', rainandsnow_light_night: '🌧️',
  rainandsnow_moderate_day: '🌧️', rainandsnow_moderate_night: '🌧️',
  rainandsnow_heavy_day: '🌧️', rainandsnow_heavy_night: '🌧️',
  rainandsnowshower_day: '🌧️', rainandsnowshower_night: '🌧️',
  sleetandsnow_day: '🌨️', sleetandsnow_night: '🌨️',
  sleetandrain_day: '🌧️', sleetandrain_night: '🌧️',
  thunderstorm_day: '⛈️', thunderstorm_night: '⛈️',
  -- yr.no v0 API codes (no _day/_night suffix)
  lightrainshowersandthunder_day: '⛈️',
  rainandthunder: '⛈️',
  heavyrain: '🌧️',
  heavyrainshowers_day: '🌧️',
  lightrain: '🌧️',
  lightrainshowers_day: '🌦️',
  rain: '🌧️',
  rainshowers_day: '🌦️',
  lightsnow: '❄️',
  moderatesnow: '❄️',
  heavysnow: '❄️',
  snow: '❄️',
  snowshowers: '🌨️',
  lightsleet: '🌨️',
  moderatesleet: '🌨️',
  heavysleet: '🌨️',
  sleet: '🌨️',
  rainandsnow: '🌧️'
}

cloudEmoji = {
  '10': '☀️',
  '30': '🌤️',
  '60': '⛅',
  '80': '🌥️',
  '100': '☁️'
}

getWeatherEmoji = (now) ->
  unless now.symbolCode and now.symbolCode.next1Hour
    return '☁️'
  symCode = now.symbolCode.next1Hour
  -- Try exact match first (for codes without _day/_night suffix)
  emoji = weatherEmoji[symCode]
  return emoji if emoji
  suffix = if now.symbol and now.symbol.sunup then '_day' else '_night'
  key = symCode .. suffix
  weatherEmoji[key] or '☁️'

getCloudEmoji = (value) ->
  unless value
    return '☁️'
  for threshold, emoji in pairs cloudEmoji
    return emoji if value <= tonumber(threshold)
  '☁️'

windSpeedToName = (ws, lang) ->
  windtext = ''
  n = (lang\match '^n')
  unless ws
    return windtext
  if ws > 32
    windtext = 'orkan!'
    unless n
      windtext = 'hurricane!'
  elseif ws > 28.5
    windtext = 'sterk storm'
    unless n
      windtext = 'violent storm'
  elseif ws > 24.5
    windtext = 'full storm'
    unless n
      windtext = 'storm'
  elseif ws > 20.8
    windtext = 'liten storm'
    unless n
      windtext = 'severe gale'
  elseif ws > 17.2
    windtext = 'sterk kuling'
    unless n
      windtext = 'gale'
  elseif ws > 13.9
    windtext = 'stiv kuling'
    unless n
      windtext = 'near gale'
  elseif ws > 10.8
    windtext = 'liten kuling'
    unless n
      windtext = 'strong breeze'
  elseif ws > 8
    windtext = 'frisk bris'
    unless n
      windtext = 'fresh breeze'
  elseif ws > 5.5
    windtext = 'laber bris'
    unless n
      windtext = 'moderate breeze'
  elseif ws > 3.4
    windtext = 'lett bris'
    unless n
      windtext = 'gentle breeze'
  elseif ws > 1.5
    windtext = 'svak vind'
    unless n
      windtext = 'light breeze'
  elseif ws > 0.3
    windtext = 'flau vind'
    unless n
      windtext = 'light air'
  else
    windtext = 'vindstille'
    unless n
      windtext = 'calm'
  return windtext

arrow = (dir) ->
  -- Turn the direction of arrow to the way wind is coming from
  utf8arrow = utf8.arrow
  ndir = dir\gsub '.', (n) ->
    if     n == 'N' then n = 'S'
    elseif n == 'E' then n = 'W'
    elseif n == 'S' then n = 'N'
    elseif n == 'W' then n = 'E'
    return n
  utf8arrow(ndir)

color = (value) ->
  if tonumber(value) > 0 then
    return red
  else
    return lightblue

deg2name = (deg) ->
  val = math.floor((deg/22.5)+.5)
  arr = {"N","NNE","NE","ENE","E","ESE", "SE", "SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"}
  return arr[ (val % 16) +1 ]

getLang = (self, source, destination) ->
  lang = ivar2.persist['yr:lang:'..source.nick]
  switch lang
    when 'stad'
      return 'nn'
    when 'sted'
      return 'nb'
    when 'place'
      return 'en'
    -- else pass

  clocale = @DestinationLocale(destination)
  if (clocale\match('^nn'))
    return 'nn'
  elseif(clocale\match('^nb'))
    return 'nb'

  return default_lang

getLocation = (arg, lang) ->
  lang = lang or default_lang
  data = simplehttp apiBase..'/api/v0/locations/suggest?language='..lang..'&q='..urlEncode(arg)
  js = json.decode(data)
  if js.totalResults == 0
    return nil, 'No results'
  locations = js['_embedded']['location']
  _, location = next locations
  return location

getPlace = (self, source, destination, input) ->
  if not input or input == ''
    persist = self.persist['yr:place:'..source.nick]
    unless persist
      patt = @ChannelCommandPattern('^%pset yr <location>', "yr", destination)\sub(1)
      patt = patt\gsub('^%^%%p', '!')
      @Msg('privmsg', destination, source, 'Set your location first. Like this: '..patt)
      return
    input = persist

  return input

handleMultiTemp = (source, destination, arg) =>
  unless arg
    return
  lang = getLang(@, source, destination)
  results = {}
  for city in *split arg, ','
    city = trim(city)
    unless city
      continue
    location = getLocation city, lang
    unless location
      table.insert results, "#{city}: not found"
      continue
    f_link = apiBase .. location._links.forecast.href
    f_data = simplehttp f_link
    forecast = json.decode f_data
    _, now = next forecast.shortIntervals
    temp = now.temperature.value
    table.insert results, "#{location.name}: #{color(temp)(temp)} °C"
  table.concat results, ', '

handleTempLookup = (source, destination, arg) =>
  place = getPlace @, source, destination, arg
  unless place
    return
  if arg and arg\find ','
    return say handleMultiTemp(@, source, destination, arg)
  lang = getLang(@, source, destination)
  location = getLocation place, lang
  unless location
    reply 'yr.no came up "wah?"'
  whereabouts = {location.name}
  category = location.category and location.category.name
  table.insert whereabouts, category if category
  subregion = location.subregion and location.subregion.name
  table.insert whereabouts, subregion if subregion
  region = location.region and location.region.name
  table.insert whereabouts, region if region
  country = location.country.name
  table.insert whereabouts, country

  whereabouts = table.concat whereabouts, ', '

  f_link = apiBase .. location._links.forecast.href
  f_data = simplehttp f_link
  forecast = json.decode f_data

  _, now = next forecast.shortIntervals

  wemoji = getWeatherEmoji now
  temp = now.temperature.value
  feelsLike = ''
  if now.feelsLike and now.feelsLike.value
    the_feels = now.feelsLike.value
    feels_word = 'feels like'
    if lang\match '^n'
      feels_word = 'følt'
    feelsLike = " (#{feels_word} #{color(the_feels)(the_feels)} °C)"

  windDirection = now.wind and now.wind.direction
  windDirectionarrow = if windDirection then arrow deg2name windDirection else ''
  windSpeed = now.wind and now.wind.speed
  windSpeedname = windSpeedToName windSpeed, lang

  humidity = now.humidity and now.humidity.value
  humidityname = '💧'

  cloudCover = now.cloudCover and now.cloudCover.value

  popText = ''
  popValue = if now.precipitation then now.precipitation.pop or now.precipitation.probability else nil
  if popValue and popValue > 0
    pop_word = 'chance of rain'
    if lang\match '^n'
      pop_word = 'sannsyn for nedbør'
    popText = ", #{popValue}% #{pop_word}"

  humidPart = ''
  if humidity
    humidPart = ", #{humidity}% #{humidityname}"
  cloudPart = ''
  if cloudCover
    cloudPart = ", #{getCloudEmoji(cloudCover)} #{cloudCover}%"
  say "#{wemoji} #{color(temp)(temp)} °C#{feelsLike}#{cloudPart}#{popText} #{humidPart}, #{windDirectionarrow} #{windSpeedname} (#{windSpeed} m/s) (#{whereabouts})"

PRIVMSG:
  '^%pbtemp%s*(.*)$': handleTempLookup
  '^%ptemp%s*(.*)$': handleTempLookup
  '^%pdeg (.*)$': (s, d, a) =>
    say deg2name(tonumber(a))