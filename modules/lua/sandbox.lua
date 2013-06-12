-- https://github.com/jnwhiteh/luasandbox
-- License: MIT

-- This script accepts a single argument, being the filename of a script
-- to be run.  It expects to be executed under the ulimit command of the
-- bash shell.  It provides a very simple sandbox that doesn't have any
-- persistent state.  This is intentional.

local optrequire = function(...)
	local success, lib = pcall(require, ...)
	if(success) then return lib end
end

-- Grab the filename from the genv, so we have it available
local filename = arg[1]
local session = arg[2]
local luarocks = optrequire("luarocks.require")
local pluto = optrequire("pluto")

-- Save what we need to have access to in order to run
local genv = getfenv(0)
local os = {
	date = genv.os.date,
	time = genv.os.time,
	difftime = genv.os.difftime,
	clock = genv.os.clock,
}
local os_exit = genv.os.exit
local string = genv.string
local table = genv.table
local type = genv.type
local print = genv.print
local floor = genv.math.floor
local loadstring = genv.loadstring
local getmetatable = genv.getmetatable
local setmetatable = genv.setmetatable
local pcall = genv.pcall
local tostring = genv.tostring
local pairs = genv.pairs
local error = genv.error
local stdout = genv.io.stdout
local open = genv.io.open
local select = genv.select
local rawset = genv.rawset
local xpcall = genv.xpcall
local traceback = genv.debug.traceback

-- Make a copy of the true global environment
local penv = {}
for k,v in pairs(genv) do penv[k] = v end
setmetatable(penv, getmetatable(genv))

-- Clear the true global environment so we can build it from scratch
for k,v in pairs(genv) do genv[k] = nil end
local genv_mt = {__metatable = {}}
setmetatable(genv, genv_mt)

-- This function allows you to expose global variables, as well as namespace functions
-- i.e. it accepts keys such as "tostring", as well as "string.format".

local function expose(tbl)
	for idx,key in pairs(tbl) do
		if type(key) ~= "string" then
			error("Attempt to expose a non-string key: " .. tostring(key))
		end

		-- If the key matches directly then copy it
		if penv[key] then
			genv[key] = penv[key]
			-- TODO: Error if the key isn't there
		else
			local namespace,subkey = key:match("^([^%.]+)%.(.+)$")
			local nsTbl = penv[namespace]
			if type(nsTbl) == "table" and type(nsTbl[subkey]) ~= "nil" then
				genv[namespace] = genv[namespace] or {}
				genv[namespace][subkey] = penv[namespace][subkey]
			else
				error("Attempt to expose a non-existant namespace value: " .. tostring(key))
			end
		end
	end
end

expose{
	"assert",
	"collectgarbage",		-- Should be safe in our throwaway environment, due to ulimit
	"error",
	"getfenv",				-- We should be fine with this, since they can't outside of it
	"getmetatable",
	"ipairs",
	--"load",               -- Corsix broke this one
	--"loadstring",         -- Corsix broke this one
	"next",
	"pairs",
	"pcall",
	"print",				-- Expose this as a backup, but we redefine it below
	"rawequal",
	"rawget",
	"rawset",
	"select",
	"setfenv",
	"setmetatable",
	"tonumber",
	"tostring",				-- This is REQUIRED for print to work properly
	"type",
	"unpack",
	"_VERSION",
	"xpcall",
	"os.clock",
	"os.date",
	"os.difftime",
	"os.time",
}

-- Export the strings,math and table libraries
local libs = {}
for k,v in pairs(penv.string) do table.insert(libs, "string."..k) end
for k,v in pairs(penv.math) do table.insert(libs, "math."..k) end
for k,v in pairs(penv.table) do table.insert(libs, "table."..k) end
for k,v in pairs(penv.coroutine) do table.insert(libs, "coroutine."..k) end
expose(libs)

genv._G = genv

-- Add the following lua-space split/join/concat/trim functions

local function quotemeta(i)
		return string.gsub(i, "[%%%[%]%*%.%-%?%$%^%(%)]", "%%%1")
end

local function __strsplit(re, str, lim)
	if (lim and lim <= 1) then return str end
	local pre, post = string.match(str, re)
	if (not pre) then
		return str
	end
	if (lim == 2) then
		return pre, post
	end
	return pre, __strsplit(re, post, lim and (lim - 1))
