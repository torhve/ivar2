package.path = table.concat({
	'libs/?.lua',
	'libs/?/init.lua',
	'spec/?.lua',
	'',
}, ';') .. package.path

package.cpath = table.concat({
	'libs/?.so',
	'',
}, ';') .. package.cpath

local busted = require 'busted'
local describe = busted.describe
local it = busted.it
local before_each = busted.before_each
local after_each = busted.after_each
local helper = require 'module_helper'

-- Canned responses keyed by URL fragment, filled per test. The module
-- captures util.simplehttp at require time, so the dispatcher reads this
-- table at call time.
local responses = {}
local requests = {}

local function installFakeUtil()
	local real_util = require 'util'
	local fake = setmetatable({}, { __index = real_util })
	fake.simplehttp = function(url, cb)
		local uri = type(url) == 'table' and url.url or url
		table.insert(requests, uri)
		local body, status
		for fragment, canned in pairs(responses) do
			if uri:find(fragment, 1, true) then
				body = canned.body
				status = canned.status or 200
				break
			end
		end
		local response = { status_code = status }
		if cb then cb(body, uri, response) end
		return body, uri, response
	end
	package.loaded['util'] = fake
	return real_util
end

local function makeMock()
	local mock = helper.mock_ivar2({
		config = {
			prefix = '!',
			nick = 'bot',
			twitchApiKey = 'clientid',
			twitchApiSecret = 'secret',
		},
	})
	local stored = {}
	mock.persist = setmetatable({}, {
		__index = function(_, k) return stored[k] end,
		__newindex = function(_, k, v) stored[k] = v end,
	})
	mock.channels = { ['#test'] = true }
	mock.messages = {}
	mock.Msg = function(self, evtype, destination, source, str, ...)
		table.insert(mock.messages, {
			dest = destination,
			text = select('#', ...) > 0 and string.format(str, ...) or str,
		})
	end
	return mock
end

-- helper.invoke only forwards the first capture group, so handlers taking
-- several arguments are dispatched directly.
local function invokeHandler(ctx, pattern, ...)
	local captures = helper.capture_env(ctx.mock)
	local handler = ctx.mod.PRIVMSG[pattern]
	setfenv(handler, captures.env)
	handler(ctx.mock, { nick = 'tester' }, '#test', ...)
	return captures
end

local TOKEN = {
	body = '{"access_token":"tok","token_type":"bearer","expires_in":3600}',
}

local SEARCH = {
	body = '{"data":[{"broadcaster_login":"foo","display_name":"Foo",'
		.. '"game_name":"Minecraft","title":"Hello","broadcaster_language":"en"}]}',
}

local STREAM = {
	body = '{"data":[{"user_login":"foo","user_name":"Foo",'
		.. '"game_name":"Minecraft","title":"Hello","viewer_count":4200,'
		.. '"started_at":"2026-11-02T10:00:00Z","broadcaster_language":"en"}]}',
}

local UNAUTHORIZED = {
	body = '{"error":"Unauthorized","status":401,"message":"Invalid OAuth token"}',
	status = 401,
}

describe('twitch', function()
	local real_util

	before_each(function()
		requests = {}
		responses = {}
		real_util = installFakeUtil()
	end)

	after_each(function()
		package.loaded['util'] = real_util
	end)

	it('reports no streams instead of crashing on an error response', function()
		responses['oauth2/token'] = TOKEN
		responses['/helix/search/channels'] = UNAUTHORIZED
		local ctx = helper.context('twitch', makeMock())
		ctx:invoke('!twitch Minecraft')
		assert.are_equal(1, #ctx.mock.messages)
		assert.are_equal('No streams found', ctx.mock.messages[1].text)
	end)

	it('keeps the alert timer alive across error responses', function()
		responses['oauth2/token'] = TOKEN
		responses['/helix/search/channels'] = UNAUTHORIZED
		local mock = makeMock()
		local ctx = helper.context('twitch', mock)
	invokeHandler(ctx, '^%ptwitchalert (%d+) (.*)$', '10', 'Minecraft')
		mock._timer_cb()
		mock._timer_cb()
		assert.are_equal(0, #mock.messages)
	end)

	it('skips API calls until the token is available', function()
		-- No token canned, so the first call must not reach the API
		responses['/helix/search/channels'] = UNAUTHORIZED
		local ctx = helper.context('twitch', makeMock())
		ctx:invoke('!twitch Minecraft')
		local sawApi = false
		for _, uri in pairs(requests) do
			if uri:find('/helix/', 1, true) then sawApi = true end
		end
		assert.is_false(sawApi)
		assert.are_equal('No streams found', ctx.mock.messages[1].text)
	end)

	it('alerts once per stream and honours the viewer limit', function()
		responses['oauth2/token'] = TOKEN
		responses['/helix/search/channels'] = SEARCH
		responses['/helix/streams'] = STREAM
		local mock = makeMock()
		local ctx = helper.context('twitch', mock)
	invokeHandler(ctx, '^%ptwitchalert (%d+) (.*)$', '10', 'Minecraft')
		assert.are_equal(1, #mock.messages)
		assert.is_truthy(mock.messages[1].text:find('twitch.tv/Foo'))
		assert.is_truthy(mock.messages[1].text:find('4k'))

		-- Same started_at on the next poll must not alert again
		mock._timer_cb()
		assert.are_equal(1, #mock.messages)
	end)

	it('stays silent below the viewer limit', function()
		responses['oauth2/token'] = TOKEN
		responses['/helix/search/channels'] = SEARCH
		responses['/helix/streams'] = STREAM
		local mock = makeMock()
		local ctx = helper.context('twitch', mock)
	invokeHandler(ctx, '^%ptwitchalert (%d+) (.*)$', '9000', 'Minecraft')
		assert.are_equal(0, #mock.messages)
	end)

	it('lists top live streams through the helix endpoint', function()
		responses['oauth2/token'] = TOKEN
		responses['/helix/streams'] = STREAM
		local mock = makeMock()
		local ctx = helper.context('twitch', mock)
		ctx:invoke('!twitch')
		assert.are_equal(1, #mock.messages)
		assert.is_truthy(mock.messages[1].text:find('http://twitch.tv/foo'))
	end)

	it('sorts results by viewer count', function()
		responses['oauth2/token'] = TOKEN
		responses['/helix/search/channels'] = {
			body = '{"data":[{"broadcaster_login":"low","display_name":"Low",'
				.. '"game_name":"Minecraft","title":"a","broadcaster_language":"en"},'
				.. '{"broadcaster_login":"high","display_name":"High",'
				.. '"game_name":"Minecraft","title":"b","broadcaster_language":"en"}]}',
		}
		responses['/helix/streams?user_login=low'] = {
			body = '{"data":[{"user_login":"low","viewer_count":5,"started_at":"x"}]}',
		}
		responses['/helix/streams?user_login=high'] = {
			body = '{"data":[{"user_login":"high","viewer_count":500,"started_at":"y"}]}',
		}
		local mock = makeMock()
		local ctx = helper.context('twitch', mock)
		ctx:invoke('!twitch Minecraft')
		assert.are_equal(2, #mock.messages)
		assert.is_truthy(mock.messages[1].text:find('twitch.tv/high'))
		assert.is_truthy(mock.messages[2].text:find('twitch.tv/low'))
	end)
end)
