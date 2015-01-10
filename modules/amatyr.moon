{:simplehttp, :json} = require'util'


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

handleWeather = (source, destination, url) =>
    simplehttp url, (data) ->
      result = json.decode data
      if result
        result = result[1]
        temp = result.outtemp
        ws = result.windspeed / 3.6 -- correct unit
        rain = result.dayrain
        windtext = windSpeedToName(ws)
        wgs = windSpeedToName(result.windgust/3.6)
        if wgs ~= windtext
          wgs = ", #{wgs} i kasta"
        else
          wgs = ''

        time = result.datetime\sub(12, 16)

        msg = string.format '\002%.1f\002 °C, \002%.1f\002 m/s (%s%s), \002%.1f\002 mm nedbør (%s)', temp, ws, windtext, wgs, rain, time
        @Privmsg destination, msg

PRIVMSG:
  '^%pnaustvêr$': (source, destination) =>
    url = 'http://yr.hveem.no/api/now'
    handleWeather(@, source, destination, url)
  '^%pvêr$': (source, destination, input) =>
    url = 'http://yr.teigen.be/api/now'
    handleWeather(@, source, destination, url)
