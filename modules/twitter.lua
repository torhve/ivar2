local simplehttp = require'simplehttp'
local json = require'json'
local html2unicode = require'html'
local base64 = require 'base64'

local access_token
local key = ivar2.config.twitterApiKey
local secret = ivar2.config.twitterApiSecret

local function outputTweet(self, source, destination, info)
	local name = info.user.name
	local screen_name = html2unicode(info.user.screen_name)
	local tweet
	if info.retweeted_status then
		local rter = info.retweeted_status.user.screen_name
		tweet = 'RT @'..rter..': '..html2unicode(info.retweeted_status.text)
	else
		tweet = html2unicode(info.text)
	end

	local out = {}
	if(name == screen_name) then
		table.insert(out, string.format('\002%s\002:', name))
	else
		table.insert(out, string.format('\002%s\002 @%s:', name, screen_name))
	end

	table.insert(out, tweet)
	self:Msg('privmsg', destination, source, table.concat(out, ' '))
end

local function getStatus(self, source, destination, tid)
	simplehttp({
		url = string.format('https://api.twitter.com/1.1/statuses/show/%s.json', tid),
		headers = {
			['Authorization'] = string.format("Bearer %s", access_token)
		},
	},
	function(data)
		local info = json.decode(data)
		outputTweet(self, source, destination, info)
	end
	)
end


local function getLatestStatuses(self, source, destination, screen_name, count)
	if not count then
		count = 1
	else
		count = tonumber(count)
	end
	simplehttp({
			url = string.format('https://api.twitter.com/1.1/statuses/user_timeline.json?exclude_replies=true&screen_name=%s', screen_name),
			headers = {
				['Authorization'] = string.format("Bearer %s", access_token)
			},
		},
		function(data)
			local info = json.decode(data)
			outputTweet(self, source, destination, info[count])
		end
	)
end


local function getToken()
	local tokenurl = "https://api.twitter.com/oauth2/token"
	simplehttp({
			url = tokenurl,
			method = 'POST',
			headers = {
				['Content-Type'] = 'application/x-www-form-urlencoded;charset=UTF-8',
				['Authorization'] = string.format( "Basic %s", base64.encode(
							string.format( "%s:%s",
								ivar2.config.twitterApiKey,
								ivar2.config.twitterApiSecret
							)
						)
					)
			},
			data = 'grant_type=client_credentials',
		},
		function(data)
			local info = json.decode(data)
			-- Save access token for further use
			access_token = info.access_token
		end
	)
	return true
end

-- get initial token
getToken()

return {
	PRIVMSG = {
		['^%ptwitter (%d+)$'] = function(self, source, destination, tid)
			getStatus(self, source, destination, tid)
		end,
		['^%ptweet (%d+)$'] = function(self, source, destination, tid)
			getStatus(self, source, destination, tid)
		end,
		['^%ptwitter ([a-zA-Z0-9_]+)$'] = function(self, source, destination, screen_name)
			getLatestStatuses(self, source, destination, screen_name)
		end,
		['^%ptweet ([a-zA-Z0-9_]+)$'] = function(self, source, destination, screen_name)
			getLatestStatuses(self, source, destination, screen_name)
		end,
		['^%ptwitter ([a-zA-Z0-9_]+) (%d+)$'] = function(self, source, destination, screen_name, count)
			getLatestStatuses(self, source, destination, screen_name, count)
		end,
		['^%ptweet ([a-zA-Z0-9_]+) (%d+)$'] = function(self, source, destination, screen_name, count)
			getLatestStatuses(self, source, destination, screen_name, count)
		end,
	},
}
