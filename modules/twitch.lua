-- Module to display, search and alert twitch.tv streams
-- vim: set noexpandtab:
local util = require'util'
local simplehttp = util.simplehttp
local json = util.json
local moduleName = 'twitch'
local key = moduleName
local store = ivar2.persist

local oauth_bearer = ''

local function getToken()
	local tokenurl = "https://id.twitch.tv/oauth2/token?client_id="
		..ivar2.config.twitchApiKey
		..'&client_secret='
		..ivar2.config.twitchApiSecret
		..'&redirect_uri=http://localhost&response_type=token&grant_type=client_credentials&scope='

	simplehttp({
		url = tokenurl,
		method = 'POST',
			headers = {
				--['Content-Type'] = 'application/x-www-form-urlencoded;charset=UTF-8',
				['Authorization'] = string.format( "OAuth %s", ivar2.config.twitchApiSecret)
			},
		},
		function(data)
			local info = json.decode(data)
			-- Save access token for further use
			oauth_bearer = info.access_token
		end
	)
	return true
	end

local twitchAPICall = function(url, cb)
	-- get initial token
	if oauth_bearer == '' then
		getToken()
	end

	return simplehttp({
		url='https://api.twitch.tv' .. url,
		-- HTTP doesn't allow lowercase headers
		version=1.1,
		headers={
			['Authorization'] = string.format("Bearer %s", oauth_bearer),
			['Client-ID'] = ivar2.config.twitchApiKey,
			['Accept'] = 'application/vnd.twitchtv.v5+json',
		}
	}, cb)
end

local streamLookup = function(user_login)
		local data = twitchAPICall(string.format('/helix/streams?user_login=%s', user_login))

		data = json.decode(data)
		local stream = data['data'][1]
		return stream
end

local formatViewers = function(viewers)
	if viewers > 1000 then
		return tostring(math.floor(viewers/1000)) .. 'k'
	end
	return viewers
end

local parseData = function(self, source, destination, data, search)
	data = json.decode(data)

	if data._total == 0 then
		return {}
	end

	local streams = {}

	for i=1, #data.data do
		local this = data.data[i]
		local lang = this.broadcaster_language
		--TODO configure filter languages ?
		if lang and (lang == 'en' or lang == 'no') then
			if search then
				-- Check for search string in game or channel name
				-- since twitch search API also does title search
				if this.display_name:lower():match(search:lower())
					or (this.game_name ~= json.null
					and this.game_name:lower():match(search:lower())) then
					table.insert(streams, this)
				end
			else
				table.insert(streams, this)
			end
		end
	end

	return streams
end

local formatData = function(self, source, destination, streams, limit)
	limit = limit or 5
	local i = 0
	local out = {}
	for _, stream in pairs(streams) do
		local stream_data = streamLookup(stream.broadcaster_login)
		stream.viewer_count = stream_data.viewer_count
	end
	-- sort streams wrt viewer count
	table.sort(out, function(a,b) return a.viewer_count or 0 >b.viewer_count or 0 end)
	for _, stream in pairs(streams) do
		local title = ': '..stream.title
		local viewers = formatViewers(stream.viewer_count or 0)
		out[#out+1] = string.format(
			"[%s] http://twitch.tv/%s %s %s",
			util.bold(viewers), stream.broadcaster_login, stream.game_name, title
		)
		i=i+1
		if i > limit then break end
	end
	return out
end

local gameHandler = function(self, source, destination, input, limit)
	limit = limit or 5
	local data = twitchAPICall('/helix/search/channels?first='
		..tostring(limit)
		..'&live_only=true&query='
		..util.urlEncode(input))
	local streams = parseData(self, source, destination, data, input)
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

local allHandler = function(self, source, destination)
	local url = 'https://api.twitch.tv/kraken/streams'
	simplehttp({
		url=url,
		headers={
			['Client-ID'] = ivar2.config.twitchApiKey,
		}},
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
			local data = twitchAPICall('/helix/search/channels?first='
				..tostring(limit)
				..'&live_only=true&query='
				..util.urlEncode(game.name))
			local streams = parseData(ivar2, nil, c, data, game.name)
			for _, stream in pairs(streams) do
				-- Use started_at to check for uniqueness
				local stream_data = streamLookup(stream.broadcaster_login)
				stream.viewers = stream_data.viewer_count
				if alerts[stream.broadcaster_login] ~= stream.started_at and
					-- Check if we meet viewer limit
					stream.viewers > game.limit then
					alerts[stream.broadcaster_login] = stream.started_at
					store[alertsKey] = alerts
					ivar2:Msg('privmsg',
						game.channel,
						ivar2.nick,
						"[%s] [%s] %s %s",
						util.bold(game.name),
						util.bold(formatViewers(stream.viewers)),
						'https://twitch.tv/'..stream.display_name,
						stream.title
					)
				end
			end
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
	if not games[name] then
		return reply('No alerting found. Check name and be sensitive, to the case!')
	end
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
