
local module_helper = require 'module_helper'
local cjson = require 'cjson'

describe('laiko module', function()
    local context
    local mock_bot
    local said = {}
    local replied = {}
    local captured_requests = {}

    before_each(function()
        said = {}
        replied = {}
        captured_requests = {}

        local mock_util = {
            json = cjson,
            simplehttp = function(req, cb)
                captured_requests[#captured_requests + 1] = req.data
                if req.method == "POST" then
                    -- Simulate a successful API response
                    local response_body = '{"choices": [{"message": {"content": "Hello from AI!"}}]}'
                    local response = { status_code = 200 }
                    cb(response_body, req.url, response)
                else
                    local response = { status_code = 400, headers = {} }
                    cb(nil, req.url, response)
                end
            end,
        }
        package.loaded['util'] = mock_util

        mock_bot = module_helper.mock_ivar2({
            config = {
                laiko_api_url = 'http://api.example.com/chat',
                laiko_model = 'test-model',
                nick = 'laiko',
                commandPattern = '^!'
            }
        })
        
        -- Mock Say/Reply on the bot instance
        -- Reply(destination, source, format, ...) -> "<nick>: <format>"
        mock_bot.Reply = function(self, destination, source, format, ...)
            local msg = select('#', ...) > 0 and string.format(format, ...) or format
            local nick = (type(source) == 'table' and source.nick) or '?'
            table.insert(replied, nick .. ': ' .. msg)
        end
        mock_bot.Say = function(self, str, ...)
            local msg = select('#', ...) > 0 and string.format(str, ...) or str
            table.insert(said, msg)
        end
        mock_bot.Log = function() end

        context = module_helper.context('laiko', mock_bot)
    end)

    after_each(function()
        package.loaded['util'] = nil
    end)

    it('successfully calls the AI API and replies', function()
        context:invoke('laiko: hello', { nick = 'tester' })

        assert.are_equal(1, #replied)
        assert.match('tester: Hello from AI!', replied[1])
    end)

    it('resets context with !new command', function()
        context:invoke('laiko: new', { nick = 'tester' })

        assert.are_equal(1, #replied)
        assert.match('Context reset', replied[1])
    end)

    it('ignores channel messages not addressed to the bot', function()
        context:invoke('hello there', { nick = 'tester' })

        assert.are_equal(0, #replied)
    end)

    it('responds to DMs without the laiko: prefix', function()
        context:invoke('hello', { nick = 'tester', dest = 'laiko' })

        assert.are_equal(1, #replied)
        assert.match('tester: Hello from AI!', replied[1])
    end)

    it('keeps conversations separate per destination', function()
        context:invoke('laiko: hi', { nick = 'tester' })
        context:invoke('laiko: hi', { nick = 'tester' })
        context:invoke('hi', { nick = 'tester', dest = 'laiko' })

        -- DM session must not inherit channel lines: system prompt + user line only
        local dm_payload = cjson.decode(captured_requests[3])
        assert.are_equal(2, #dm_payload.messages)
    end)

    it('keeps only a few lines of conversation per user', function()
        for i = 1, 5 do
            context:invoke('laiko: question ' .. i, { nick = 'tester' })
        end

        local last_payload = cjson.decode(captured_requests[5])
        assert.are_equal(8, #last_payload.messages)
    end)

    it('keeps conversations separate per user', function()
        context:invoke('laiko: hi', { source = { nick = 'alice' } })
        context:invoke('laiko: hi', { source = { nick = 'bob' } })

        -- Each user should see only their own line (system + user message)
        assert.are_equal(2, #cjson.decode(captured_requests[1]).messages)
        assert.are_equal(2, #cjson.decode(captured_requests[2]).messages)
    end)
end)
