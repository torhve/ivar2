package.path = table.concat({
	'libs/?.lua',
	'libs/?/init.lua',

	'',
}, ';') .. package.path

package.cpath = table.concat({
	'libs/?.so',

	'',
}, ';') .. package.cpath

local connection = require'handler.connection'
local uri_mod = require'handler.uri'
local nixio = require'nixio'
local ev = require'ev'
local event = require 'event'
require'logging.console'

local log = logging.console()
local loop = ev.Loop.default

local ivar2 = {
	ignores = {},
	Loop = loop,
	event = event,
	channels = {},

	timeoutFunc = function(ivar2)
		return function(loop, timer, revents)
			ivar2:Log('error', 'Socket stalled for 6 minutes.')
			if(ivar2.config.autoReconnect) then
				ivar2:Reconnect()
			end
		end
	end,
}

local events = {
	['PING'] = {
		core = {
			function(self, source, destination, time)
				self:Send(string.format('PONG %s', time))
			end,
		},
	},

	['JOIN'] = {
		core = {
			function(self, source, chan)
				if(not self.channels[chan]) then
					self.channels[chan] = {
						nicks = {},
						modes = {},
					}
				end

				if(source.nick == self.config.nick) then
					self:Mode(chan, '')
				end

				self.channels[chan].nicks[source.nick] = {
					modes = {},
				}
			end,
		},
	},

	['PART'] = {
		core = {
			function(self, source, chan)
				self.channels[chan].nicks[source.nick] = nil
			end,
		},
	},

	['KICK'] = {
		core = {
			function(self, source, chan, nick)
				self.channels[chan].nicks[nick] = nil
			end,
		},
	},

	['NICK'] = {
		core = {
			function(self, source, nick)
				for channel, data in pairs(self.channels) do
					data.nicks[nick] = data.nicks[source.nick]
					data.nicks[source.nick] = nil
				end
			end,
		},
	},

	['MODE'] = {
		core = {
			function(self, source, channel, modeLine)
				if(channel == self.config.nick) then return end

				local dir, mode, nick = modeLine:match('([+%-])([^ ]+) ?(.*)$')
				local modes

				if(self.channels[channel].nicks[nick]) then
					modes = self.channels[channel].nicks[nick].modes
				elseif(nick == '') then
					modes = self.channels[channel].modes
				end

				if(not modes) then
					return
				end

				if(dir == '+') then
					for m in mode:gmatch('[a-zA-Z]') do
						table.insert(modes, m)
					end
				elseif(dir == '-') then
					for m in mode:gmatch('[a-zA-Z]') do
						for i=1, #modes do
							if(modes[i] == m) then
								table.remove(modes, i)
								break
							end
						end
					end
				end
			end,
		},
	},

	['005'] = {
		core = {
			function(self, source, param, _)
				local network = param:match("NETWORK=([^ ]+)")
				if(network) then
					self.network = network
				end
			end,
		},
	},

	['324'] = {
		core = {
			function(self, source, _, argument)
				local chan, dir, modes = argument:match('([^ ]+) ([+%-])(.*)$')

				local chanModes = self.channels[chan].modes
				for mode in modes:gmatch('[a-zA-Z]') do
					table.insert(chanModes, mode)
				end
			end,
		},
	},

	['353'] = {
		core = {
			function(self, source, chan, nicks)
				chan = chan:match('[=*@] (.*)$')

				local convert = {
					['+'] = 'v',
					['@'] = 'o',
				}

				if(not self.channels[chan]) then
					self.channels[chan] = {
						nicks = {},
						modes = {},
					}
				end
				for nick in nicks:gmatch("%S+") do
					local prefix = nick:sub(1, 1)
					if(convert[prefix]) then
						nick = nick:sub(2)
					else
						prefix = nil
					end

					self.channels[chan].nicks[nick] = {
						modes = {
							convert[prefix]
						},
					}
				end
			end,
		},
	},

	['433'] = {
		core = {
			function(self)
				local nick = self.config.nick:sub(1,8) .. '_'
				self:Nick(nick)
			end,
		},
	},
}

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

local tableHasValue = function(table, value)
	if(type(table) ~= 'table') then return end

	for _, v in next, table do
		if(v == value) then return true end
	end
end

local client_mt = {
	handle_error = function(self, err)
		self:Log('error', err)
		if(self.config.autoReconnect) then
			self:Log('info', 'Lost connection to server. Reconnecting in 60 seconds.')
			ev.Timer.new(
				function(loop, timer, revents)
					self:Reconnect()
				end,
				60
			):start(loop)
		else
			loop:unloop()
		end
	end,

	handle_connected = function(self)
		if(not self.updated) then
			if self.config.password then
				self:Send(string.format('PASS %s', self.config.password))
			end
			self:Nick(self.config.nick)
			local uri = uri_mod.parse(self.config.uri)
			self:Send(string.format('USER %s %s blah :%s', self.config.ident, uri.host, self.config.realname))
		else
			self.updated = nil
		end
	end,

	handle_data = function(self, data)
		return self:ParseInput(data)
	end,
}
client_mt.__index = client_mt
setmetatable(ivar2, client_mt)

