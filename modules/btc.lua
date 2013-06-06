local simplehttp = require'simplehttp'
local json = require'json'

local APIBase = 'https://blockchain.info/no/ticker'
return {
	PRIVMSG = {
		['^.btc$'] = function(self, source, destination, input)
			simplehttp(APIBase, function(data)
					local result = json.decode(data)

					if(result) then
						self:Msg('privmsg', destination, source, string.format('1BTC is worth %s€ (~15m)', source.nick, result["EUR"]["15min"]))
					end
				end
			)
		end,
	},
}
