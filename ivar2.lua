-- vim: set noexpandtab:
package.path = table.concat({
	'libs/?.lua',
	'libs/?/init.lua',

	'',
}, ';') .. package.path

package.cpath = table.concat({
	'libs/?.so',

	'',
}, ';') .. package.cpath

local configFile, reload = ...

-- Check if we have moonscript available
local moonstatus, moonscript = pcall(require, 'moonscript')
moonscript = moonstatus and moonscript

local connection = require'handler.connection'
local nixio = require'nixio'
local ev = require'ev'
local event = require 'event'
local util = require 'util'
local irc = require 'irc'
local lconsole = require'logging.console'

local log = lconsole()

local ivar2 = {
	ignores = {},
	Loop = ev.Loop.default,
	event = event,
	channels = {},
	more = {},
	timers = {},
	util = util,

	timeoutFunc = function(ivar2)
		return function(loop, timer, revents)
			ivar2:Log('error', 'Socket stalled for 6 minutes.')
			if(ivar2.config.autoReconnect) then
				ivar2:Reconnect()
			end
		end
	end,
}

local matchFirst = function(pattern, ...)
	for i=1, select('#', ...) do
		local arg = select(i, ...)
		if(arg) then
			local match = arg:match(pattern)
			if(match) then return match end
		end
	end
end

