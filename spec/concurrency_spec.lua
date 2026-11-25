-- Regression tests for concurrent async dispatch: concurrent invocations of
-- the same handler must not overwrite each other's say routing.
--
-- These tests drive the real ivar2 bot instance through its real dispatch
-- path (DispatchCommand -> ModuleCall -> wrapped coroutine), with Say/Reply
-- overridden to capture output.

package.path = table.concat({
    'libs/?.lua',
    'libs/?/init.lua',

    '',
}, ';') .. package.path

local busted = require'busted'
local cqueues = require'cqueues'
local describe = busted.describe
local it = busted.it

-- These tests rely on C-level cqueues yields (the mechanism simplehttp uses),
-- which only works under LuaJIT. The default busted shim runs under plain
-- Lua 5.1, where the yield crosses the pcall C-call boundary and fails, so
-- the tests are gated. Run with: luajit <busted> spec/concurrency_spec.lua
local is_luajit = type(jit) == 'table'
if not is_luajit then
    print('[concurrency_spec] skipping: requires LuaJIT (C-call yield)')
end

-- Load the real ivar2 instance (reload flag: no side effects)
local ivar2 = assert(loadfile('ivar2.lua'))(nil, 'reload')
ivar2.config.channels = {}

local sayCalls = {}
ivar2.Say = function(self, destination, source, msg)
    table.insert(sayCalls, { destination = destination, source = source, msg = msg })
end

local queue = cqueues.new()

local function dispatch(message, nick, destination)
    queue:wrap(function()
        ivar2:DispatchCommand('PRIVMSG', message, { nick = nick, mask = nick .. '!u@h' }, destination)
    end)
end

if is_luajit then
describe('concurrent async dispatch', function()
    it('routes each concurrent async call to its own destination', function()
        sayCalls = {}

        local handler = function(self, source, destination, arg)
            cqueues.sleep(0.05)
            say('hello ' .. tostring(arg))
        end
        ivar2:EnableModule('concurrency_test', {
            PRIVMSG = {
                ['^%ptest (.*)$'] = handler,
            },
        })

        dispatch('!test alice', 'alice', '#chan-A')
        dispatch('!test bob', 'bob', '#chan-B')

        assert_loop(queue, TEST_TIMEOUT)

        ivar2:DisableModule('concurrency_test')

        assert.are_equal(2, #sayCalls)
        local byMsg = {}
        for _, call in ipairs(sayCalls) do
            byMsg[call.msg] = call.destination
        end
        assert.are_equal('#chan-A', byMsg['hello alice'])
        assert.are_equal('#chan-B', byMsg['hello bob'])
    end)

    it('advances the pipeline remainder on each say in one handler', function()
        sayCalls = {}
        local dispatchArgs = {}
        local origDispatch = ivar2.DispatchCommand
        ivar2.DispatchCommand = function(self, command, argument, source, destination)
            table.insert(dispatchArgs, argument)
            return origDispatch(self, command, argument, source, destination)
        end

        local handler = function(self, source, destination, arg)
            say('out1')
            say('out2')
            say('out3')
        end
        ivar2:EnableModule('pipeline_test', {
            PRIVMSG = {
                ['^%pgout (.*)$'] = handler,
            },
        })

        queue:wrap(function()
            local source = { nick = 'alice', mask = 'alice!u@h' }
            ivar2:DispatchCommand('PRIVMSG', '!gout alice | nextcmd | nextcmd2', source, '#chan-A')
        end)

        assert_loop(queue, TEST_TIMEOUT)

        ivar2.DispatchCommand = origDispatch
        ivar2:DisableModule('pipeline_test')

        -- Outer dispatch + one nested dispatch per pipeline say. The remainder
        -- cursor advances per say: say1 feeds through 'nextcmd', say2 through
        -- 'nextcmd2'. The third say runs out of remainder and plain-says.
        assert.are_equal(3, #dispatchArgs)
        assert.are_equal('!gout alice | nextcmd | nextcmd2', dispatchArgs[1])
        assert.are_equal('nextcmd out1|nextcmd2', dispatchArgs[2])
        assert.are_equal('nextcmd2 out2', dispatchArgs[3])
        assert.are_equal(1, #sayCalls)
        assert.are_equal('out3', sayCalls[1].msg)
        assert.are_equal('#chan-A', sayCalls[1].destination)
    end)
end)
end
