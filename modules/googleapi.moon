-- ported from luabot's google module. Thanks!
html2unicode = require'html'

imagesearch = (source, destination, term, num=1) =>
    data, err = ivar2.util.simplehttp 'http://ajax.googleapis.com/ajax/services/search/images?safe=off&v=1.0&q='..ivar2.util.urlEncode(term), (data) ->
      res = ivar2.util.json.decode(data)
      results = res.responseData.results

      total = #results

      if num >= total or num < 0
          say "Couldn't find anything matching \002#{term}\002."
          return

      url = results[num]['unescapedUrl']
      say "(#{num} of #{total}) #{url}"

PRIVMSG:
  '^%pimage (.+)': imagesearch
  '^%pimage (.+) ([0-9]+)': imagesearch
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
