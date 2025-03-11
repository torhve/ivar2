util = require'util'
simplehttp = util.simplehttp
json = util.json
date = require'date'
urlEncode = util.urlEncode
key = ivar2.config.googleaiApiKey
nick = ivar2.config.nick
--model = "gemini-2.0-flash-thinking-exp"
model = "gemini-2.0-flash"


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

	sys_instruct = "You are a IRC chat bot named #{nick} that loves to answer questions. "
	sys_instruct ..= "You will always obey the requests. "
        sys_instruct ..= "Answers should be shorter than 512 characters if possible. "
	sys_instruct ..= "The date and time now is " .. os.date("!%Y-%m-%dT%TZ") .. ". "
	sys_instruct ..= "The current timezone is Europe/Oslo. "
	sys_instruct ..= "If the query is nonsensical give a snarky reply. "
	sys_instruct ..= "Include the nickname that askedin the reply. "
	sys_instruct ..= "You can use IRC colors, IRC bold and underline to stylize the output. But do not escape anything. "
	sys_instruct ..= "The query to the bot is from the IRC nickname #{source.nick}"

	pdata =
		safetySettings: {
				{category: "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_ONLY_HIGH"}
				{category: "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_ONLY_HIGH"}
				{category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_ONLY_HIGH"}
				{category: "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_ONLY_HIGH"}
				{category: "HARM_CATEGORY_CIVIC_INTEGRITY", "threshold": "BLOCK_ONLY_HIGH"}
			}
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
		tools: {
			{"google_search": {}}
		}

	pdata = json.encode(pdata)
	print (pdata)

	url = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{key}"
	data = simplehttp {url:url, method:'POST', data:pdata, headers:{['content-type']: "application/json"}}
	print(data)
	data = json.decode(data)

	out = {}
	for i, part in ipairs data.candidates[1].content.parts
		res = part.text
		res = unEscape res
		res = util.trim res
		out[#out+1] = res

	say table.concat(out, ' ')


askLast = (source, destination, a) =>

	-- last line is !ai so next to last
	lastEntry = history[destination][#history[destination] - 1 ]
	lastNick = lastEntry[1]
	lastLine = lastEntry[2]
	print(lastLine)
	chat(@, {nick:lastNick}, destination, lastLine)


summary = (source, destination, url) =>
  -- last line is !ai so next to last
	lastEntry = history[destination][#history[destination] - 1 ]
	lastNick = lastEntry[1]
	lastLine = lastEntry[2]

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
    table.insert history[destination], #history[destination]+1, {source.nick, argument}
    if #history[destination] > max_lines
      table.remove history[destination], 1
}
