-- Module to display and/or search twitch.tv streams
local util = require'util'
local simplehttp = util.simplehttp
local json = util.json

local parseData = function(self, source, destination, data, search)
	data = json.decode(data)

	local streams = {}
	local addStream = function(name, viewers, game)
		table.insert(streams, {
			name=name,
			viewers=viewers,
			game=game,
		})
	end

	for i=1, #data.streams do
		local this = data.streams[i]
		local name = this.channel.display_name
		local viewers = this.viewers
		local game = this.game
		if search then
			if string.find(name:lower(), search:lower()) or string.find(game:lower(), search:lower()) then
				addStream(name, viewers, game)
			end
		else
			addStream(name, viewers, game)
		end
	end

	-- sort streams wrt viewer count
	table.sort(streams, function(a,b) return a.viewers>b.viewers end)
	local i = 0

	local i = 0
	for _, stream in pairs(streams) do
		i=i+1
		local out = {}
		local ins = function(fmt, ...)
			for i=1, select('#', ...) do
				local val = select(i, ...)
				if(type(val) == 'nil' or val == -1) then
					return
				end
			end

			table.insert(
				out,
				string.format(fmt, ...)
			)
		end
		ins(
			"http://twitch.tv/\002%s\002 %d watching %s",
			stream.name, stream.viewers, stream.game
		)
		self:Msg('privmsg', destination, source, (table.concat(out, " ")))
		if i==6 then break end
	end

end

local url= 'https://api.twitch.tv/kraken/streams'
local handler = function(self, source, destination, input)
	simplehttp(
		url,
		function(data)
			parseData(self, source, destination, data, input)
		end
	)
end

local allHandler = function(self, source, destination, input)
	handler(self, source, destination)
end

return {
	PRIVMSG = {
		['^%ptwitch$'] = allHandler,
		['^%ptwitch (.*)$'] = handler,
	},
}
