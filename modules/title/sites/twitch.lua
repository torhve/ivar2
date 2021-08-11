local util = require'util'
local simplehttp = util.simplehttp
local json = util.json

local oauth_bearer = ''

local function getToken()
    local tokenurl = "https://id.twitch.tv/oauth2/token?client_id="..ivar2.config.twitchApiKey..'&client_secret='..ivar2.config.twitchApiSecret..'&redirect_uri=http://localhost&response_type=token&grant_type=client_credentials&scope='
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

-- get initial token
getToken()

local twitchAPICall = function(url, cb)
	return simplehttp({
		url=url,
		-- HTTP doesn't allow lowercase headers
		version=1.1,
		headers={
			['Authorization'] = string.format("Bearer %s", oauth_bearer),
			['Client-ID'] = ivar2.config.twitchApiKey,
			['Accept'] = 'application/vnd.twitchtv.v5+json',
		}},
		cb)
end

-- get oauth token
getToken()

customHosts['twitch%.tv'] = function(queue, info)
	if not ivar2.config.twitchApiKey then
		return
	end

	local path = info.path
	if(not path) then
		return
	end

	local url

	if(path:match('^/videos/(%d+)')) then
    local video = path:match('^/videos/(%d+)')
		url = string.format('https://api.twitch.tv/helix/videos/%s', video)
	elseif(path:match('/[^/]+')) then
		local channel = path:match('[^/]+')
		twitchAPICall(string.format('https://api.twitch.tv/helix/users?login=%s', channel), function(data, final_url, response)
			data = json.decode(data)
			local username = data['data'][1]['id']
			url = string.format('https://api.twitch.tv/helix/channels?broadcaster_id=%s', username)
		end)
	end

	if(not url) then
		return
	end


	twitchAPICall(url, function(data, final_url, response)
			local resp = json.decode(data)
			resp = resp['data'][1]

			local out = {}
			if(resp['error']) then
				table.insert(out, resp['error'])
				table.insert(out, ': ')
				table.insert(out, resp['message'])
				queue:done(table.concat(out))
				return
			end
			if(resp.title) then
				table.insert(out, resp.title)
			else
				table.insert(out, string.format('\002%s\002: ', resp.broadcaster_name))
				if(resp.status) then
					table.insert(out, (tostring(resp.status):gsub('\n', ' ')))
				end
			end

			if(resp.game ~= json.null) then
				table.insert(out, string.format(" (Playing: %s)", resp.game_name))
			end

			queue:done(table.concat(out))
		end
	)

	return true
end
