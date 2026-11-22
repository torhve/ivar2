local busted = require 'busted'
local describe = busted.describe
local it = busted.it
local before_each = busted.before_each
local helper = require 'module_helper'

-- Minimal stand-in for sqlpersist/persist: key/value table access plus keys().
local function make_persist()
    local store = {}
    local persist = {}
    persist.keys = function()
        local out = {}
        for k in pairs(store) do table.insert(out, k) end
        table.sort(out)
        return out
    end
    setmetatable(persist, {
        __index = function(_, k) return store[k] end,
        __newindex = function(_, k, v)
            if v == nil then
                store[k] = nil
            else
                store[k] = v
            end
        end,
    })
    return persist, store
end

local function make_ivar2(prefix)
    local persist, store = make_persist()
    local routes = {}
    local mock = helper.mock_ivar2({
        config = { prefix = '!', nick = 'bot', webserverprefix = prefix },
        webserver = {
            regUrl = function(pattern, handler) routes[pattern] = handler end,
            unRegUrl = function() end,
        },
    })
    mock.persist = persist
    return mock, routes, persist, store
end

describe('redirect module', function()
    local mock, routes, persist, store

    before_each(function()
        mock, routes, persist, store = make_ivar2('https://irc.lart.no/9')
        helper.load_module('redirect', mock)
    end)

    it('registers the /+code route', function()
        assert.is_not_nil(routes['^/%+(%w+)$'])
    end)

    it('shortens through the bot webserver prefix', function()
        local short
        mock.shorten('https://example.com/a?b=c', function(url) short = url end)
        assert.is_not_nil(short)
        assert.are.equal('string', type(short))
        assert.is_not_nil(short:match('^https://irc.lart.no/9/%+%w+$'))
    end)

    it('stores the target url behind the code', function()
        local short
        mock.shorten('https://example.com/very/long/link', function(url) short = url end)
        local code = short:match('/%+(%w+)$')
        assert.are.equal('https://example.com/very/long/link', persist['redirect:' .. code].url)
    end)

    it('hands out distinct codes', function()
        local seen = {}
        for i = 1, 50 do
            local short
            mock.shorten('https://example.com/' .. i, function(url) short = url end)
            local code = short:match('/%+(%w+)$')
            assert.is_nil(seen[code], 'reused code ' .. code)
            seen[code] = true
        end
    end)

    it('redirects with 302 and a location header', function()
        local short
        mock.shorten('https://example.com/target', function(url) short = url end)
        local code = short:match('/%+(%w+)$')

        local body, status, headers = routes['^/%+(%w+)$'](mock, { url = '/+' .. code })
        assert.are.equal(302, status)
        assert.are.equal('https://example.com/target', headers.location)
        assert.is_not_nil(body)
    end)

    it('404s unknown codes', function()
        local _, status = routes['^/%+(%w+)$'](mock, { url = '/+nosuchcode' })
        assert.are.equal(404, status)
    end)

    it('counts hits', function()
        local short
        mock.shorten('https://example.com/target', function(url) short = url end)
        local code = short:match('/%+(%w+)$')
        for _ = 1, 3 do
            routes['^/%+(%w+)$'](mock, { url = '/+' .. code })
        end
        assert.are.equal(3, persist['redirect:' .. code].hits)
    end)

    it('strips a trailing slash from the prefix', function()
        local trailing = make_ivar2('https://irc.lart.no/9/')
        helper.load_module('redirect', trailing)
        local short
        trailing.shorten('https://example.com/a', function(url) short = url end)
        assert.is_not_nil(short:match('^https://irc.lart.no/9/%+%w+$'))
    end)

    it('returns the raw url when no webserver prefix is set', function()
        local plain = helper.mock_ivar2()
        plain.persist = make_persist()
        helper.load_module('redirect', plain)
        local out
        plain.shorten('https://example.com/long', function(url) out = url end)
        assert.are.equal('https://example.com/long', out)
    end)

    it('prunes expired redirects on load', function()
        local fresh
        mock.shorten('https://example.com/fresh', function(url) fresh = url end)
        store['redirect:old1'] = { url = 'https://example.com/old', t = os.time() - (60 * 60 * 24 * 400) }
        store['redirect:old2'] = 'not a table'

        helper.load_module('redirect', mock)

        assert.is_nil(store['redirect:old1'])
        assert.is_nil(store['redirect:old2'])
        local code = fresh:match('/%+(%w+)$')
        assert.is_not_nil(store['redirect:' .. code])
    end)
end)
