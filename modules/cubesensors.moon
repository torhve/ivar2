round = (x) ->
  x + 0.5 - (x + 0.5) % 1

PRIVMSG:
  '^%pinnev.+r$': (source, destination, input) =>
    ivar2.util.simplehttp ivar2.config.cubeapiurl, (data) ->
      result = json.decode data
      if result
        r = result[1]
        temp = r.rtemp
        noise = tonumber(r.noisedba) or 0
        say '\002%.1f\002 °C, \002%s\002 luftkvalitet, \002%s\002 fukt, \002%s\002 lys, \002%s\002 dBA støynivå', temp, round(r.voc), round(r.humidity), round(r.light), noise
