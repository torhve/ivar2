-- OLD: http://developer.spotify.com/en/metadata-api/overview/
-- NEW: https://developer.spotify.com/web-api/migration-guide/
-- NEW: https://api.spotify.com/v1/tracks/3tLAA1LA06ecIaRSRbMFbi
local util = ivar2.util
local simplehttp = util.simplehttp
local json = util.json
local base64 = require'base64'

local spotify = ivar2.persist

local validType = {
	track = true,
	album = true,
	artist = true,
}

-- We could cache this, but the API is fairly speedy...
local getToken = function()
	local client_key = ivar2.config.spotifyApiKey
	local client_secret = ivar2.config.spotifyApiSecret

	if(not client_key or not client_secret) then
		ivar2:Log('warn', 'spotify: Client key and secret is not set in config file')
		return
	end

	local auth = base64.encode(
		string.format('%s:%s', client_key, client_secret)
	)

	local data = simplehttp(
		{
			url = 'https://accounts.spotify.com/api/token',
			method = 'POST',
			headers = {
				['Content-Type'] = 'application/x-www-form-urlencoded',
				['Authorization'] = string.format('Basic %s', auth)
			},
			data = 'grant_type=client_credentials'
		}
	)

	local info = json.decode(data)
	return info.access_token
end

local handlers = {
	track = function(jsdata)
		if(jsdata.description) then return nil, jsdata.description end
		if(jsdata.error) then return nil, jsdata.error.message end

		local title = jsdata.name
		local album = jsdata.album.name

		local artists = {}
		for _, artist in ipairs(jsdata.artists) do
			table.insert(artists, artist.name)
		end

		local popularity = jsdata.popularity .. '%'
		local preview = ''
		if jsdata.preview_url ~= json.null then
			preview = jsdata.preview_url .. '.mp3'
		end

		return true, string.format('%s - [%s] %s [%s] ➤ %s ♫♪', table.concat(artists, ', '), album, title, popularity, preview)
	end,

	album = function(jsdata)
		if(jsdata.description) then return jsdata.description end
		if(jsdata.error) then return nil, jsdata.error.message end

		local artists = {}
		for _, artist in ipairs(jsdata.artists) do
			table.insert(artists, artist.name)
		end
		local album = jsdata.name

		return true, string.format('%s - %s', table.concat(artists, ', '), album)
	end,

	artist = function(jsdata)
		if(jsdata.description) then return jsdata.description end
		if(jsdata.error) then return nil, jsdata.error.message end

		return true, jsdata.name
	end,
}

local handleData = function(metadata, jsdata)
	local success, message = handlers[metadata.type](jsdata)
	if(success) then
		return message
	else
		return string.format('%s error %s', metadata.uri, message)
	end
end

local handleOutput = function(data)
	if(data.num ~= 0) then return end

	local uris = {}
	local uriOrder = {}
	for i, meta in ipairs(data.handled) do
		local uri = meta.uri
		if(not uris[uri]) then
			table.insert(uriOrder, uri)
			meta.n = i
			uris[uri] = meta
		else
			uris[uri].n = string.format('%s+%d', uris[uri].n, i)
		end
	end

	local output = {}
	for i=1, #uriOrder do
		local lookup = uris[uriOrder[i]]
		table.insert(output, string.format('\002[%s]\002 %s - %s', lookup.n, lookup.info, lookup.open))
	end

	if(#output > 0) then
		ivar2:Msg('privmsg', data.destination, data.source, table.concat(output, ' '))
	end
end

-- https://api.spotify.com/v1/tracks/3tLAA1LA06ecIaRSRbMFbi
-- https://api.spotify.com/v1/albums/6G9fHYDCoyEErUkHrFYfs4
-- https://api.spotify.com/v1/artists/4YrKBkKSVeqDamzBPWVnSJ
local fetchInformation = function(output, n, info)
	if(spotify['spotify:'..info.uri] and tonumber(spotify['spotify:'.. info.uri .. ':timestamp']) > os.time()) then
		ivar2:Log('debug', string.format('spotify: Fetching %s from cache.', info.uri))

		info.info = spotify['spotify:'..info.uri]
		output.handled[n] = info
		output.num = output.num - 1

		handleOutput(output)
	else
		ivar2:Log('info', string.format('spotify: Requesting information on %s.', info.uri))

		local access_token = getToken()
		if(not access_token) then return end

		simplehttp(
			{
				url = ('https://api.spotify.com/v1/%ss/%s'):format(info.type, info.hash),
				method = 'GET',
				headers = {
					['Authorization'] = string.format('Bearer %s', access_token)
				}
			},

			function(data, url, response)
				local message = handleData(info, json.decode(data))
				-- New API doesn't provide a Expires header, but they do set
				-- cache-control public max-age 7200. If we were good citizens we
				-- could parse this. Alas, I'm lazy.
				local expires = os.time() + 7200

				spotify['spotify:'..info.uri] = message
				spotify['spotify:'..info.uri .. ':timestamp'] = expires

				output.handled[n] = info
				info.info = message
				output.num = output.num - 1

				handleOutput(output)
			end
		)
	end
end

return {
	PRIVMSG = {
		function(self, source, destination, argument)
			local tmp = {}
			local index = 0
			for uri, type, hash in argument:gmatch('(spotify:(%w+):(%S+))') do
				if(validType[type]) then
					index = index + 1

					tmp[index] = {
						uri = uri,
						type = type,
						hash = hash,
						open = ('http://open.spotify.com/%s/%s'):format(type, hash)
					}
				end
			end

			if(index > 0) then
				local output = {
					num = index,
					source = source,
					destination = destination,

					handled = {}
				}

				for i=1, #tmp do
					fetchInformation(output, i, tmp[i])
				end
			end
		end,
	}
}
