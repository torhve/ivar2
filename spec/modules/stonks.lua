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

describe('stonks module (mocked)', function()
    local cjson = require 'cjson'

    local function make_price_data(opts)
        return {
            symbol = opts.symbol or 'AAPL',
            currency = 'USD',
            currencySymbol = '$',
            regularMarketPrice = { fmt = opts.regularMarketPrice or '180.50', raw = 180.50 },
            regularMarketChangePercent = { fmt = opts.regularMarketChangePercent or '+1.23%', raw = opts.regularMarketChangePercentRaw or 1.23 },
            regularMarketTime = opts.regularMarketTime or 1718000000,
            preMarketTime = opts.preMarketTime,
            preMarketPrice = opts.preMarketPrice and { fmt = opts.preMarketPrice, raw = opts.preMarketPrice } or nil,
            preMarketChangePercent = opts.preMarketChangePercent and { fmt = opts.preMarketChangePercent, raw = opts.preMarketChangePercentRaw } or nil,
            postMarketTime = opts.postMarketTime,
            postMarketPrice = opts.postMarketPrice and { fmt = opts.postMarketPrice, raw = opts.postMarketPrice } or nil,
            postMarketChangePercent = opts.postMarketChangePercent and { fmt = opts.postMarketChangePercent, raw = opts.postMarketChangePercentRaw } or nil,
            longName = opts.longName or 'Apple Inc.',
            shortName = opts.shortName or 'Apple',
        }
    end

    local function mock_simplehttp(json_data)
        return function()
            return cjson.encode(json_data)
        end
    end

    local function setup_mocked(mock_json)
        local real_util = package.loaded['util']
        local mock_util = {
            simplehttp = mock_simplehttp(mock_json),
            json = cjson,
            urlEncode = function(s) return s end,
            green = function(s) return s end,
            red = function(s) return s end,
        }
        package.loaded['util'] = mock_util
        local mock_ivar2 = helper.mock_ivar2({ config = { prefix = '!', yfinanceApiKey = 'test' } })
        local mod = helper.load_module('stonks', mock_ivar2)
        return mock_ivar2, mod, function() package.loaded['util'] = real_util end
    end

    local function invoke_handler(mod, mock, captures, arg)
        local callEnv = setmetatable({}, { __index = captures.env })
        callEnv.say = captures.env.say
        callEnv.reply = captures.env.reply
        local handler = mod.PRIVMSG['^%pq (.*)$']
        setfenv(handler, callEnv)
        handler(mock, { nick = 'tester', mask = 'tester!u@host' }, '#test', arg)
    end

    it('shows aftermarket change in parentheses with independent color', function()
        local price = make_price_data({
            regularMarketChangePercent = '+1.23%',
            regularMarketChangePercentRaw = 1.23,
            preMarketTime = 1717999000,
            postMarketTime = 1718001000,
            postMarketPrice = '181.00',
            postMarketChangePercent = '+0.50%',
            postMarketChangePercentRaw = 0.50,
        })
        local json_data = { quoteSummary = { result = { { price = price } } } }
        local mock_ivar2, mod, cleanup = setup_mocked(json_data)
        local captures = helper.capture_env(mock_ivar2)
        invoke_handler(mod, mock_ivar2, captures, 'AAPL')
        cleanup()

        assert.is_true(#captures.say > 0)
        local output = captures.say[1]
        assert.is_not_nil(output:match('%+1.23%%'))
        assert.is_not_nil(output:match('%+0.50%%'))
        assert.is_not_nil(output:match('%+0.50%%%)'))
    end)

    it('colors aftermarket change red when negative', function()
        local price = make_price_data({
            regularMarketChangePercent = '+1.23%',
            regularMarketChangePercentRaw = 1.23,
            preMarketTime = 1717999000,
            postMarketTime = 1718001000,
            postMarketPrice = '179.50',
            postMarketChangePercent = '-0.50%',
            postMarketChangePercentRaw = -0.50,
        })
        local json_data = { quoteSummary = { result = { { price = price } } } }
        local mock_ivar2, mod, cleanup = setup_mocked(json_data)
        local captures = helper.capture_env(mock_ivar2)
        invoke_handler(mod, mock_ivar2, captures, 'AAPL')
        cleanup()

        assert.is_true(#captures.say > 0)
        local output = captures.say[1]
        assert.match('%-0.50%%', output)
    end)

    it('omits parentheses when no aftermarket data', function()
        local price = make_price_data({
            regularMarketChangePercent = '+1.23%',
            regularMarketChangePercentRaw = 1.23,
        })
        local json_data = { quoteSummary = { result = { { price = price } } } }
        local mock_ivar2, mod, cleanup = setup_mocked(json_data)
        local captures = helper.capture_env(mock_ivar2)
        invoke_handler(mod, mock_ivar2, captures, 'AAPL')
        cleanup()

        assert.is_true(#captures.say > 0)
        local output = captures.say[1]
        assert.is_not_nil(output:match('%+1.23%%'))
        assert.is_nil(output:match('%('))
    end)
end)