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
local cqueues = require 'cqueues'

-- The module shells out to systemd-notify; never let the real binary run.
local real_execute = os.execute
local commands, execResult

local function newMock()
	local mock = helper.mock_ivar2()

	-- Registry with the same "one timer per id, cancel the old one" behaviour
	-- ivar2:Timer has, so reloads can be checked for duplicates.
	mock.timers = {}
	mock.registrations = 0
	mock.logs = {}

	mock.Log = function(self, level, message)
		table.insert(self.logs, { level = level, message = message })
	end

	mock.Timer = function(self, id, initial, repeat_, cb)
		self.registrations = self.registrations + 1
		local existing = self.timers[id]
		if(existing) then
			existing.cancelled = true
		end
		self.timers[id] = { id = id, initial = initial, repeat_ = repeat_, cb = cb }
		return {
			stop = function() self.timers[id].cancelled = true end,
		}
	end

	return mock
end

local function liveTimers(mock)
	local live, ids = 0, {}
	for id, timer in pairs(mock.timers) do
		table.insert(ids, id)
		if(not timer.cancelled) then
			live = live + 1
		end
	end
	table.sort(ids)
	return live, table.concat(ids, ',')
end

describe('systemd-watchdog', function()
	before_each(function()
		commands = {}
		-- Lua 5.2 shape; Lua 5.1/LuaJIT numeric shape is covered in a later test
		execResult = { ok = true, how = 'exit', code = 0 }
		rawset(os, 'execute', function(cmd)
			table.insert(commands, cmd)
			if(execResult.numeric) then return execResult.numeric end
			return execResult.ok, execResult.how, execResult.code
		end)
	end)

	after_each(function()
		rawset(os, 'execute', real_execute)
	end)

	it('signals readiness once on load', function()
		helper.load_module('systemd-watchdog', newMock())
		assert.are.equal(1, #commands)
		assert.are.equal('systemd-notify --ready', commands[1])
	end)

	it('pets the watchdog from its timer callback', function()
		local mock = newMock()
		helper.load_module('systemd-watchdog', mock)

		local live, ids = liveTimers(mock)
		assert.are.equal(1, live)
		assert.are.equal('systemd-watchdog', ids)

		local timer = mock.timers['systemd-watchdog']
		assert.are.equal(30, timer.initial)
		assert.are.equal(30, timer.repeat_)

		commands = {}
		timer.cb()
		assert.are.equal(1, #commands)
		assert.are.equal('systemd-notify WATCHDOG=1', commands[1])
		assert.are.equal(0, #mock.logs)
	end)

	-- Regression: the module used to start a raw cqueues loop at load time.
	-- ivar2:Connect() reloads every module, so every reconnect stacked another
	-- immortal loop, and each loop forked systemd-notify every 30 seconds.
	it('leaks no coroutines and no timers across reloads', function()
		local cq = cqueues.new()
		local problems

		cq:wrap(function()
			local queue = cqueues.running()
			local threadsBefore = queue:count()
			local mock = newMock()

			for _ = 1, 5 do
				helper.load_module('systemd-watchdog', mock)
			end

			problems = {}
			local threadsAfter = queue:count()
			if(threadsAfter ~= threadsBefore) then
				table.insert(problems, 'coroutines leaked: ' .. threadsBefore .. ' -> ' .. threadsAfter)
			end
			if(mock.registrations ~= 5) then
				table.insert(problems, 'expected 5 timer registrations, got ' .. mock.registrations)
			end
			local live = liveTimers(mock)
			if(live ~= 1) then
				table.insert(problems, 'expected 1 live timer after reloads, got ' .. live)
			end
		end)

		helper.run_loop(cq, 1)
		assert.are.equal(0, #problems, table.concat(problems, '; '))
	end)

	it('logs when systemd-notify fails', function()
		execResult = { ok = false, how = 'exit', code = 127 }
		local mock = newMock()
		helper.load_module('systemd-watchdog', mock)
		assert.are.equal(1, #mock.logs)
		assert.are.equal('error', mock.logs[1].level)
		assert.truthy(mock.logs[1].message:find('systemd-notify', 1, true))
	end)

	it('treats a bare numeric exit code as status (Lua 5.1 shape)', function()
		execResult = { numeric = 0 }
		local mock = newMock()
		helper.load_module('systemd-watchdog', mock)
		assert.are.equal(0, #mock.logs)

		execResult = { numeric = 1 }
		mock = newMock()
		helper.load_module('systemd-watchdog', mock)
		assert.are.equal(1, #mock.logs)
	end)
end)
