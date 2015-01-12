-- Weather Underground API module, requires a key set in configuration
-- WeatherUndergroundKey

util = require'util'
os = require'os'

key = ivar2.config.WeatherUndergroundKey
unless key
  return {}

geoApiBase = 'http://api.geonames.org/searchJSON?name=%s&featureClass=P&username=haste'
wugeolookupurl = 'http://api.wunderground.com/api/%s/geolookup/q/59.788,5.7218.json'
language = 'NO'

tempColor = (v) ->
  v = tonumber(v)
  if v > 0
    color = util.red
    return color(v)
  else
    color = util.lightblue
    return color(v)

windSpeedToName = (ws) ->
  windtext = ''
  unless ws
    return windtext
  if ws > 32
    windtext = 'orkan!'
  elseif ws > 28.5
    windtext = 'sterk storm'
  elseif ws > 24.5
    windtext = 'full storm'
  elseif ws > 20.8
    windtext = 'liten storm'
  elseif ws > 17.2
    windtext = 'sterk kuling'
  elseif ws > 13.9
    windtext = 'stiv kuling'
  elseif ws > 10.8
    windtext = 'liten kuling'
  elseif ws > 8
    windtext = 'frisk bris'
  elseif ws > 5.5
    windtext = 'laber bris'
  elseif ws > 3.4
    windtext = 'lett bris'
  elseif ws > 1.5
    windtext = 'svak vind'
  elseif ws > 0.3
    windtext = 'flau vind'
  else
    windtext = 'vindstille'
  return windtext

findLocation = (source, destination, name, cb) =>
  gurl = geoApiBase\format(util.urlEncode(name))
  util.simplehttp gurl, (data) ->
    json = util.json.decode(data)
    if json.totalResultsCount == 0
      return @Msg('privmsg', destination, source, "Does that place even exist?")
    city = json.geonames[1]
    lat = city.lat
    lon = city.lng
    cb(lon, lat)

lookupConditions = (source, destination, input, pws) =>
  findLocation @, source, destination, input, (lon, lat) ->
    pws = pws or false
    if pws
      pws = 'pws:1/'
    else
      pws = 'pws:0/'
    url = "http://api.wunderground.com/api/#{key}/lang:#{language}/#{pws}conditions/q/#{lat},#{lon}.json"
    @Log 'debug', "Fetching WU URL: %s", url
    util.simplehttp url, (data) ->
      json = util.json.decode(data)
      if json.error ~= nil and json.error.description ~=nil
        return say json.error.description
      current = json.current_observation

      location = current.observation_location
      city = location.city

      weather = current.weather
      temp = current.temp_c
      feelsLike = current.feelslike_c

      windSpeedname = windSpeedToName(current.wind_kph/3.6)

      windDirection = current.wind_dir

      rain = current.precip_today_metric

      time = os.date('%H:%M', tonumber(current.observation_epoch))

      @Msg 'privmsg', destination, source, '%s, %s °C (følt %s °C), %s %s, %s mm, (%s, %s)', weather, tempColor(temp), tempColor(feelsLike), windDirection, windSpeedname, rain, city, time

lookupConditionsPWS = (source, destination, input) =>
  lookupConditions(@, source, destination, input, true)

PRIVMSG:
  '^%pwu (.+)$': lookupConditions
  '^%ppws (.+)$': lookupConditionsPWS
