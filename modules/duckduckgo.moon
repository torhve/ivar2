json = require 'json'
simplehttp = require 'simplehttp'

urlEncode = (str, space) ->
  space = space or '+'

  str = str\gsub '([^%w ])', (c) ->
      string.format  "%%%02X", string.byte(c) 
  return str\gsub(' ', space)

PRIVMSG:
  '^%pddg (.+)$': (source, destination, term) =>
    term = urlEncode term
    simplehttp "http://api.duckduckgo.com/?q=#{term}&format=json", (d) ->
      data = json.decode d
      out = {}
      topic = data.RelatedTopics[1] if data.RelatedTopics and #data.RelatedTopics>0
      if data.Heading == ''
        return
      table.insert out, "\002#{data.Heading}\002:"
      table.insert out, data.AbstractText unless data.AbstractText == ''
      table.insert out, data.Image unless data.Image == ''
      table.insert out, data.AbstractURL unless data.AbstractURL == ''
      table.insert out, data.Definition unless data.Definition == ''
      table.insert out, data.DefinitionText unless data.DefinitionText == ''
      if #out < 3
        table.insert out, topic.FirstURL
        table.insert out, topic.Text

      @Msg 'privmsg', destination, source, table.concat(out, ' ')

