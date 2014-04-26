local simplehttp = require'simplehttp'
local json = require'json'

local trim = function(s)
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local urlEncode = function(str)
	return str:gsub(
		'([^%w ])',
		function (c)
			return string.format ("%%%02X", string.byte(c))
		end
	):gsub(' ', '+')
end

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
				local msgLimit = (512 - 16 - 65 - 10) - #self.config.nick - #destination
				if(#result > msgLimit) then
					result = result:sub(1, msgLimit - 3) .. '...'
				end
				self:Msg('privmsg', destination, source, string.format('%s: %s', source.nick, result))
			else
				self:Msg('privmsg', destination, source, string.format("%s: %s is bad and you should feel bad.", source.nick, input))
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
