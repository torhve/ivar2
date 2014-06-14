local simplehttp = require'simplehttp'

local pattern = ('<td>[^<]+</td><td>([^<]+)</td>'):rep(3) .. '<td>([^<]+)</td>'
local parseData = function(source, destination, data, anime)
	data = data:match'Airing</h1>(.-)<h1>'
	data = data:gsub('<td.->', '<td>'):gsub('</?a.->', ''):gsub('[\r\n]+', '')
	-- FIXME: This match is _steps_ away from locking on the C side.
	for entry in data:gmatch'<tr.->(.-)</tr>' do
		for title, channel,airtime,eta in entry:gmatch(pattern) do
			if(title:lower():find(anime, 1, true)) then
				return ivar2:Msg('privmsg', destination, source, '%s airs on %s on %s (ETA: %s)', title, channel, airtime, eta:sub(1, -2))
			end
		end
	end

	ivar2:Msg('privmsg', destination, source, 'Fool! I found nothing by that name... :(')
end

return {
	PRIVMSG = {
		['^%pairs%s*$'] = function(self, source, destination)
			self:Msg('privmsg', destination, source, 'Returns air time, ETA and channel for <anime>. Usage: !airs <anime>.')
		end,

		['^%pairs (.+)$'] = function(self, source, destination, anime)
			simplehttp('http://www.mahou.org/Showtime/', function(data)
				parseData(source, destination, data, anime:lower())
			end)
		end,
	},
}
