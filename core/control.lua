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

local function createFifo()
	P.unlink(fileName)
	P.mkfifo(fileName)
	P.chmod(fileName, "0666")
end

local function openFifo()
	return P.open(fileName, P.O_RDONLY + P.O_NONBLOCK)
end

createFifo()
local fifoFd = openFifo()

local controller = cqueues.running()
controller:wrap(function()
	while true do
		cqueues.poll(fifoFd)
		while true do
			local line = P.read(fifoFd, 4096)
			if line == '' then
				break
			end
			for l in line:gmatch('[^\r\n]+') do
				local command, argument = l:match('^(%S+) ?(.*)$')
				if(commands[command]) then
					pcall(commands[command], argument)
				end
			end
		end
		P.close(fifoFd)
		fifoFd = openFifo()
	end
end)

return {
	close = function()
		P.close(fifoFd)
	end
}