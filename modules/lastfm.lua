local util = require'util'
local simplehttp = util.simplehttp
local json = util.json

local utify8 = function(str)
	str = str:gsub("\\u(....)", function(n)
		n = tonumber(n, 16)

		if(n < 128) then
			return string.char(n)
		elseif(n < 2048) then
			return string.char(192 + ((n - (n % 64)) / 64), 128 + (n % 64))
		else
			return string.char(224 + ((n - (n % 4096)) / 4096), 128 + (((n % 4096) - (n % 64)) / 64), 128 + (n % 64))
		end
	end)

	return str
end

local APIBase = 'http://ws.audioscrobbler.com/2.0/?format=json&api_key=' .. ivar2.config.lastfmAPIKey

local buildQuery = function(param)
	local url = {APIBase}

	for k, v in next, param do
		table.insert(url, string.format('%s=%s', k, v))
	end

	return table.concat(url, '&')
end

local pattern = ('<td>[^<]+</td><td>([^<]+)</td>'):rep(3) .. '<td>([^<]+)</td>'
local parseTopArtists = function(source, destination, data)
	local response = json.decode(utify8(data))
	if(response.error) then
		return response.message
	end

	local info = response.topartists
	if(info.total == '0') then
		return "%s doesn't have any plays in the last 7 days.", info.user
	end

	local out = {}
	-- Handle single entries.
	if(info.artist.name) then
		local entry = info.artist
		table.insert(out, string.format('%s (%s)', entry.name, entry.playcount))
	else
		for i=1, #info.artist do
			local entry = info.artist[i]
			table.insert(out, string.format('%s (%s)', entry.name, entry.playcount))
		end
	end

	return "%s's top artists the last 7 days: %s | http://last.fm/user/%s",
		info['@attr'].user,
		table.concat(out, ', '),
		info['@attr'].user
	
end

local parseRecentTracks = function(source, destination, data)
	local response = json.decode(utify8(data))
	if(response.error) then
		return response.message
	end

	-- This should only be the case if someone tries to lookup a registered user
	-- with no plays registered.
	local info = response.recenttracks
	if(info.total == '0') then
		return "%s doesn't have any recently played tracks.", info['@attr'].user
	end

	local track = info.track[1]
	if(not track) then
		return "%s is currently not listening to music.", info['@attr'].user
	end

	local out = {
		string.format("%s's now playing:", info['@attr'].user),
		string.format('%s -', track.artist['#text']),
	}

	local album = track.album['#text']
	if(album ~= '') then
		table.insert(out, string.format('[%s]', album))
	end

	table.insert(out, track.name)
    table.insert(out, string.format(' %s', '♫♪'))

	return table.concat(out, ' ')
end

local getUser = function(source)
	user = source.nick
	puser = ivar2.persist['lastfm:'..user]
	if puser then
		user = puser
	end
	return user
end

return {
	PRIVMSG = {
		['^%pset lastfm (.+)$'] = function(self, source, destination, user)
			ivar2.persist['lastfm:'..source.nick] = user
			reply('Username set to %s', user)
		end,
		['^%plastfm (.+)$'] = function(self, source, destination, user)
			simplehttp(
				buildQuery{
					method = 'user.getTopArtists',
					period = '7day',
					limit = '5',
					user = user,
				},
				function(data)
					say(parseTopArtists(source, destination, data))
				end
			)
		end,

		['^%plastfm%s*$'] = function(self, source, destination, user)
			simplehttp(
				buildQuery{
					method = 'user.getTopArtists',
					period = '7day',
					limit = '5',
					user = getUser(source),
				},
				function(data)
					say(parseTopArtists(source, destination, data))
				end
			)
		end,

		['^%pnp (.+)$'] = function(self, source, destination, user)
			simplehttp(
				buildQuery{
					method = 'user.getRecentTracks',
					limit = '1',
					user = user,
				},
				function(data)
					say(parseRecentTracks(source, destination, data))
				end
			)
		end,

		['^%pnp%s*$'] = function(self, source, destination)
			simplehttp(
				buildQuery{
					method = 'user.getRecentTracks',
					limit = '1',
					user = getUser(source),
				},

				function(data)
					say(parseRecentTracks(source, destination, data))
				end
			)
		end,
	},
}
