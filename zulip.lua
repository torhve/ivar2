
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

local event = require 'event'
local util = require 'util'
local irc = require 'irc'
local lconsole = require'logging.console'
local lfs = require 'lfs'
local cqueues = require'cqueues'
local signal = require'cqueues.signal'
local queue = cqueues.new()
local zulip = require'core/zulip'

math.randomseed(os.time())

local log = lconsole()

local ivar2 = {
	ignores = {},
	events = require'core/ircevents',
	event = event,
	channels = {},
	more = {},
	timers = {},
	config = {},
	cancelled_timers = {},
	util = util,
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

		self:Log('debug', "send FIXME: %s", message)
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
	--local message, extra = irc.split(ivar2.hostmask, destination, safeFormat(format, ...), ivar2.config.splitMarker)
	local message = safeFormat(format, ...)
	-- Save the potential extra stuff from the split into the more container
	--ivar2.more[destination] = extra
	-- Check if bot should use NOTICE instead of PRIVMSG
	local channel = self.config.channels[destination]
	if self.config.notice or (type(channel) == "table" and channel.notice) then
		return self:Notice(destination, message)
	end
	self:SimpleDispatch('PRIVMSG_OUT', message, {nick=self.config.nick}, destination)
	return zulip:Privmsg(destination, message)
end

function ivar2:Action(destination, format, ...)
	local message = safeFormat(format, ...)
	message = irc.formatCtcp(message, 'ACTION')
	return self:Privmsg(destination, message)
end

function ivar2:Msg(type, destination, source, ...)
	local handler = type == 'notice' and 'Notice' or 'Privmsg' or 'Action'
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
	source.mask = mask
	source.nick = mask
	source.ident = mask
	source.host = mask -- TODO team id
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
	if(not self.events[command]) then return end

	if(source) then source = self:ParseMask(source) end

	for moduleName, moduleTable in next, self.events[command] do
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
	if(not self.events[command]) then return end

	if(source) then source = self:ParseMask(source) end

	for moduleName, moduleTable in next, self.events[command] do
		if(not self:IsModuleDisabled(moduleName, destination)) then
			for pattern, callback in next, moduleTable do
				local success, message
				if(type(pattern) == 'number' and not source) then
					success, message = pcall(callback, self, argument)
				elseif(type(pattern) == 'number' and source) then
					success, message = self:ModuleCall(command, callback, source, destination, false, argument)
				else
					local channelPattern = self:ChannelCommandPattern(pattern, moduleName, destination)
					-- Check command for filters, aka | operator
					-- Ex: !joke|!translate en no|!gay
					local cutarg, remainder = self:CommandSplitter(argument)

					if(cutarg:match(channelPattern)) then
						if(remainder) then
							self:Log('debug', 'Splitting command: %s into %s and %s', command, cutarg, remainder)
						end

						success, message = self:ModuleCall(command, callback, source, destination, remainder, cutarg:match(channelPattern))
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

function ivar2:DestinationLocale(destination)
	-- Get configured language for a destination, can be global or channel
	-- specific. Locale string should be a POSIX locale string, e.g.
	-- nn_NO, nb_NO, en_US,

	-- Modules can then opt into looking for this information and use it
	-- however it wants, for example by switching output language in its
	-- functions to another language than default
	--

	local default = 'en_US'
	local channel = self.config.channels[destination]

	if(type(channel) == 'table') then
		local dconf = channel.locale
		if(dconf) then
			return dconf
		end
	end

	local global = self.config.locale
	if(global) then
		return global
	end

	return default

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
	--local nick = self:ParseMaskNick(source)
	local nick = source
	if(type(channel) == 'table') then
		return tableHasValue(channel.ignoredNicks, nick)
	end
end

function ivar2:EnableModule(moduleName, moduleTable)
	self:Log('info', 'Loading module %s.', moduleName)
	-- Some modules don't return handlers, for example webservermodules,
	-- or pure timermodules, etc.
	if type(moduleTable) ~= 'table' then
		return
	end

	for command, handlers in next, moduleTable do
		if(not self.events[command]) then self.events[command] = {} end
		self.events[command][moduleName] = handlers
	end
end

function ivar2:DisableModule(moduleName)
	if(moduleName == 'core') then return end
	for command, modules in next, self.events do
		if(modules[moduleName]) then
			self:Log('info', 'Disabling module: %s', moduleName)
			modules[moduleName] = nil
			event:ClearModule(moduleName)
		end
	end
end

function ivar2:DisableAllModules()
	for command, modules in next, self.events do
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

	for _, ending in ipairs(endings) do
		local fileName = 'modules/' .. moduleName .. ending
		-- Check if file exist and is readable before we try to loadfile it
		local access = lfs.attributes(fileName)
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
			break
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

function ivar2:ModuleCall(command, func, source, destination, remainder, ...)
	-- Construct a environment for each callback that provide some helper
	-- functions and utilities for the modules
	local env = getfenv(func)
	env.say = function(str, ...)
		local output = safeFormat(str, ...)
		if(not remainder) then
			self:Say(destination, source, output)
		else
			local newcommand
			newcommand, remainder = self:CommandSplitter(remainder)
			local newline = newcommand .. " " .. output
			if(remainder) then
				newline = newline .. "|" .. remainder
			end

			self:DispatchCommand(command, newline, source, destination)
		end
	end
	env.reply = function(str, ...)
		self:Reply(destination, source, str, ...)
	end

	return pcall(func, self, source, destination, ...)
end

function ivar2:Events()
	return self.events
end

-- Let modules register commands
function ivar2:RegisterCommand(handlerName, pattern, handler, verb)
	-- Default verb is PRIVMSG
	if(not verb) then
		verb = 'PRIVMSG'
	end
	local env = {
		ivar2 = self,
		package = package,
	}
	setmetatable(env, {__index = _G })
	setfenv(handler, env)
	self:Log('info', 'Registering new pattern: %s, in command %s.', pattern, handlerName)

	if(not self.events[verb][handlerName]) then
		self.events[verb][handlerName] = {}
	end
	self.events[verb][handlerName][pattern] = handler
end

function ivar2:UnregisterCommand(handlerName, pattern, verb)
	-- Default verb is PRIVMSG
	if(not verb) then
		verb = 'PRIVMSG'
	end
	self.events[verb][handlerName][pattern] = nil
	self:Log('info', 'Clearing command with pattern: %s, in module %s.', pattern, handlerName)
end

function ivar2:Timer(id, interval, repeat_interval, callback)
	-- Check if invoked with repeat interval or not
	if not callback then
		callback = repeat_interval
		repeat_interval = nil
	end
	local func = function()
		local success, message = pcall(callback)
		if(not success) then
			self:Log('error', 'Error during timer callback %s: %s.', id, message)
		end
		-- Delete expired timer
		if(not repeat_interval and self.timers[id]) then
			self.timers[id] = nil
		end
	end
	-- Check for existing
	if self.timers[id] then
		-- Only allow one timer per id
		-- Cancel any running
		self:Log('info', 'Cancelling existing timer: %s', id)
		self.timers[id]:stop()
	end
	local is_cancelled = function()
		for i, t in ipairs(self.cancelled_timers) do
			if t.id == id then
				table.remove(self.cancelled_timers, i)
				return true
			end
		end
	end
	local timer = {
		id = id,
		cancelled = false,
		stop = function(timer)
			self.timers[id].cancelled = true
			table.insert(self.cancelled_timers, self.timers[id])
			self.timers[id] = nil
		end,
		run = function()
			cqueues.sleep(interval)
			if is_cancelled() then return end
			func()
			if repeat_interval then
				while true do
					cqueues.sleep(repeat_interval)
					if is_cancelled() then return end
					func()
				end
			end
		end
	}
	local controller = cqueues.running()
	timer.controller = controller:wrap(timer.run)
	self.timers[id] = timer
	return timer
end

function ivar2:Connect(config)
	self.config = config
	if(not self.config.password) then
		self:Log('error', 'No password/token defined in config, aborting.')
		return
	end

	--if(not self.control) then
	--	self.control = assert(loadfile('core/control.lua'))(ivar2)
	--	self.control:start(self.Loop)
	--end

	if(not self.x0) then
		self.x0 = assert(loadfile('core/x0.lua'))(ivar2)
	end

	if(not self.webserver) then
		self.webserver = assert(loadfile('core/webserver.lua'))(self)
		local cqueue = cqueues.running()
		cqueue:wrap(function()
			pcall(function()
				self.webserver.start(self.config.webserverhost, self.config.webserverport, cqueue)
			end)
		end)
	end

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

	queue:wrap(function()
	  local connect, msg = zulip:Connect(config.uri, config.ident, config.password)
		if not connect then
			self:Log('error', 'Error connecting :%s', connect, msg)
		end
	end)

	zulip:RegisterHandler('message', function(m)
		m = m.message
	  local source = m.sender_full_name
	  local destination = m.display_recipient
		if type(destination) == 'table' then -- privmsg
			destination = 'ivar2'
		else
			destination = '#'..destination..':'..m.subject
		end

	  local argument = m.content
	  local command = 'PRIVMSG'
		self:Log('debug', 'PRIVMSG %s <%s> %s', destination, source, argument)

	  if(not self:IsIgnored(destination, source)) then
		  -- Order on wrap execution is undefined,
		  -- so do not rely on messages being processed in order
		  local cqueue = cqueues.running()
		  cqueue:wrap(function()
			  self:DispatchCommand(command, argument, source, destination)
		  end)
	  end
	end, 'ivar2')
	return true
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
		--self.control:stop(self.Loop)
		--self.timeout:stop(self.Loop)
		pcall(function()
			self.webserver.stop()
		end)

		message.socket = self.socket
		-- reload configuration file
		local config, err = loadfile(configFile)
		if(not config) then
			self:Log('error', 'Unable to reload config file: %s.', err)
			message.config = self.config
		else
			local csuccess, mess = pcall(config)
			if(not csuccess) then
				self:Log('error', 'Unable to execute new config file: %s.', mess)
			else
				message.config = mess
			end
		end

		-- Store the config file name in the config so it can be accessed later
		message.config.configFile = configFile
		message.timers = self.timers
		message.cancelled_timers = self.cancelled_timers
		--message.Loop = self.Loop
		message.channels = self.channels
		message.event = self.event
		-- Reload IRC events
		package.loaded.ircevents = nil
		message.events = require'core/ircevents'
		-- Reload utils
		package.loaded.util = nil
		package.loaded.simplehttp = nil
		message.util = require'util'
		-- Reload irclib
		package.loaded.irc = nil
		irc = require'irc'
		-- Reload webserver
		--XXX message.webserver = assert(loadfile('core/webserver.lua'))(message)
		--XXX message.webserver.start(message.config.webserverhost, message.config.webserverport)
		message.webserver = assert(loadfile('core/webserver.lua'))(message)
		local cqueue = cqueues.running()
		cqueue:wrap(function()
			pcall(function()
				message.webserver.start(message.config.webserverhost, message.config.webserverport)
			end)
		end)
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
		self.timeout = self:Timer('_timeout', 60*10, 60*10, self.timeoutFunc(self))

		self.x0 = assert(loadfile('core/x0.lua'))(self)
		--self.control = assert(loadfile('core/control.lua'))(self)
		--self.control:start(self.Loop)

		self:Log('info', 'Successfully update core.')
	end
end

function ivar2:SignalHandle()
	local TERM = signal.SIGTERM
	local INT = signal.SIGINT
	local HUP = signal.SIGHUP

	while true do
		-- NOTE: Delivered signals cannot be caught by Linux signalfd or
		-- Solaris sigtimedwait. Works without blocking on *BSD and OS X.
		signal.block(TERM, INT, HUP)

		local signo = assert(assert(signal.listen(TERM, INT, HUP)):wait())

		if signo == HUP then
			self:Log('info', 'Got SIGHUP, reloading.')
			self:Reload()
		else
			self:Quit('Ouch. Someone handed me the '..signal[signo]..'. RIP!')
			io.stderr:write("exiting on signal ", signal[signo], "\n")
			os.exit(0)
		end
	end
end

if(reload) then
	return ivar2
end

-- Attempt to create the cache folder.
lfs.mkdir('cache')

-- Load config and start the bot
if configFile then
	local ok, config = pcall(loadfile(configFile))
	if not ok then
		io.stderr:write("Unable to load config "..tostring(configFile)..': '..tostring(config)..'\n')
		os.exit(1)
	end
	-- Store the config file name in the config so it can be accessed later
	config.configFile = configFile
	queue:wrap(function()
			if(not ivar2:Connect(config)) then
				os.exit(0)
			end
	end)
	-- Install Linux signal handler
	queue:wrap(function ()
		ivar2:SignalHandle()
	end)
	-- Run the cqueues main loop through a stepping function to catch errors
	while true do
		-- luacheck: ignore obj fd
		local stepok, err, ctx, ecode, thread, obj, fd = queue:step()
		if(not stepok) then
			ivar2:Log('error', 'Error in main loop: %s, %s, %s', err, ctx, ecode)
			ivar2:Log('error', debug.traceback(thread, err))
		end
	end
else
	ivar2:Log('error', 'No config file specified')
end
