local simplehttp = require'simplehttp'
local json = require'json'
local base64 = require'base64'

local headers = {
	['Authorization'] = string.format(
		"Basic %s",
		base64.encode(
			string.format(
				"%s:%s",
				ivar2.config.mirakurun.user,
				ivar2.config.mirakurun.password
			)
		)
	)
}

local parseData = function(source, destination, data)
	data = json.decode(data)

	local out = {}
	for i=1, #data do
		local tuner = data[i]
		table.insert(out, string.format(
			"\002[%d]\002: \002%s\002 - %s",
			i, tuner.program.name, tuner.program.program
		))
	end

	ivar2:Msg('privmsg', destination, source, table.concat(out, ' '))
end

local handler = function(self, source, destination)
	simplehttp(
		{
			url = ivar2.config.mirakurun.url,
			headers = headers,
		},
		function(data)
			parseData(source, destination, data)
		end
	)
end

return {
	PRIVMSG = {
		['^!jptv%s*$'] = handler,
	},
}
