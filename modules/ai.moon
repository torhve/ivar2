util = require'util'
simplehttp = util.simplehttp
json = util.json
date = require'date'
urlEncode = util.urlEncode
key = ivar2.config.googleaiApiKey

-- save a few lines for context
history = {}


unEscape = (input) ->

  -- replace javascript escape codes with lua formatted strings
  luaString = input\gsub("\\x(%x%x)", (hex) ->
    byte = tonumber(hex, 16)
    return string.char(byte)
  )
  return luaString

chat = (source, destination, a) =>

  sys_instruct = "You are a IRC bot named lorelai. You repond tersely, and limit responses to one line, under 512 characters. "
  sys_instruct ..= "The date and time now is " .. os.date("!%Y-%m-%dT%TZ") .. ". "
  sys_instruct ..= "The current timezone is Europe/Oslo. "
  sys_instruct ..= "If the query is nonsensical give a snarky reply. "
  sys_instruct ..= "Include the asker nick in the reply. "
  sys_instruct ..= "You can use IRC colors, IRC bold and underline to stylized the output."
  sys_instruct ..= "The query to the bot is by the IRC user #{source.nick}"

  pdata =
		contents:
			{
				parts:
					{
						text: a
					}
			}
		system_instruction: {
			parts:
				{
					text: sys_instruct
				}
			}
  pdata = json.encode(pdata)

  url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=#{key}"
  data = simplehttp {url:url, method:'POST', data:pdata, headers:{['content-type']: "application/json"}}
  print(data)
  data = json.decode(data)
  res = data.candidates[1].content.parts[1].text
  unless res return ''

  res = unEscape res
  res = util.trim res

  out = {}
  out[#out+1] = res
  say table.concat(out, ' ')


askLast = (source, destination, a) =>

  -- last line is !ai so next to last
  lastLine =history[destination][#history[destination] - 1 ]
  print(lastLine)
  chat(@, source, destination, lastLine)


summary = (source, destination, url) =>
  lastLine =history[destination][#history[destination] - 1 ]

  data = simplehttp lastLine

  prompt = "Summarize the following HTML document: \n\n" .. data

  chat(@, source, destination, prompt)


PRIVMSG: {
  '^%pai (.*)$': chat
  '^%pai$': askLast
  '^%psummary$': summary
  (source, destination, argument) =>
    max_lines = 5
    unless history[destination]
      history[destination] = {}
    table.insert history[destination], #history[destination]+1, argument
    if #history[destination] > max_lines
      table.remove history[destination], 1
}