function ivar2:Log(level, ...)
	local message = safeFormat(...)
	if(message) then
		if(level == 'error' and self.nma) then
			self.nma(message)
		end

		log[level](log, message)
	end
end

function ivar2:Send(format, ...)
	local message = safeFormat(format, ...)
	if(message) then
		message = message:gsub('[\r\n]+', '')
		self:Log('debug', message)

		self.socket:send(message .. '\r\n')
	end
end

function ivar2:Quit(message)
	self.config.autoReconnect = nil

	if(message) then
		return self:Send('QUIT :%s', message)
	else
		return self:Send'QUIT'
	end
end

function ivar2:Join(channel, password)
	if(password) then
		return self:Send('JOIN %s %s', channel, password)
	else
		return self:Send('JOIN %s', channel)
	end
end

function ivar2:Part(channel)
	return self:Send('PART %s', channel)
end

function ivar2:Topic(destination, topic)
	if(topic) then
		return self:Send('TOPIC %s :%s', destination, topic)
	else
		return self:Send('TOPIC %s', destination)
	end
end

function ivar2:Mode(destination, mode)
	return self:Send('MODE %s %s', destination, mode)
end

function ivar2:Kick(destination, user, comment)
	if(comment) then
		return self:Send('KICK %s %s :%s', destination, user, comment)
	else
		return self:Send('KICK %s %s', destination, user)
	end
end

function ivar2:Notice(destination, format, ...)
	return self:Send('NOTICE %s :%s', destination, safeFormat(format, ...))
end

function ivar2:Privmsg(destination, format, ...)
	return self:Send('PRIVMSG %s :%s', destination, safeFormat(format, ...))
end

function ivar2:Msg(type, destination, source, ...)
	local handler = type == 'notice' and 'Notice' or 'Privmsg'
	if(destination == self.config.nick) then
		-- Send the respons as a PM.
		return self[handler](self, source.nick or source, ...)
	else
		-- Send it to the channel.
		return self[handler](self, destination, ...)
	end
end

function ivar2:Nick(nick)
	self.config.nick = nick
	return self:Send('NICK %s', nick)
end

function ivar2:ParseMaskNick(source)
	return source:match'([^!]+)!'
end

function ivar2:ParseMask(mask)
	local source = {}
	source.mask, source.nick, source.ident, source.host = mask, mask:match'([^!]+)!([^@]+)@(.*)'
	return source
end

function ivar2:DispatchCommand(command, argument, source, destination)
	if(not events[command]) then return end

	if(source) then source = self:ParseMask(source) end

	for moduleName, moduleTable in next, events[command] do
		if(not self:IsModuleDisabled(moduleName, destination)) then
			for pattern, callback in next, moduleTable do
				local success, message
				if(type(pattern) == 'number' and not source) then
					success, message = pcall(callback, self, argument)
				elseif(type(pattern) == 'number' and source) then
					success, message = pcall(callback, self, source, destination, argument)
				elseif(argument:match(pattern)) then
					success, message = pcall(callback, self, source, destination, argument:match(pattern))
				end

				if(not success and message) then
					local output = string.format('Unable to execute handler %s from %s: %s', pattern, moduleName, message)
					self:Log('error', output)
				end
			end
		end
	end
end

function ivar2:IsModuleDisabled(moduleName, destination)
	local channel = self.config.channels[destination]

	if(type(channel) == 'table') then
		return tableHasValue(channel.disabledModules, moduleName)
	end
end

function ivar2:Ignore(mask)
	self.ignores[mask] = true
end

function ivar2:Unignore(mask)
	self.ignores[mask] = nil
end

function ivar2:IsIgnored(destination, source)
	if(self.ignores[source]) then return true end

	local channel = self.config.channels[destination]
	local nick = self:ParseMaskNick(source)
	if(type(channel) == 'table') then
		return tableHasValue(channel.ignoredNicks, nick)
	end
end

function ivar2:EnableModule(moduleName, moduleTable)
	self:Log('info', 'Loading module %s.', moduleName)

	for command, handlers in next, moduleTable do
		if(not events[command]) then events[command] = {} end
		events[command][moduleName] = handlers
	end
end

function ivar2:DisableModule(moduleName)
	if(moduleName == 'core') then return end
	for command, modules in next, events do
		if(modules[moduleName]) then
			self:Log('info', 'Disabling module: %s', moduleName)
			modules[moduleName] = nil
			event:ClearModule(moduleName)
		end
	end
end

function ivar2:DisableAllModules()
	for command, modules in next, events do
		for module in next, modules do
			if(module ~= 'core') then
				self:Log('info', 'Disabling module: %s', module)
				modules[module] = nil
			end
		end
	end
end

function ivar2:LoadModule(moduleName)
	local moduleFile, moduleError = loadfile('modules/' .. moduleName .. '.lua')
	if(not moduleFile) then
		moduleFile, moduleError = loadfile('modules/' .. moduleName .. '/init.lua')
	end

	if(not moduleFile) then
		return self:Log('error', 'Unable to load module %s: %s.', moduleName, moduleError)
	end

	local env = {
		ivar2 = self,
		package = package,
	}
	local proxy = setmetatable(env, {__index = _G })
	setfenv(moduleFile, proxy)

	local success, message = pcall(moduleFile, self)
	if(not success) then
		self:Log('error', 'Unable to execute module %s: %s.', moduleName, message)
	else
		self:EnableModule(moduleName, message)
	end
