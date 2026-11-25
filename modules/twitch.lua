-- Module to display, search and alert twitch.tv streams
-- vim: set noexpandtab:
local util = require'util'
local simplehttp = util.simplehttp
local json = util.json
local moduleName = 'twitch'
local key = moduleName
local store = ivar2.persist

local lconsole = require'logging.console'
local log = lconsole()
local oauth_bearer = ''
local token_pending = false

local function getToken()
	if token_pending then
		return
	end
	token_pending = true

	local tokenurl = "https://id.twitch.tv/oauth2/token?client_id="
		..ivar2.config.twitchApiKey
		..'&client_secret='
		..ivar2.config.twitchApiSecret
		..'&redirect_uri=http://localhost&response_type=token&grant_type=client_credentials&scope='

	simplehttp({
		url = tokenurl,
		method = 'POST',
		},
		function(data, uri, response)
			token_pending = false
			local ok, info = pcall(json.decode, data or '')
			if not ok or type(info) ~= 'table' or not info.access_token then
				log:error('twitch: token request failed (status %s): %s',
					tostring(response and response.status_code), tostring(data))
				return
			end
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
		if oauth_bearer == '' then
			-- The token arrives asynchronously, so there's nothing to call yet
			return nil
		end
	end

	local data, _, response = simplehttp({
		url='https://api.twitch.tv' .. url,
		-- HTTP doesn't allow lowercase headers
		version=1.1,
		headers={
			['Authorization'] = string.format("Bearer %s", oauth_bearer),
			['Client-ID'] = ivar2.config.twitchApiKey,
			['Accept'] = 'application/vnd.twitchtv.v5+json',
		}
	}, cb)

	if response and (response.status_code == 401 or response.status_code == 403) then
		-- Expired or invalid token, fetch a new one for the next call
		oauth_bearer = ''
		log:error('twitch: %s rejected with %s: %s', url,
			tostring(response.status_code), tostring(data))
		getToken()
	end

	return data
end

-- Decode a Helix response. Returns nil for error responses (no data field).
local decodeData = function(data)
	if data == nil or data == '' then
		return nil
	end
	local ok, decoded = pcall(json.decode, data)
	if not ok or type(decoded) ~= 'table' or type(decoded.data) ~= 'table' then
		if data:find('error') then
			log:error('twitch: API error: %s', data:sub(1, 200))
		end
		return nil
	end
	return decoded
end

local streamLookup = function(user_login)
	local decoded = decodeData(twitchAPICall(
		string.format('/helix/streams?user_login=%s', user_login)))
	if decoded == nil then
		return nil
	end
	return decoded.data[1]
end

local formatViewers = function(viewers)
	if viewers > 1000 then
		return tostring(math.floor(viewers/1000)) .. 'k'
	end
	return viewers
end

local parseData = function(self, source, destination, data, search)
	data = decodeData(data)
	if data == nil then
		return {}
	end

	local streams = {}

	for i=1, #data.data do
		local this = data.data[i]
		-- /helix/streams reports user_login/user_name rather than
		-- broadcaster_login/display_name
		this.broadcaster_login = this.broadcaster_login or this.user_login
		this.display_name = this.display_name or this.user_name
		local lang = this.broadcaster_language
		--TODO configure filter languages ?
		if lang and (lang == 'en' or lang == 'no') then
			if search then
				-- Check for search string in game or channel name
				-- since twitch search API also does title search
				if (this.display_name or ''):lower():match(search:lower())
					or (this.game_name and this.game_name ~= json.null
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
	for _, stream in ipairs(streams) do
		local stream_data = streamLookup(stream.broadcaster_login)
		if stream_data then
			stream.viewer_count = stream_data.viewer_count
		end
	end
	-- sort streams wrt viewer count
	table.sort(streams, function(a, b)
		return (a.viewer_count or 0) > (b.viewer_count or 0)
	end)
	for _, stream in ipairs(streams) do
		local title = stream.title and (': '..stream.title) or ''
		local viewers = formatViewers(stream.viewer_count or 0)
		out[#out+1] = string.format(
			"[%s] http://twitch.tv/%s %s %s",
			util.bold(viewers), stream.broadcaster_login,
			stream.game_name ~= json.null and stream.game_name or '', title
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
	local data = twitchAPICall('/helix/streams?first=20&sort=viewer_count')
	local streams = parseData(self, source, destination, data)
	if #streams == 0 then
		self:Msg('privmsg', destination, source, 'No streams found')
		return
	end
	local out = formatData(self, source, destination, streams)
	for _, line in pairs(out) do
		self:Msg('privmsg', destination, source, line)
	end
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
			for _, stream in ipairs(streams) do
				-- search/channels doesn't report started_at, take it from the lookup
				local stream_data = streamLookup(stream.broadcaster_login)
				if stream_data then
					local started_at = stream_data.started_at or stream.started_at
					stream.viewers = stream_data.viewer_count or 0
					if alerts[stream.broadcaster_login] ~= started_at and
						-- Check if we meet viewer limit
						stream.viewers > (game.limit or 0) then
						alerts[stream.broadcaster_login] = started_at
						store[alertsKey] = alerts
						ivar2:Msg('privmsg',
							game.channel,
							ivar2.nick,
							"[%s] [%s] %s %s",
							util.bold(game.name),
							util.bold(formatViewers(stream.viewers)),
							'https://twitch.tv/'..stream.display_name,
							stream.title or ''
						)
					end
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
