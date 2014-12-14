local util = require'util'
local simplehttp = util.simplehttp
local json = util.json
local trim = util.trim
local urlEncode = util.urlEncode

local parseJSON = function(data)
	data = json.decode(data)

	if(#data.list > 0) then
		return data.list[1].definition:gsub('\r\n', ' ')
	end
end

local APIBase = 'http://api.urbandictionary.com/v0/define?term=%s'
local handler = function(self, source, destination, input)
	input = trim(input)
	simplehttp(
		APIBase:format(urlEncode(input)),

		function(data)
			local result = parseJSON(data)

			if(result) then
				say(string.format('%s: %s', source.nick, result))
			else
				say(string.format("%s: %s is bad and you should feel bad.", source.nick, input))
			end
		end
	)
end

return {
	PRIVMSG = {
		['^%pud (.+)$'] = handler,
		['^%purb (.+)$'] = handler,
	},
}