end

function genv.strsplit(del, str, lim)
	if (lim and lim <= 1) then return str end
	return __strsplit("^(.-)[" .. quotemeta(del) .. "](.*)$", str, lim)
end

function genv.strconcat(...)
	return table.concat({...})
end

function genv.strjoin(sep, ...)
	local l = select("#", ...)
	if (l == 0) then
		return
	elseif (l == 1) then
		return (...)
	end

	local t = {(...)}
	for i=2,l do
		table.insert(t, sep)
		table.insert(t, (select(i, ...)))
	end
	return table.concat(t)
end

function genv.strtrim(str)
		return str:match("%s*(.*)%s*")
end

genv.string.concat = genv.strconcat
genv.string.join = genv.strjoin
genv.string.split = genv.strsplit
genv.string.trim = genv.strtrim

-- Let's properly sandbox the string metatable
getmetatable("").__metatable = {}

-- Utility functions that let us capture and release output
local hijacknil = setmetatable({}, {__tostring=function() return "nil" end})
local function capture(...)
	local tbl = {}
	for i=1,select("#", ...) do
		local item = select(i, ...)
		if type(item) == nil then
			tbl[i] = hijacknil
		else
			tbl[i] = item
		end
	end

	return tbl
end

local function release(tbl, s)
	s = s or 1

	if s > #tbl then
		return
	end

	local item = tbl[s]
	if item == hijacknil then
		return nil, release(tbl, s + 1)
	else
		return item, release(tbl, s + 1)
	end
end

local no_persist = {}
local c = 1
local function flat_nopersist(tbl)
	for k,v in pairs(tbl) do
		if type(v) == "string" or type(v) == "number" then
			--do nothing
		elseif type(v) == "table" and not no_persist[v] then
			no_persist[v] = 0
			flat_nopersist(v)
		else
			no_persist[v] = c
			c = c + 1
		end
	end
end

flat_nopersist(penv)
flat_nopersist(genv)

local function main()
	-- Begin compiling and running the script.
	-- Output a marker "RUN:" to show that we've actually began running the script
	stdout:write("RUN:"); stdout:flush();

	local file = open(filename, "r")
	if type(file) ~= "userdata" then
		print("ERR:Unexpected error running sandboxed code: file error")
		os_exit(1)
	end

	local script,err = file:read("*all")
	if type(err) ~= "nil" then
		print("ERR:Unexpected error running sandbox code: read error")
		os_exit(1)
	end

	local func,err = loadstring(script, "=weblua")
	if type(func) ~= "function" then
		-- We officially have nothing to run, bail out with the first error
		print("ERR:" .. tostring(err))
		os_exit(1)
	else
		if(pluto) then
			-- Create a capture table to get any new globals set by the script
			local new_globals = {}
			function genv_mt.__newindex(t,k,v)
				rawset(new_globals, k, v)
				rawset(t, k, v)
			end

			-- Load any persistent state that has been saved
			local file = open("/tmp/webluasession-"..session, "r")
			if file then
				local env = select(2, pcall(pluto.unpersist, no_persist, file:read("*all")))
				if type(env) == "table" then
					for k,v in pairs(env) do
						genv[k] = v
					end
				end
				file:close()
			end
		end

		-- Run this script, and hope it prints something

		local handler = function(msg)
			local stack = traceback()
			stack = stack:gsub("%S+sputnik%-weblua[^\n]+%s+", "")
			stack = stack:gsub("%s+%[C%]: in function 'xpcall'.+$", "")
			return tostring(msg) .. stack
		end

		local results = capture(xpcall(func, handler))
		if results[1] then
			-- pcall ran successfully, output any results

			if(pluto) then
				-- For everything in new_globals, update those values
				for k,v in pairs(new_globals) do
					rawset(new_globals, k, genv[k])
				end

				-- Save the state out to a session file
				local file = open("/tmp/webluasession-"..session, "w+")
				if file then
					local buf = select(2, pcall(pluto.persist, no_persist, new_globals))
					if type(buf) == "string" and #buf < (500 * 1024) then
						file:write(buf)
					end
					file:close()
				end
			end

			stdout:flush()
			print(select(2, release(results)))
			stdout:write(":END")
		else
			print(tostring(results[2]))
			stdout:write(":ERR")
		end
	end
end

return main()

