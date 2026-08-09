local module_helper = require 'module_helper'

describe('imagegen module', function()
    local context

    before_each(function()
        package.loaded['util'] = {
            json = require 'cjson',
            simplehttp = function() end,
        }

        package.loaded['base64'] = {
            encode = function(s) return s end,
            decode = function(s) return s end,
        }

        package.loaded['lfs'] = {
            attributes = function() return nil end,
            mkdir = function() end,
        }

        local mock_bot = module_helper.mock_ivar2({
            config = {
                openaiApiKey = 'test-key',
                openaiEndpoint = 'http://localhost:8090',
                webserverprefix = '',
                prefix = '!',
                nick = 'bot',
            },
        })

        mock_bot._said = {}
        mock_bot._replied = {}
        mock_bot.Say = function(self, dest, fmt, ...)
            local msg = select('#', ...) > 0 and string.format(fmt, ...) or fmt
            table.insert(mock_bot._said, {dest = dest, msg = msg})
        end
        mock_bot.Reply = function(self, dest, source, fmt, ...)
            local msg = select('#', ...) > 0 and string.format(fmt, ...) or fmt
            table.insert(mock_bot._replied, {dest = dest, source = source, msg = msg})
        end
        mock_bot.Log = function() end
        mock_bot.Timer = function(self, name, initial, repeat_, cb)
            self._timer_cb = cb
            return { stop = function() end }
        end

        context = module_helper.context('imagegen', mock_bot)
    end)

    after_each(function()
        package.loaded['util'] = nil
        package.loaded['base64'] = nil
        package.loaded['lfs'] = nil
    end)

    describe('module loading', function()
        it('loads without error with valid config', function()
            assert.is_not_nil(context.mod)
            assert.is_table(context.mod.PRIVMSG)
        end)
    end)

    describe('pattern matching', function()
        it('matches !aimage with prompt', function()
            context:invoke('!aimage cinematic portrait of a warrior')
            assert.is_equal(0, #context.mock._said)
            assert.is_equal(0, #context.mock._replied)
        end)

        it('matches !aimage with URL in prompt', function()
            local captures = context:invoke('!aimage make it rainy https://example.com/photo.jpg')
            assert.is_true(#captures.say > 0)
            local msg = captures.say[1]
            assert.is_not_nil(msg:find('downloading'))
        end)

        it('rejects !aimage with only a URL and no prompt', function()
            local captures = context:invoke('!aimage https://example.com/photo.jpg')
            assert.is_true(#captures.reply > 0)
            local msg = captures.reply[1]
            assert.is_not_nil(msg:find('prompt'))
        end)
    end)

    describe('missing config', function()
        before_each(function()
            package.loaded['util'] = {
                json = require 'cjson',
                simplehttp = function() end,
            }

            package.loaded['base64'] = {
                encode = function(s) return s end,
                decode = function(s) return s end,
            }

            package.loaded['lfs'] = {
                attributes = function() return nil end,
                mkdir = function() end,
            }

            local mock_bot = module_helper.mock_ivar2({
                config = {
                    prefix = '!',
                    nick = 'bot',
                },
            })

            mock_bot._said = {}
            mock_bot._replied = {}
            mock_bot.Say = function(self, dest, fmt, ...)
                local msg = select('#', ...) > 0 and string.format(fmt, ...) or fmt
                table.insert(mock_bot._said, {dest = dest, msg = msg})
            end
            mock_bot.Reply = function(self, dest, source, fmt, ...)
                local msg = select('#', ...) > 0 and string.format(fmt, ...) or fmt
                table.insert(mock_bot._replied, {dest = dest, source = source, msg = msg})
            end
            mock_bot.Log = function() end
            mock_bot.Timer = function() return { stop = function() end } end

            context = module_helper.context('imagegen', mock_bot)
        end)

        it('rejects !aimage when API key is missing', function()
            local captures = context:invoke('!aimage test prompt')
            assert.is_true(#captures.reply > 0)
            local msg = captures.reply[1]
            assert.is_not_nil(msg:find('not configured'))
        end)
    end)
end)