end

function ivar2:LoadModules()
	if(self.config.modules) then
		for _, moduleName in next, self.config.modules do
			self:LoadModule(moduleName)
		end
	end
end

function ivar2:Connect(config)
	self.config = config

	if(not self.control) then
		self.control = assert(loadfile('core/control.lua'))(ivar2)
		self.control:start(loop)
	end

	if(not self.nma) then
		self.nma = assert(loadfile('core/nma.lua'))(ivar2)
	end

	if(self.timeout) then
		self.timeout:stop(loop)
	end

	self.timeout = ev.Timer.new(self.timeoutFunc(self), 60*6, 60*6)
	self.timeout:start(loop)

	local uri = uri_mod.parse(config.uri)
	self:Log('info', 'Connecting to %s:%s.', uri.host, uri.port)
	self.socket = connection.uri(loop, self, config.uri)

	self:DisableAllModules()
	self:LoadModules()
end

function ivar2:Reconnect()
	self:Log('info', 'Reconnecting to servers.')

	-- Doesn't exsist if connection.tcp() in :Connect() fails.
	if(self.socket) then
		self.socket:close()
	end

	self:Connect(self.config)
end

function ivar2:Reload()
	local coreFunc, coreError = loadfile('ivar2.lua')
	if(not coreFunc) then
		return self:Log('error', 'Unable to reload core: %s.', coreError)
	end

	local success, message = pcall(coreFunc)
	if(not success) then
		return self:Log('error', 'Unable to execute new core: %s.', message)
	else
		self.control:stop(self.Loop)
		self.timeout:stop(self.Loop)

		message.socket = self.socket
		message.config = self.config
		message.timers = self.timers
		message.Loop = self.Loop
		message.channels = self.channels
		message.event = self.event
		message.network = self.network
		-- Clear the registered events
		message.event:ClearAll()

		message:LoadModules()
		message.updated = true
		self.socket:sethandler(message)

		self = message

		self.nma = assert(loadfile('core/nma.lua'))(self)
		self.control = assert(loadfile('core/control.lua'))(self)
		self.control:start(loop)

		self.timeout = ev.Timer.new(self.timeoutFunc(self), 60*6, 60*6)
		self.timeout:start(loop)

		self:Log('info', 'Successfully update core.')
	end
end

function ivar2:ParseInput(data)
	self.timeout:again(loop)

	if(self.overflow) then
		data = self.overflow .. data
		self.overflow = nil
	end

	for line in data:gmatch('[^\n]+') do
		if(line:sub(-1) ~= '\r') then
			self.overflow = line
		else
			-- Strip of \r.
			line = line:sub(1, -2)
			self:Log('debug', line)

			local source, command, destination, argument
			if(line:sub(1, 1) ~= ':') then
				command, argument = line:match'^(%S+) :(.*)'
				if(command) then
					self:DispatchCommand(command, argument, 'server')
				end
			elseif(line:sub(1, 1) == ':') then
				if(not source) then
					-- :<server> 000 <nick> <destination> :<argument>
					source, command, destination, argument = line:match('^:(%S+) (%d%d%d) %S+ ([^%d]+[^:]+) :(.*)')
				end
				if(not source) then
					-- :<server> 000 <nick> <int> :<argument>
					source, command, argument = line:match('^:(%S+) (%d%d%d) [^:]+ (%d+ :.+)')
					if(source) then argument = argument:gsub(':', '', 1) end
				end
				if(not source) then
					-- :<server> 000 <nick> <argument> :<argument>
					source, command, argument = line:match('^:(%S+) (%d%d%d) %S+ (.+) :.+$')
				end
				if(not source) then
					-- :<server> 000 <nick> :<argument>
					source, command, argument = line:match('^:(%S+) (%d%d%d) [^:]+ :(.*)')
				end
				if(not source) then
					-- :<server> 000 <nick> <argument>
					source, command, argument = line:match('^:(%S+) (%d%d%d) %S+ (.*)')
				end
				if(not source) then
					-- :<server> <command> <destination> :<argument>
					source, command, destination, argument = line:match('^:(%S+) (%u+) ([^:]+) :(.*)')
				end
				if(not source) then
					-- :<source> <command> <destination> <argument>
					source, command, destination, argument = line:match('^:(%S+) (%u+) (%S+) (.*)')
				end
				if(not source) then
					-- :<source> <command> :<destination>
					source, command, destination = line:match('^:(%S+) (%u+) :(.*)')
				end
				if(not source) then
					-- :<source> <command> <destination>
					source, command, destination = line:match('^:(%S+) (%u+) (.*)')
				end

				if(not self:IsIgnored(destination, source)) then
					self:DispatchCommand(command, argument, source, destination)
				end
			end
		end
	end
end

-- Attempt to create the cache folder.
nixio.fs.mkdir('cache')

return ivar2
