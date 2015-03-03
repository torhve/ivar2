local util = require'util'
local simplehttp = util.simplehttp
local json = util.json

customHosts['twitch%.tv'] = function(queue, info)
	local path = info.path

	if(not path) then
		return
	end

	local username, kind, video
	if(path:match('/[^/]+/[^/]+/[^/]+')) then
		username, kind, video = path:match('/([^/]+)/([^/]+)/(%d+)')
	elseif(path:match('/[^/]+')) then
		username = path:match('[^/]+')
	end

	if(not username) then
		return
	end

	local url
	if(video) then
		url = string.format('https://api.twitch.tv/kraken/videos/%s%s', kind, video)
	else
		url = string.format('https://api.twitch.tv/kraken/channels/%s', username)
	end

	simplehttp(
		url,

		function(data, url, response)
			local resp = json.decode(data)

			local out = {}
			if(resp.title) then
				table.insert(out, resp.title)
			else
				table.insert(out, string.format('\002%s\002: ', resp.display_name))
				table.insert(out, (resp.status:gsub('\n', ' ')))
			end

			if(resp.game ~= json.null) then
				table.insert(out, string.format(" (Playing: %s)", resp.game))
			end

			queue:done(table.concat(out))
		end
	)

	return true
end
