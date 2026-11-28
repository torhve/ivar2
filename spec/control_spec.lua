-- Tests for the FIFO remote control loop (core/control.lua).
--
-- Regression coverage for two bugs:
--   * The reader closed and reopened the FIFO on every EOF. Anything written in
--     that window was lost, so `echo cmd > fifo` silently did nothing, and a
--     writer could block on open while the reader was mid-cycle.
--   * A command longer than one read was parsed as two separate commands, and a
--     poll/read error killed the reader coroutine for the rest of the process'
--     lifetime, leaving the bot unreachable over the FIFO.

package.path = table.concat({
	'libs/?.lua',
	'libs/?/init.lua',
	'spec/?.lua',

	'',
}, ';') .. package.path

local busted = require'busted'
local cqueues = require'cqueues'
local P = require'posix'
local helper = require'module_helper'
local describe = busted.describe
local it = busted.it
local before_each = busted.before_each
local after_each = busted.after_each

local repoDir = P.getcwd()
local controlSource = repoDir .. '/core/control.lua'
local fifoName = 'controltest'
local fifoPath = fifoName

local scratchDir

-- A command executed by the FIFO writes into this table; the FIFO chunk only
-- sees _G through its metatable proxy, so it has to be a real global.
local seen = {}
_G.__control_spec_seen = seen

local function resetSeen()
	seen = {}
	_G.__control_spec_seen = seen
end

local function send(text)
	local fd = assert(P.open(fifoPath, P.O_WRONLY))
	assert(P.write(fd, text))
	P.close(fd)
end

-- Load control.lua inside a cqueues loop, run `body`, then shut the reader
-- down. Returns the log lines the control object produced.
local function withControl(body)
	local logs = {}
	local ivar2 = {
		config = { configFile = fifoName .. '.lua' },
	}
	ivar2.Log = function(self, level, message, ...)
		table.insert(logs, level .. ': ' .. string.format(message, ...))
	end

	local cq = cqueues.new()
	cq:wrap(function()
		local control = assert(loadfile(controlSource))(ivar2)
		body()
		control.close()
	end)
	helper.run_loop(cq, TEST_TIMEOUT)
	return logs
end

describe('core/control.lua fifo', function()
	before_each(function()
		resetSeen()
		scratchDir = os.tmpname()
		P.unlink(scratchDir)
		assert(P.mkdir(scratchDir, 0700))
		assert(P.chdir(scratchDir))
	end)

	after_each(function()
		assert(P.chdir(repoDir))
		P.unlink(scratchDir .. '/' .. fifoName)
		P.rmdir(scratchDir)
	end)

	it('runs each command written in its own open/write/close cycle', function()
		-- The old reader dropped commands written while it was between
		-- P.close() and reopening the FIFO, so a burst of one-command writes
		-- came through incomplete.
		local count = 80
		withControl(function()
			for i = 1, count do
				send('> table.insert(_G.__control_spec_seen, ' .. i .. ')\n')
			end
			cqueues.sleep(0.5)
		end)

		local got = {}
		for _, v in ipairs(seen) do
			got[v] = true
		end
		for i = 1, count do
			assert.is_true(got[i], 'command ' .. i .. ' was never executed')
		end
		assert.are.equal(count, #seen)
	end)

	it('splits several commands from a single write', function()
		withControl(function()
			send('> table.insert(_G.__control_spec_seen, "a")\n'
				.. '> table.insert(_G.__control_spec_seen, "b")\n')
			cqueues.sleep(0.2)
		end)
		assert.are.same({ 'a', 'b' }, seen)
	end)

	it('reassembles a command split across two writes', function()
		withControl(function()
			send('> table.insert(_G.__control_spec_seen, ')
			cqueues.sleep(0.2)
			send('"partial")\n')
			cqueues.sleep(0.2)
		end)
		-- The old reader would have run the first fragment as a command
		-- (loadstring fails, so nothing ran) and the second fragment as a
		-- separate command line.
		assert.are.same({ 'partial' }, seen)
	end)

	it('keeps reading after a command that raises', function()
		withControl(function()
			send('> error("boom from the fifo")\n')
			send('> table.insert(_G.__control_spec_seen, "after")\n')
			cqueues.sleep(0.2)
		end)
		assert.are.same({ 'after' }, seen)
	end)

	it('ignores commands it does not know', function()
		local logs = withControl(function()
			send('bogus_command hello\n')
			send('> table.insert(_G.__control_spec_seen, "ok")\n')
			cqueues.sleep(0.2)
		end)
		assert.are.same({ 'ok' }, seen)
		assert.are.equal(0, #logs)
	end)
end)
