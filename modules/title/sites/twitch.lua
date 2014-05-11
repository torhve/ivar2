local simplehttp = require'simplehttp'
local json = require'json'

customHosts['twitch%.tv'] = function(queue, info)
	local path = info.path

	if(not path) then
		return
	end

	local username, video
	if(path:match('/[^/]+/[^/]+/[^/]+')) then
		username, video = path:match('/([^/]+)/[^/]+/(%d+)')
	elseif(path:match('/[^/]+')) then
		username = path:match('[^/]+')
	end

	if(not username) then
		return
	end

	local url
	if(video) then
		url = string.format('https://api.twitch.tv/kraken/videos/a%s', video)
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

				if(resp.game) then
					table.insert(out, string.format(" (Playing: %s)", resp.game))
				end
			else
				table.insert(out, string.format('\002%s\002: ', resp.display_name))
				table.insert(out, (resp.status:gsub('\n', ' ')))
			end

			queue:done(table.concat(out))
		end
	)

	return true
end
