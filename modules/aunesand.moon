html2unicode = require'html'

hex_to_char = (x) ->
  string.char(tonumber(x, 16))

unescape = (url) ->
  url\gsub("%%(%x%x)", hex_to_char)

PRIVMSG:
  '^%paunesand': (source, destination) =>
    rnd = math.random(1,3000)
    ivar2.util.simplehttp 'http://p3.no/uv/aune-sands-poesigenerator/?cachebuster='..rnd, (html) ->
      match = html\match[[<a title="Del diktet på Facebook" href="(.*)"]]
      if match
        poem = match\match[[facebookdescription=(.-)-]]
        poem = poem\gsub '+', ' '
        poem = unescape(poem)
        if poem
          say html2unicode(poem)

