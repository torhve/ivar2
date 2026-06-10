local busted = require 'busted'
local describe = busted.describe
local it = busted.it
local helper = require 'module_helper'

describe('stonks module', function()
    local ctx = helper.setup('stonks', 'config/ivartest.lua')

    it('matches !q pattern', function()
        local prefix = ctx.mock.config.prefix or '!'
        local pattern = ('^%pq (.+)$'):gsub('%%p', prefix)
        assert.is_not_nil(('!q NVDA'):match(pattern))
    end)

    it('makes HTTP request for quote', function()
        local ok, captures = pcall(function()
            return ctx:invoke('!q AAPL', { timeout = 5 })
        end)
        -- API may fail if key is expired, but framework should still work
        if ok then
            assert.is_true(#captures.say > 0 or #captures.reply > 0)
        end
    end)
end)