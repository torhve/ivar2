local util = require'util'
local simplehttp = util.simplehttp
local json = util.json

local APIBase = 'https://blockchain.info/no/ticker'
return {
	PRIVMSG = {
		['^%pbtc$'] = function(self, source, destination, input)
			simplehttp(APIBase, function(data)
					local result = json.decode(data)

					if(result) then
						self:Msg('privmsg', destination, source, '\0021\002 BTC is worth \002%s\002 € (~15m)', result["EUR"]["15m"])
					end
				end
			)
		end,
	},
}
