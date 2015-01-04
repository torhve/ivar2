
package.path = table.concat({
    'libs/?.lua',
    'libs/?/init.lua',

    '',
}, ';') .. package.path

package.cpath = table.concat({
    'libs/?.so',

    '',
}, ';') .. package.cpath

local util = require 'util'
local irc = require 'irc'
local utf8 = util.utf8

describe("test IRC parser", function()
    describe("352 message", function()
        it("should parse 352 message with IPv6 host", function()
              local line = ':server.server.com 352 botnick #channel user 2a00:dd52:211g::2 server.server.com nick H :0 Realname'
              local command, argument, source, destination = irc.parse(line)
              assert.are_equal('352', command)
              assert.are_equal('server.server.com', source)
              assert.are_equal('#channel', destination)
              assert.are_same({
                  mode = 'H',
                  hopcount = ':0',
                  server = 'server.server.com',
                  nick = 'nick',
                  realname = 'Realname',
                  user = 'user'
              }, argument)
        end)
    end)
end)

describe("test util lib", function()
    describe("utf8 string tests", function()
        it("should work with multibye utf8 chars", function()
            local line = {'F','o','o',' ','æ','ø','Å','😀'}
            local uline = {}
            for c in util.utf8.chars(table.concat(line)) do
                table.insert(uline, c)
            end
            assert.are_same(line, uline)
            assert.are_equal(#line, utf8.len(table.concat(line)))
            local reversed = {}
            for i=#line,1,-1 do
                table.insert(reversed, line[i])
            end
            assert.are_same(table.concat(reversed), utf8.reverse(table.concat(line)))

            assert.are_equal('foo æøå😀', utf8.lower(table.concat(line)))

        end)
    end)
end)
