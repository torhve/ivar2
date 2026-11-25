local module_helper = require 'module_helper'

describe('lai module', function()
    local context

    before_each(function()
        -- Mock util (minimal - lai module loads these at require time)
        package.loaded['util'] = {
            json = require 'cjson',
            trim = function(s) return s:gsub('^%s+', ''):gsub('%s+$', '') end,
            urlEncode = function(s) return s end,
            simplehttp = function() end, -- no-op, we don't test async here
        }

        -- Mock htmltext
        package.loaded['htmltext'] = {
            extract = function() return 'Extracted text.' end,
        }

        -- Mock base64
        package.loaded['base64'] = {
            encode = function(s) return s end,
            decode = function(s) return s end,
        }

        -- Mock lfs
        package.loaded['lfs'] = {
            attributes = function() return nil end,
            mkdir = function() end,
        }

        local mock_bot = module_helper.mock_ivar2({
            config = {
                llmApiKey = 'test-key',
                llmEndpoint = 'http://localhost:8080',
                llmModel = 'gemma4-text',
                imageModel = 'qwen-image-turbo',
                prefix = '!',
                nick = 'bot',
            },
        })

        mock_bot._said = {}
        mock_bot._replied = {}
        mock_bot.Say = function(self, dest, a, b, ...)
            local msg
            if type(a) == 'string' then
                msg = a
            else
                msg = b
            end
            table.insert(mock_bot._said, {dest = dest, msg = msg})
        end
        mock_bot.Reply = function(self, dest, source, msg, ...)
            table.insert(mock_bot._replied, {dest = dest, source = source, msg = msg})
        end
        mock_bot.Log = function() end
        mock_bot.Timer = function(self, name, initial, repeat_, cb)
            self._timer_cb = cb
            return { stop = function() end }
        end

        context = module_helper.context('lai', mock_bot)
    end)

    after_each(function()
        package.loaded['util'] = nil
        package.loaded['htmltext'] = nil
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
        it('matches !lai with text argument (dispatches to llm_chat)', function()
            context:invoke('!lai hello world')
            -- llm_chat is async, no immediate reply expected
            assert.is_equal(0, #context.mock._replied)
            assert.is_equal(0, #context.mock._said)
        end)

        it('matches !lai with URL argument (dispatches to llm_url)', function()
            context:invoke('!lai https://example.com/page')
            -- llm_url immediately replies "Fetching and summarizing..."
            assert.is_equal(1, #context.mock._replied)
            local msg = context.mock._replied[1].msg
            assert.is_not_nil(msg:find('Fetching'))
        end)

        it('matches !lai without argument (askLastLocal) - no history', function()
            context:invoke('!lai')
            assert.is_true(#context.mock._said > 0)
            local msg = context.mock._said[1].msg
            assert.is_not_nil(msg:find('local AI'))
        end)

        it('matches !summary with URL argument', function()
            context:invoke('!summary https://example.com/page')
            -- llm_url immediately replies "Fetching and summarizing..."
            assert.is_equal(1, #context.mock._replied)
            local msg = context.mock._replied[1].msg
            assert.is_not_nil(msg:find('Fetching'))
        end)

        it('matches !summary without URL - no history', function()
            context:invoke('!summary')
            assert.is_true(#context.mock._said > 0)
            local msg = context.mock._said[1].msg
            assert.is_not_nil(msg:find('history'))
        end)

        it('matches !aimage with prompt', function()
            context:invoke('!aimage cinematic portrait of a warrior')
            -- generate_image is async, no immediate reply expected
            assert.is_equal(0, #context.mock._said)
            assert.is_equal(0, #context.mock._replied)
        end)

        it('matches !aimage with URL in prompt (downloading...)', function()
            context:invoke('!aimage make it rainy https://example.com/photo.jpg')
            assert.is_true(#context.mock._said > 0)
            local msg = context.mock._said[1].msg
            assert.is_not_nil(msg:find('downloading'))
        end)

        it('rejects !aimage with only a URL and no prompt', function()
            context:invoke('!aimage https://example.com/photo.jpg')
            assert.is_true(#context.mock._replied > 0)
            local msg = context.mock._replied[1].msg
            assert.is_not_nil(msg:find('prompt'))
        end)
    end)

    describe('missing config', function()
        before_each(function()
            package.loaded['util'] = {
                json = require 'cjson',
                trim = function(s) return s:gsub('^%s+', ''):gsub('%s+$', '') end,
                urlEncode = function(s) return s end,
                simplehttp = function() end,
            }

            package.loaded['htmltext'] = {
                extract = function() return 'Extracted text.' end,
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
            mock_bot.Say = function(self, dest, a, b, ...)
                local msg
                if type(a) == 'string' then
                    msg = a
                else
                    msg = b
                end
                table.insert(mock_bot._said, {dest = dest, msg = msg})
            end
            mock_bot.Reply = function(self, dest, source, msg, ...)
                table.insert(mock_bot._replied, {dest = dest, source = source, msg = msg})
            end
            mock_bot.Log = function() end
            mock_bot.Timer = function() return { stop = function() end } end

            context = module_helper.context('lai', mock_bot)
        end)

        it('rejects !aimage when API key is missing', function()
            context:invoke('!aimage test prompt')
            assert.is_true(#context.mock._replied > 0)
            local msg = context.mock._replied[1].msg
            assert.is_not_nil(msg:find('not configured'))
        end)

        it('rejects !lai when API key is missing', function()
            context:invoke('!lai hello world')
            assert.is_true(#context.mock._replied > 0)
            local msg = context.mock._replied[1].msg
            assert.is_not_nil(msg:find('not configured'))
        end)

        it('rejects !summary when API key is missing', function()
            context:invoke('!summary https://example.com/page')
            assert.is_true(#context.mock._replied > 0)
            local msg = context.mock._replied[1].msg
            assert.is_not_nil(msg:find('not configured'))
        end)
    end)
end)
