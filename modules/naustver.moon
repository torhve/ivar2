simplehttp = require'simplehttp'
json = require'json'

APIBase = 'http://yr.hveem.no/api/now'

PRIVMSG:
  '^%pvêr$': (self, source, destination, input) ->
    simplehttp APIBase, (data) ->
      result = json.decode data 
      if result
        result = result[1]
        temp = result.outtemp
        ws = result.windspeed
        rain = result.dayrain
        windtext = ''
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


        self\Msg 'privmsg', destination, source, '\002%.1f\002 °C, \002%.1f\002 m/s (%s), \002%.1f\002 mm nedbør', temp, ws, windtext, rain