local events = {
	['PING'] = {
		core = {
			function(self, source, destination, server)
				self:Send('PONG %s', server)
			end,
		},
	},

	['JOIN'] = {
		core = {
			function(self, source, chan)
				chan = chan:lower()

				if(not self.channels[chan]) then
					self.channels[chan] = {
						nicks = {},
						modes = {},
					}
				end

				if(source.nick == self.config.nick) then
					self:Mode(chan, '')
					-- Servers sends us our hostmask on joins, use that to set it
					self.hostmask = source.mask
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
				chan = chan:lower()

				if(source.nick == self.config.nick) then
					self.channels[chan] = nil
				else
					self.channels[chan].nicks[source.nick] = nil
				end
			end,
		},
	},

	['KICK'] = {
		core = {
			function(self, source, destination, message)
				local chan, nick = destination:match("^(%S+) (%S+)$")
				chan = chan:lower()

				if(nick == self.config.nick) then
					self.channels[chan] = nil
				else
					self.channels[chan].nicks[nick] = nil
				end
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

				channel = channel:lower()
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
			-- XXX: We should probably parse out everything and move it to
			-- self.server or something.
			function(self, source, param, param2)
				local network = matchFirst("NETWORK=(%S+)", param, param2)
				if(network) then
					self.network = network
				end

				local maxNickLength = matchFirst("MAXNICKLEN=(%d+)", param, param2)
				if(maxNickLength) then
					self.maxNickLength = maxNickLength
				end
			end,
		},
	},

	['324'] = {
		core = {
			function(self, source, _, argument)
				local chan, dir, modes = argument:match('([^ ]+) ([+%-])(.*)$')

				chan = chan:lower()
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
				chan = chan:lower()

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

	['437'] = {
		core = {
			function(self, source, chan, argument)
				chan = chan:lower()

				local password
				for channel, data in next, self.config.channels do
					if(channel == chan) then
						if(type(data) == 'table' and data.password) then
							password = data.password
						end

						break
					end
				end

				self:Timer('_join', 30, function(loop, timer, revents)
					self:Join(chan, password)
				end)
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
			self:Timer('_reconnect', 60, function(loop, timer, revents)
				self:Reconnect()
			end)
		else
			self.Loop:unloop()
		end
	end,

	handle_connected = function(self)
		if(not self.updated) then
			if self.config.password then
				self:Send('PASS %s', self.config.password)
			end
			self:Nick(self.config.nick)
			self:Send('USER %s 0 * :%s', self.config.ident, self.config.realname)
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
		log[level](log, message)
	end
end

function ivar2:Send(format, ...)
	local message = safeFormat(format, ...)
	if(message) then
		message = message:gsub('[\r\n]+', ' ')

		self:Log('debug', message)

		self.timeout:again(self.Loop)
		self.socket:send(message .. '\r\n')
	end
end

function ivar2:Quit(message)
	self.config.autoReconnect = nil
	self:SimpleDispatch('QUIT_OUT', message)

	if(message) then
		return self:Send('QUIT :%s', message)
	else
		return self:Send'QUIT'
	end
end

function ivar2:Join(channel, password)
	self:SimpleDispatch('JOIN_OUT', channel)
	if(password) then
		return self:Send('JOIN %s %s', channel, password)
	else
		return self:Send('JOIN %s', channel)
	end
end

function ivar2:Part(channel)
	self:SimpleDispatch('PART_OUT', channel)
	return self:Send('PART %s', channel)
end

function ivar2:Topic(destination, topic)
	self:SimpleDispatch('TOPIC_OUT', topic, {source=self.config.nick}, destination)
	if(topic) then
		return self:Send('TOPIC %s :%s', destination, topic)
	else
		return self:Send('TOPIC %s', destination)
	end
end

function ivar2:Mode(destination, mode)
	self:SimpleDispatch('MODE_OUT', mode, {source=self.config.nick}, destination)
	return self:Send('MODE %s %s', destination, mode)
end

function ivar2:Kick(destination, user, comment)
	self:SimpleDispatch('KICK_OUT', user, {source=self.config.nick}, destination)
	if(comment) then
		return self:Send('KICK %s %s :%s', destination, user, comment)
	else
		return self:Send('KICK %s %s', destination, user)
	end
end

function ivar2:Notice(destination, format, ...)
	local arg = safeFormat(format, ...)
	self:SimpleDispatch('NOTICE_OUT', arg, {nick=self.config.nick}, destination)
	return self:Send('NOTICE %s :%s', destination, arg)
end

function ivar2:Privmsg(destination, format, ...)
	local message, extra = irc.split(ivar2.hostmask, destination, safeFormat(format, ...), ivar2.config.splitMarker)
	-- Save the potential extra stuff from the split into the more container
	ivar2.more[destination] = extra
	-- Check if bot should use NOTICE instead of PRIVMSG
	local channel = self.config.channels[destination]
	if self.config.notice or (type(channel) == "table" and channel.notice) then
		return self:Notice(destination, message)
	end
	self:SimpleDispatch('PRIVMSG_OUT', message, {nick=self.config.nick}, destination)
	return self:Send('PRIVMSG %s :%s', destination, message)
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

function ivar2:Say(destination, source, ...)
	return self:Msg('privmsg', destination, source, ...)
end

function ivar2:Reply(destination, source, format, ...)
	return self:Msg('privmsg', destination, source, source.nick..': '..format, ...)
end

function ivar2:Nick(nick)
	self.config.nick = nick
	self:SimpleDispatch('NICK_OUT', {nick=self.config.nick})
	return self:Send('NICK %s', nick)
end

function ivar2:ParseMaskNick(source)
	return source:match'([^!]+)!'
end

function ivar2:ParseMask(mask)
	if type(mask) == 'table' then return mask end
	local source = {}
	source.mask, source.nick, source.ident, source.host = mask, mask:match'([^!]+)!([^@]+)@(.*)'
	return source
end

function ivar2:LimitOutput(destination, output, sep, padding)
	-- 512 - <nick> - ":" - "!" - 63 (max host size, rfc) - " " - destination
	local limit = 512 - #self.config.nick - 1 - 1 - 63 - 1 - #destination - (padding or 0)
	sep = sep or 2

	local out = {}
	for i=1, #output do
		local entry = output[i]
		limit = limit - #entry - sep
		if(limit > 0) then
			table.insert(out, entry)
		else
			break
		end
	end

	return out, limit
end

function ivar2:SimpleDispatch(command, argument, source, destination)
	-- Function that dispatches commands in the events table without
	-- splitting arguments and setting up function environment
	if(not events[command]) then return end

	if(source) then source = self:ParseMask(source) end

	for moduleName, moduleTable in next, events[command] do
		if(not self:IsModuleDisabled(moduleName, destination)) then
			for pattern, callback in next, moduleTable do
				local success, message
				if(type(pattern) == 'number' and source) then
					success, message = pcall(callback, self, source, destination, argument)
				else
					local channelPattern = self:ChannelCommandPattern(pattern, moduleName, destination)
					if(argument:match(channelPattern)) then
						success, message = pcall(callback, self, source, destination, argument)
					end
				end
				if(not success and message) then
					self:Log('error', 'Unable to execute handler %s from %s: %s', pattern, moduleName, message)
				end
			end
		end
	end
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
					success, message = self:ModuleCall(callback, source, destination, false, argument)
				else
					local channelPattern = self:ChannelCommandPattern(pattern, moduleName, destination)
					-- Check command for filters, aka | operator
					-- Ex: !joke|!translate en no|!gay
					local cutarg, remainder = self:CommandSplitter(argument)

					if(cutarg:match(channelPattern)) then
						if(remainder) then
							self:Log('debug', 'Splitting command: %s into %s and %s', command, cutarg, remainder)
						end

						success, message = self:ModuleCall(callback, source, destination, remainder, cutarg:match(channelPattern))
					end
				end

				if(not success and message) then
					self:Log('error', 'Unable to execute handler %s from %s: %s', pattern, moduleName, message)
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

function ivar2:ChannelCommandPattern(pattern, moduleName, destination)
	if not destination then
		return pattern
	end
	local default = '%%p'
	-- First check for a global pattern
	local npattern = self.config.commandPattern or default
	-- If a channel specific pattern exist, use it instead of the default ^%p
	-- Need to lowercase both in case of inconsistancies between server and client
	local channel = self.config.channels[destination:lower()]

	if(type(channel) == 'table') then
		npattern = channel.commandPattern or npattern

		-- Check for module override
		if(type(channel.modulePatterns) == 'table') then
			npattern = channel.modulePatterns[moduleName] or npattern
		end
	end

	return (pattern:gsub('%^%%p', '%^'..npattern))
end

function ivar2:Ignore(mask)
	self.ignores[mask] = true
end

function ivar2:Unignore(mask)
	self.ignores[mask] = nil
end

function ivar2:IsIgnored(destination, source)
	if(not destination) then return false end
	if(not source) then return false end
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
	local moduleFile
	local moduleError
	local endings = {'.lua', '/init.lua', '.moon', '/init.moon'}

	for _,ending in pairs(endings) do
		local fileName = 'modules/' .. moduleName .. ending
		-- Check if file exist and is readable before we try to loadfile it
		local access, errCode, accessError = nixio.fs.access(fileName, 'r')
		if(access) then
			if(fileName:match('.lua')) then
				moduleFile, moduleError = loadfile(fileName)
			elseif(fileName:match('.moon') and moonscript) then
				moduleFile, moduleError = moonscript.loadfile(fileName)
			end
			if(not moduleFile) then
				-- If multiple file matches exist and the first match has an error we still
				-- return here.
				return self:Log('error', 'Unable to load module %s: %s.', moduleName, moduleError)
			end
		end
	end
	if(not moduleFile) then
		moduleError = 'File not found'
		return self:Log('error', 'Unable to load module %s: %s.', moduleName, moduleError)
	end

	local env = {
		ivar2 = self,
		package = package,
	}
	setmetatable(env, {__index = _G })
	setfenv(moduleFile, env)

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

function ivar2:CommandSplitter(command)
	local first, remainder

	local pipeStart, pipeEnd = command:match('()%s*|%s*()')
	if(pipeStart and pipeEnd) then
		first = command:sub(0,pipeStart-1)
		remainder = command:sub(pipeEnd)
	else
		first = command
	end

	return first, remainder
end

function ivar2:ModuleCall(func, source, destination, remainder, ...)
	-- Construct a environment for each callback that provide some helper
	-- functions and utilities for the modules
	local env = getfenv(func)
	env.say = function(str, ...)
		local output = safeFormat(str, ...)
		if(not remainder) then
			self:Say(destination, source, output)
		else
			local command
			command, remainder = self:CommandSplitter(remainder)
			local newline = command .. " " .. output
			if(remainder) then
				newline = newline .. "|" .. remainder
			end

			-- TODO: Check that it's actually a privmsg
			self:DispatchCommand('PRIVMSG', newline, source, destination)
		end
	end
	env.reply = function(str, ...)
		self:Reply(destination, source, str, ...)
	end

	return pcall(func, self, source, destination, ...)
end

function ivar2:Events()
	return events
end

-- Let modules register commands
function ivar2:RegisterCommand(handlerName, pattern, handler, event)
	-- Default event is PRIVMSG
	if(not event) then
		event = 'PRIVMSG'
	end
	local env = {
		ivar2 = self,
		package = package,
	}
	setmetatable(env, {__index = _G })
	setfenv(handler, env)
	self:Log('info', 'Registering new pattern: %s, in command %s.', pattern, handlerName)

	if(not events[event][handlerName]) then
		events[event][handlerName] = {}
	end
	events[event][handlerName][pattern] = handler
end

function ivar2:UnregisterCommand(handlerName, pattern, event)
	-- Default event is PRIVMSG
	if(not event) then
		event = 'PRIVMSG'
	end
	events[event][handlerName][pattern] = nil
	self:Log('info', 'Clearing command with pattern: %s, in module %s.', pattern, handlerName)
end

function ivar2:Timer(id, interval, repeat_interval, callback)
	-- Check if invoked with repeat interval or not
	if not callback then
		callback = repeat_interval
		repeat_interval = nil
	end
	-- Construct callback
	local callbackHandler = function(cb)
		return function(...)
			local success, message = pcall(cb, ...)
			if(not success) then
				self:Log('error', 'Error during timer callback %s: %s.', id, message)
			end
			-- Delete expired timer
			if(not repeat_interval and self.timers[id]) then
				self.timers[id] = nil
			end
		end
	end
	local timer = ev.Timer.new(callbackHandler(callback), interval, repeat_interval)
	timer:start(self.Loop)
	-- Only allow one timer per id
	-- Cancel any running
	if(self.timers[id]) then
		self.timers[id]:stop(self.Loop)
	end
	self.timers[id] = timer
	return timer
end

function ivar2:Connect(config)
	self.config = config

	if(not self.control) then
		self.control = assert(loadfile('core/control.lua'))(ivar2)
		self.control:start(self.Loop)
	end

	if(not self.x0) then
		self.x0 = assert(loadfile('core/x0.lua'))(ivar2)
	end

	if(not self.webserver) then
		self.webserver = assert(loadfile('core/webserver.lua'))(ivar2)
		self.webserver.start(self.config.webserverhost, self.config.webserverport)
	end

	if(self.timeout) then
		self.timeout:stop(self.Loop)
	end

	self.timeout = self:Timer('_timeout', 60*6, 60*6, self.timeoutFunc(self))

	self:Log('info', 'Connecting to %s.', self.config.uri)
	self.socket = assert(connection.uri(self.Loop, self, self.config.uri))

	if(not self.persist) then
		-- Load persist library using config
		self.persist = require(config.persistbackend or 'sqlpersist')({
			path = config.kvsqlpath or 'cache/keyvaluestore.sqlite3',
			verbose = false,
			namespace = 'ivar2',
			clear = false
		})
	end
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

	local success, message = pcall(coreFunc, configFile, 'reload')
	if(not success) then
		return self:Log('error', 'Unable to execute new core: %s.', message)
	else
		self.control:stop(self.Loop)
		self.timeout:stop(self.Loop)
		self.webserver:stop()

		message.socket = self.socket
		-- reload configuration file
		local config, err = loadfile(configFile)
		if(not config) then
			self:Log('error', 'Unable to reload config file: %s.', err)
			message.config = self.config
		else
			local success, mess = pcall(config)
			if(not success) then
				self:Log('error', 'Unable to execute new config file: %s.', mess)
			else
				message.config = mess
			end
		end

		-- Store the config file name in the config so it can be accessed later
		message.config.configFile = configFile
		message.timers = self.timers
		message.Loop = self.Loop
		message.channels = self.channels
		message.event = self.event
		-- Reload utils
		package.loaded.util = nil
		package.loaded.simplehttp = nil
		message.util = require'util'
		-- Reload irclib
		package.loaded.irc = nil
		irc = require'irc'
		-- Reload webserver
		message.webserver = assert(loadfile('core/webserver.lua'))(message)
		message.webserver.start(message.config.webserverhost, message.config.webserverport)
		-- Reload persist
		package.loaded[message.config.persistbackend or 'sqlpersist'] = nil
		message.persist = require(message.config.persistbackend or 'sqlpersist')({
				path = message.config.kvsqlpath or 'cache/keyvaluestore.sqlite3',
				verbose = false,
				namespace = 'ivar2',
				clear = false
		})

		message.network = self.network
		message.hostmask = self.hostmask
		message.maxNickLength = self.maxNickLength
		-- Clear the registered events
		message.event:ClearAll()

		message:LoadModules()
		message.updated = true

		self = message
		self.timeout = self:Timer('_timeout', 60*6, 60*6, self.timeoutFunc(self))
		self.socket:sethandler(message)

		self.x0 = assert(loadfile('core/x0.lua'))(self)
		self.control = assert(loadfile('core/control.lua'))(self)
		self.control:start(self.Loop)


		self:Log('info', 'Successfully update core.')
	end
end

function ivar2:ParseInput(data)
	self.timeout:again(self.Loop)

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
			local command, argument, source, destination = irc.parse(line)
			if(not self:IsIgnored(destination, source)) then
				self:DispatchCommand(command, argument, source, destination)
			end

		end
	end
end

if(reload) then
	return ivar2
end

-- Attempt to create the cache folder.
nixio.fs.mkdir('cache')
local config = assert(loadfile(configFile))()
-- Store the config file name in the config so it can be accessed later
config.configFile = configFile
ivar2:Connect(config)
ivar2.Loop:loop()
