-- ported from luabot's google module. Thanks!
html2unicode = require'html'

PRIVMSG:
  '^%pg (.+)': (source, destination, query) =>
    data, err = ivar2.util.simplehttp 'http://ajax.googleapis.com/ajax/services/search/web?v=1.0&q='..ivar2.util.urlEncode(query), (data) ->

      if query == 'google'
        return reply "wow. That's really clever."

      unless data
        return reply "no response"

      if data\sub(1, 1) ~= '{' then
        return false, 'invalid reply?'

      resp = ivar2.util.json.decode(data)
      unless resp.responseData
        return reply 'no response data'

      res = resp.responseData.results
      if res[1]
        say(html2unicode(res[1].titleNoFormatting)..': '..res[1].unescapedUrl)
      else
        return reply 'no results'

