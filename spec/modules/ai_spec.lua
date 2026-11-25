local module_helper = require 'module_helper'

describe('ai module', function()
    local context

    before_each(function()
        -- Mock util (minimal - ai module loads these at require time)
        package.loaded['util'] = {
            json = require 'cjson',
            trim = function(s) return s:gsub('^%s+', ''):gsub('%s+$', '') end,
            urlEncode = function(s) return s end,
            simplehttp = function() end, -- no-op, we don't test async here
        }

        -- Mock moonloader for .moon loading
        package.loaded['moonloader'] = require 'moonloader'

        local mock_bot = module_helper.mock_ivar2({
            config = {
                googleaiApiKey = 'test-key',
                nick = 'bot',
                commandPattern = '^!',
                prefix = '!',
            },
        })

        -- Capture Say/Reply on the mock bot
        mock_bot._said = {}
        mock_bot._replied = {}
        mock_bot.Say = function(self, dest, fmt, ...)
            local msg = select('#', ...) > 0 and string.format(fmt, ...) or fmt
            table.insert(mock_bot._said, {dest = dest, msg = msg})
        end
        mock_bot.Reply = function(self, dest, source, msg)
            table.insert(mock_bot._replied, {dest = dest, source = source, msg = msg})
        end
        mock_bot.Log = function() end
        mock_bot.Timer = function(self, name, initial, repeat_, cb)
            self._timer_cb = cb
            return { stop = function() end }
        end

        context = module_helper.context('ai', mock_bot)
    end)

    after_each(function()
        package.loaded['util'] = nil
    end)

    describe('pattern matching', function()
        it('matches !ai with argument (dispatches to geminiChat)', function()
            context:invoke('!ai hello world')
            -- geminiChat is async, no immediate reply expected
            assert.is_equal(0, #context.mock._replied)
            assert.is_equal(0, #context.mock._said)
        end)

        it('matches !ai without argument (askLast) - no history', function()
            context:invoke('!ai')
            assert.is_true(#context.mock._said > 0)
            local msg = context.mock._said[1].msg
            assert.is_not_nil(msg:find('history'))
        end)

        it('tracks non-command messages in history silently', function()
            context:invoke('just a regular message')
            assert.is_equal(0, #context.mock._said)
            assert.is_equal(0, #context.mock._replied)
        end)
    end)

    describe('module loading', function()
        it('loads without error with valid config', function()
            assert.is_not_nil(context.mod)
            assert.is_table(context.mod.PRIVMSG)
        end)
    end)
end)
