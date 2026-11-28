local ivar2 = ...

local P = require'posix'
local cqueues = require'cqueues'


local stripExtension = function(path)
	local i = path:match( ".+()%.%w+$" )
	if ( i ) then return path:sub(1, i-1) end
	return path
end

local fileName = stripExtension(P.basename(ivar2.config.configFile))

local commands = {
	['>'] = function(lua)
		local func = loadstring(lua)
		if(func) then
			local env = {
				ivar2 = ivar2,
			}

			local proxy = setmetatable(env, {__index = _G })
			setfenv(func, proxy)

			pcall(func)
		end
	end,

	quit = function(message)
		ivar2:Quit(message)
	end,

	join = function(argument)
		local chan, pass = argument:match('^(%S+) ?(%S*)')
		if(pass == '') then pass = nil end
		ivar2:Join(chan, pass)
	end,

	part = function(argument)
		ivar2:Part(argument)
	end,

	topic = function(argument)
		local chan, topic = argument:match('^(%S+) (.+)$')
		ivar2:Topic(chan, topic)
	end,

	mode = function(argument)
		local destination, mode = argument:match('^(%S+) (.+)$')
		ivar2:Mode(destination, mode)
	end,

	kick = function(argument)
		local chan, user, comment = argument:match('^(%S+) (%S+) ?(.*)$')
		ivar2:Kick(chan, user, comment)
	end,

	nick = function(nick)
		ivar2:Nick(nick)
	end,

	ignore = function(mask)
		ivar2:Ignore(mask)
	end,

	unignore = function(mask)
		ivar2:Unignore(mask)
	end,

	loadmodule = function(module)
		ivar2:LoadModule(module)
	end,

	disablemodule = function(module)
		ivar2:DisableModule(module)
	end,

	reloadmodule = function(module)
		ivar2:DisableModule(module)
		ivar2:LoadModule(module)
	end,

	reload = function()
		ivar2:Reload()
	end
}

-- Reuse an existing FIFO at this path: a reload re-creates this control object,
-- and unlinking/re-creating the path would orphan the previous reader (it keeps
-- polling an unlinked inode) while new writers talk to a different one.
local function createFifo()
	local st = P.stat(fileName)
	if(st and P.S_ISFIFO(st.mode)) then
		P.chmod(fileName, "0666")
		return
	end
	P.unlink(fileName)
	P.mkfifo(fileName)
	P.chmod(fileName, "0666")
end

-- Open O_RDWR. Our own read end keeps the writer count above zero, so the read
-- side never sees EOF when the last writer closes and never has to be closed
-- and reopened. The old close/reopen cycle dropped whatever a writer had pushed
-- between P.close and openFifo, and blocked writers that opened the FIFO during
-- that window, so `echo cmd > fifo` could silently no-op.
local function openFifo()
	return P.open(fileName, P.O_RDONLY + P.O_RDWR + P.O_NONBLOCK)
end

-- One reader per FIFO. A reload re-creates this control object in the same
-- process, so retire the previous reader for this path before starting a new
-- one: two readers on the same FIFO split each other's commands, and before the
-- path was reused the old coroutine just leaked, polling an unlinked inode.
local readers = rawget(_G, '__ivar2_fifo_readers')
if(not readers) then
	readers = {}
	rawset(_G, '__ivar2_fifo_readers', readers)
end
if(readers[fileName]) then
	pcall(readers[fileName])
end

local alive = true
createFifo()
local fifoFd = openFifo()

-- A command longer than one read is kept in the buffer until its newline
-- arrives, instead of having its fragments parsed as separate commands.
local buffer = ''
local MAX_BUFFER = 1024 * 1024

local function dispatchLine(line)
	local command, argument = line:match('^(%S+) ?(.*)$')
	local handler = command and commands[command]
	if(not handler) then return end
	local ok, err = pcall(handler, argument)
	if(not ok) then
		ivar2:Log('error', 'Control command %s failed: %s', command, tostring(err))
	end
end

-- Read everything currently available. Returns how many bytes were read.
local function drain()
	local total = 0
	while true do
		local chunk = P.read(fifoFd, 4096)
		-- nil: EAGAIN (nothing more right now). #chunk == 0: EOF/short read.
		if(chunk == nil or #chunk == 0) then
			return total
		end
		total = total + #chunk
		buffer = buffer .. chunk
		while true do
			local nl = buffer:find('[\r\n]')
			if(not nl) then break end
			local line = buffer:sub(1, nl - 1)
			buffer = buffer:sub(nl + 1)
			if(#line > 0) then
				dispatchLine(line)
			end
		end
		if(#buffer > MAX_BUFFER) then
			ivar2:Log('error', 'Control FIFO overflow, dropping %d bytes.', #buffer)
			buffer = ''
		end
	end
end

local coro_exited = false
local controller = cqueues.running()
controller:wrap(function()
	local failures = 0
	while alive do
		-- A poll or read error must never take the FIFO reader down for the
		-- rest of the process' lifetime, or remote control stays dead until
		-- the next restart. Retry, and only give up once the descriptor is
		-- clearly unusable.
		local ok, err = pcall(function()
			while alive do
				-- Timed poll: wakes at least every 0.25s so close() is prompt
				-- and a stuck descriptor can't wedge the reader forever.
				cqueues.poll({ pollfd = fifoFd, events = 'r', timeout = 0.25 })
				if(drain() == 0) then
					-- poll said readable but read took nothing: keep the loop
					-- from spinning hot on a stuck descriptor.
					cqueues.sleep(0.05)
				end
			end
		end)
		if(not ok) then
			if(not alive) then break end
			failures = failures + 1
			ivar2:Log('error', 'Control FIFO loop error (%d): %s', failures, tostring(err))
			if(failures >= 5) then
				ivar2:Log('error', 'Control FIFO reader giving up.')
				break
			end
		end
	end
	-- Close our own fd once the reader is done; close() must not touch it
	-- while the coro is mid-poll.
	if(fifoFd) then
		P.close(fifoFd)
		fifoFd = nil
	end
	coro_exited = true
end)

local control = {
	close = function()
		alive = false
		-- Wait until the reader coro actually exits and closes its fd so a
		-- fresh control object on the same path doesn't share the FIFO with
		-- a stale reader for up to one poll cycle.
		while not coro_exited do
			cqueues.sleep(0.01)
		end
	end,
}

readers[fileName] = control.close

return control