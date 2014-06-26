-- ported from luabot's complete module by anders. Thanks!
html2unicode = require'html'


PRIVMSG:
  '^%pcomplete (.+)$': (s, d, query) =>
    URL = "http://www.google.com/complete/search?client=serp&hl=en&xhr=t&q="..ivar2.util.urlEncode(query)
    ivar2.util.simplehttp URL, (response) ->
      d = json.decode(response)
      out = {}

      for k, v in ipairs(d[2]) do
        completion = v[1]\gsub("<.->", "")
        out[#out + 1] = html2unicode(completion).."?"

      if #out > 0
        say(table.concat(out, " "))
