
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

describe("test IRC parser", function()
    describe("352 message", function()
        it("should parse 352 message with IPv6 host", function()
              line = ':server.server.com 352 botnick #channel user 2a00:dd52:211g::2 server.server.com nick H :0 Realname'
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
