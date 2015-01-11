-- Module to display, search and alert twitch.tv streams
-- vim: set noexpandtab:
local util = require'util'
local simplehttp = util.simplehttp
local json = util.json
local moduleName = 'twitch'
local key = moduleName
local store = ivar2.persist

local parseData = function(self, source, destination, data)
	data = json.decode(data)

	if data._total == 0 then
		return {}
	end

	local streams = {}
	for i=1, #data.streams do
		local this = data.streams[i]
		local lang = this.channel.broadcaster_language
		--TODO configure filter languages ?
		if lang and (lang == 'en' or lang == 'no') then
			table.insert(streams, this)
		end
	end

	-- sort streams wrt viewer count
	table.sort(streams, function(a,b) return a.viewers>b.viewers end)
	return streams
end

local formatData = function(self, source, destination, streams, limit)
	limit = limit or 5
	local i = 0
	local out = {}
	for _, stream in pairs(streams) do
		local viewers = tostring(math.floor(stream.viewers/1000)) .. 'k'
		if viewers == '0k' then
			viewers = stream.viewers
		end
		local title = ''
		if stream.channel and stream.channel.status then
			title = ': '..stream.channel.status
		end
		out[#out+1] = string.format(
			"[%s] http://twitch.tv/%s %s %s",
			util.bold(viewers), stream.channel.display_name, stream.game, title
		)
		i=i+1
		if i > limit then break end
	end
	return out
end

local gameHandler= function(self, source, destination, input, limit)
	limit = limit or 5
	--	'http://api.twitch.tv/kraken/streams?limit=20&offset=0&game='..util.urlEncode(input)..'&on_site=1',
	simplehttp(
		'https://api.twitch.tv/kraken/search/streams?limit='..tostring(limit)..'&offset=0&query='..util.urlEncode(input),
		function(data)
			local streams = parseData(self, source, destination, data)
			if #streams == 0 then
				local out = 'No streams found'
				self:Msg('privmsg', destination, source, out)
			else
				local out = formatData(self, source, destination, streams, limit)
				for _,line in pairs(out) do
					self:Msg('privmsg', destination, source, line)
				end
			end
		end
	)
end

local allHandler = function(self, source, destination)
	local url = 'https://api.twitch.tv/kraken/streams'
	simplehttp(
		url,
		function(data)
			local streams = parseData(self, source, destination, data)
			local out = formatData(self, source, destination, streams)
			for _,line in pairs(out) do
				self:Msg('privmsg', destination, source, line)
			end
		end
	)
end

local checkStreams = function()
	for c,_ in pairs(ivar2.channels) do
		local gamesKey = key..':'..c
		local games = store[gamesKey] or {}
		local alertsKey = gamesKey .. ':alerts'
		local alerts = store[alertsKey] or {}
		for name, game in pairs(games) do
			local limit = 5
			simplehttp(
				string.format(
					'https://api.twitch.tv/kraken/search/streams?limit=%s&offset=0&query=%s',
					tostring(limit),
					util.urlEncode(game.name)
				),
				function(data)
					local streams = parseData(ivar2, nil, c, data, limit)
					for _, stream in pairs(streams) do
						-- Use Created At to check for uniqueness
						if alerts[stream.channel.name] ~= stream.created_at and
						  -- Check if we meet viewer limit
						  stream.viewers > game.limit then
							alerts[stream.channel.name] = stream.created_at
							store[alertsKey] = alerts
							ivar2:Msg('privmsg',
								game.channel,
								ivar2.nick,
								"[%s] [%s] %s %s",
								util.bold(game.name),
								util.bold(tostring(math.floor(stream.viewers/1000))..'k'),
								'http://twitch.tv/'..stream.channel.display_name,
								stream.channel.status
							)
						end
					end
				end
			)
		end
	end
end

-- Start the stream alert poller
ivar2:Timer('twitch', 300, 300, checkStreams)

local regAlert = function(self, source, destination, limit, name)
	local gamesKey = key..':'..destination
	local games = store[gamesKey] or {}
	games[name] = {channel=destination, name=name, limit=tonumber(limit)}
	store[gamesKey] = games
	reply('Ok. Added twitch alert.')
	checkStreams()
end

local listAlert = function(self, source, destination)
	local gamesKey = key..':'..destination
	local games = store[gamesKey] or {}
	local out = {}
	for name, game in pairs(games) do
		out[#out+1] = name
	end
	if #out > 0 then
		say('Alerting following terms: %s', table.concat(out, ', '))
	else
		say('No alerting here.')
	end
end

local delAlert = function(self, source, destination, name)
	local gamesKey = key..':'..destination
	local games = store[gamesKey] or {}
	games[name] = nil
	store[gamesKey] = games
	reply('Ok. Removed twitch alert.')
end

return {
	PRIVMSG = {
		['^%ptwitch$'] = allHandler,
		['^%ptwitch (.*)$'] = gameHandler,
		['^%ptwitchalert (%d+) (.*)$'] = regAlert,
		['^%ptwitchalert list$'] = listAlert,
		['^%ptwitchalert del (.*)$'] = delAlert,
	},
}
