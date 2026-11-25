local busted = require 'busted'
local describe = busted.describe
local it = busted.it
local helper = require 'module_helper'

describe('ping module', function()
    local ctx = helper.setup('ping', 'config/ivartest.lua')

    it('responds to !ping', function()
        local captures = ctx:invoke('!ping')
        assert.is_true(#captures.say > 0)
        assert.is_not_nil(captures.say[1]:match('pong'))
    end)
end)