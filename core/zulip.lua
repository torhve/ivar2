-- vim: set noexpandtab:
--
-- Simple Zulip API meant to be run under cqueues
--
package.path = table.concat({
	'libs/?.lua',
	'libs/?/init.lua',

	'',
}, ';') .. package.path

package.cpath = table.concat({
	'libs/?.so',

	'',
}, ';') .. package.cpath

local lconsole = require'logging.console'
local log = lconsole()
local util = require 'util'

local base64 = require'base64'

local http = util.simplehttp
local urlEncode = util.urlEncode
local json = util.json

local zulip = {
	registerdata = nil,
	name = nil,
	channels = {},
	users = {},
	url = nil,
	handlers = {},
}

function zulip:Connect(server, email, token)
	self:Log('info', 'Authing and registering')

	self.server = server
	self.token = token
	self.email = email

	local auth = base64.encode(
		string.format('%s:%s', email, token)
	)

	local data = http(
		{
			url = string.format('https://%s/api/v1/register', server),
			method = 'POST',
			headers = {
				['Content-Type'] = 'application/x-www-form-urlencoded',
				['Authorization'] = string.format('Basic %s', auth)
			},
			data = '[event_types=["message,realm_user,custom_profile_fields,subscription,stream"],fetch_event_types=["realm_user","custom_profile_fields","subscription,stream"]]'
		}
	)
	if not data then
		return nil, 'No data returned'
	end
	data = json.decode(data)
	if not data then
		return nil, 'Invalid json'
	end
	if data.result and data.result == 'error' then
		self:Log('error', data.error)
		return nil, data.error
	end
	if not data.queue_id then
		return nil, 'No Queue Id: '..tostring(data)
	end

	self.registerdata = data

	self.queue_id = data.queue_id
	self.last_event_id = data.last_event_id

	for _, c in ipairs(data.subscriptions) do
		self:Log('info', 'Adding stream %s', c.name)
		self.channels[c.name] = c
	end

	for _, u in ipairs(data.realm_users) do
		self:Log('info', 'Adding user %s', u.full_name)
		self.users[u.email] = u
	end

	self.url = data.url

	self:Log('info', 'Connecting to events API')

	while true do
		local url = string.format("https://%s/api/v1/events?queue_id=%s&last_event_id=%s&dont_block=%s",
			server,
			self.queue_id,
			self.last_event_id,
			"false"
		)
		local edata = http(
			{
				url = url,
				method = 'GET',
				headers = {
					['Content-Type'] = 'application/x-www-form-urlencoded',
					['Authorization'] = string.format('Basic %s', auth)
				},
				--data = 'event_types=["message"],fetch_event_types=["realm_user,custom_profile_fields,subscription,stream"]'
			}
		)
		if not edata then
			return nil, 'No data returned'
		end
		edata = json.decode(edata)
		if not edata then
			return nil, 'Invalid json'
		end
		if edata.result and edata.result == 'error' then
			self:Log('error', edata.error)
			return nil, edata.error
		end

		for _, event in pairs(edata.events) do
			if event.id then
				self.last_event_id = event.id
			end
			if event.type == 'message' then
				self:Log('debug', '#%s:%s <%s> %s',
					event.message.display_recipient,
					event.message.subject,
					event.message.sender_short_name or event.message.sender_full_name,
					event.message.content
					)
			else
					self:Log('debug', 'event %s', json.encode(edata))
			end
			for id, fn in pairs(self.handlers[event.type] or {}) do
				if fn then
					fn(event)
				end
			end

		end
	end
end

function zulip:get_channel(id)
	local channel = self.channels[id]
	if not channel then
		return nil, 'Channel not found'
	end
	return channel.name
end

function zulip:get_user(id)
	local user = self.users[id]
	if not user then
		return nil, 'User not found'
	end
	return user.name
end

function zulip:Privmsg(destination, message)
	local msg_type = 'stream' -- or 'private'

	-- resolve channel
	--if destination:match('^#') then
	--	local dname = destination:match('^#(.*)$')
	--	for id, c in pairs(self.channels) do
	--		if c.name == dname then
	--			destination = id
	--			break
	--		end
	--	end
	--end

	local to, topic = destination:match('^#(.+):(.+)$')

	local auth = base64.encode(
		string.format('%s:%s', self.email, self.token)
	)
	local payload = string.format([[type=%s&to=%s&topic=%s&content=%s]],
		msg_type,
		urlEncode(to),
		urlEncode(topic),
		urlEncode(util.stripformatting(message))
	)

	local data = http(
		{
			url = string.format('https://%s/api/v1/messages?%s', self.server, payload),
			method = 'POST',
			headers = {
				['Content-Type'] = 'application/x-www-form-urlencoded',
				['Authorization'] = string.format('Basic %s', auth)
			},
			data=payload
		}
	)
	self:Log('info', '%s <%s> %s', destination, 'ivar2', message)
	print(data)
	-- TODO: error handling
end

local safeFormat = function(format, ...)
	if(select('#', ...) > 0) then
		local success, message = pcall(string.format, format, ...)
		if(success) then
			return message
		end
	else
		return format
	end
end

function zulip:Log(level, ...)
	local message = safeFormat(...)
	if(message) then
		message = 'zulip> ' .. message
		log[level](log, message)
	end
end

function zulip:RegisterHandler(event_type, fn, id)
	if not self.handlers[event_type] then
		self.handlers[event_type] = {}
	end
	id = id or 'random' -- XXX
	self.handlers[event_type][id] = fn
end

function zulip:UnRegisterHandler(event_type, fn)
	--TODO
end

--[[
Usage

local handleMessage = function(m)
	local channel = zulip:get_channel(m.channel)
	if not channel then
		channel = 'DM'
	else
		channel = '#'..channel
	end
	local user = zulip:get_user(m.user)
	local message = m.text
	print(channel..' <'..user..'>'.. ' '..message)
	if message == 'k' then
		zulip:Privmsg(m.channel, 'okay')
	end
end

--zulip:RegisterHandler('message', handleMessage, 'testid')
--]]

return zulip
