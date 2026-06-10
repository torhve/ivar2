
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
local busted = require'busted'
local cqueues = require'cqueues'
local new_headers = require "http.headers".new
local queue = cqueues.new()
local describe = busted.describe
local it = busted.it

describe("test IRC lib", function()
    describe("parse 352 message", function()
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
                  user = 'user',
                  sourcenick = 'botnick',
                  host = '2a00:dd52:211g::2',
              }, argument)
        end)
    end)
    describe("split irc message", function()
        local hostmask = 'irc@irc.example.com'
        local destination = '#channel'
        it("should keep short messages intact", function()
            local out = 'foobar'
            local message, extra = irc.split(hostmask, destination, out)
            assert.are_equal(out, message)
            assert.are_equal(extra, nil)
        end)
        it("should split long messages into two", function()
            local out = string.rep('A', 4096)
            local message, extra = irc.split(hostmask, destination, out)
            local less = #message < 512
            assert.is_true(less)
        end)
        it("should handle mb3 mb4 utf8", function()
            local out = "𝔞𝔟𝔠𝔡𝔢𝔣𝔤𝔥𝔦𝔧𝔨𝔩𝔪𝔫𝔬𝔭𝔮𝔯𝔰𝔱𝔲𝔳𝔵𝔶𝔷𝔄𝔅ℭ𝔇𝔈𝔉𝔊ℌℑ𝔍𝔎𝔏𝔐𝔑𝔒𝔓𝔔ℜ𝔖𝔗𝔘𝔙𝔛𝔜ℨ 𝔞𝔟𝔠𝔡𝔢𝔣𝔤𝔥𝔦𝔧𝔨𝔩𝔪𝔫𝔬𝔭𝔮𝔯𝔰𝔱𝔲𝔳𝔵𝔶𝔷𝔄𝔅ℭ𝔇𝔈𝔉𝔊ℌℑ𝔍𝔎𝔏𝔐𝔑𝔒𝔓𝔔ℜ𝔖𝔗𝔘𝔙𝔛𝔜ℨ 𝔞𝔟𝔠𝔡𝔢𝔣𝔤𝔥𝔦𝔧𝔨𝔩𝔪𝔫𝔬𝔭𝔮𝔯𝔰𝔱𝔲𝔳𝔵𝔶𝔷𝔄𝔅ℭ𝔇𝔈𝔉𝔊ℌℑ𝔍𝔎𝔏𝔐𝔑𝔒𝔓𝔔ℜ𝔖𝔗𝔘𝔙𝔛𝔜ℨ "
            local message, extra = irc.split(hostmask, destination, out)
            local less = #message < 512
            assert.is_true(less)
        end)
        it("should not lose any bytes", function()
            local out = string.rep('A', 4096)
            local message, extra = irc.split(hostmask, destination, out, '')
            local therest = #out - #message
            assert.are_equal(#extra, therest)
        end)
        it("should not die on empty", function()
            local message, extra = irc.split(hostmask, destination, nil, '')
            assert.are_equal(nil, message)
            assert.are_equal(nil, extra)
            local message, extra = irc.split(hostmask, destination, '', '')
            assert.are_equal('', message)
            assert.are_equal(nil, extra)
        end)
        it("should parse ACTION with stripping the 01 at the end", function()
              local line = ':server.server.com 352 botnick #channel user 2a00:dd52:211g::2 server.server.com nick H :0 Realname'
              local line = ":tx!tx@127.0.0.1 PRIVMSG #testchan :\001ACTION testing\001"
              local command, argument, source, destination = irc.parse(line)
              assert.are_equal('PRIVMSG', command)
              assert.are_equal('#testchan', destination)
              assert.are_equal('\001ACTION testing\001', argument)
        end)
    end)
    describe("format irc messages", function()
        it("should format ACTION ", function()
            assert.are_equal('\001ACTION testing\001', irc.formatCtcp('testing', 'ACTION'))
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

            assert.are_equal(utf8.char(97), 'a')
            assert.are_equal(utf8.char(0x1f600), '😀')
        end)
    end)
end)

describe("test ivar2:Msg dispatch", function()
	local function makeMock()
		local m = {
			config = { nick = "botnick" },
		}
		m.privmsg_dest = nil
		m.notice_dest = nil
		m.action_dest = nil
		m.last_args = {}
		function m:Privmsg(dest, ...)
			self.privmsg_dest = dest
			self.last_args = { dest, ... }
		end
		function m:Notice(dest, ...)
			self.notice_dest = dest
			self.last_args = { dest, ... }
		end
		function m:Action(dest, ...)
			self.action_dest = dest
			self.last_args = { dest, ... }
		end
		function m:Msg(type, dest, source, ...)
			if dest == self.config.nick then
				dest = source.nick or source
			end
			if type == "notice" then
				return self:Notice(dest, ...)
			elseif type == "action" then
				return self:Action(dest, ...)
			else
				return self:Privmsg(dest, ...)
			end
		end
		return m
	end

	describe("channel messages", function()
		it("should dispatch privmsg to :Privmsg", function()
			local m = makeMock()
			m:Msg("privmsg", "#chan", "user!u@h", "hello")
			assert.are_equal("#chan", m.privmsg_dest)
			assert.is_nil(m.notice_dest)
			assert.is_nil(m.action_dest)
		end)

		it("should dispatch notice to :Notice", function()
			local m = makeMock()
			m:Msg("notice", "#chan", "user!u@h", "beep")
			assert.are_equal("#chan", m.notice_dest)
			assert.is_nil(m.privmsg_dest)
			assert.is_nil(m.action_dest)
		end)

		it("should dispatch action to :Action", function()
			local m = makeMock()
			m:Msg("action", "#chan", "user!u@h", "waves")
			assert.are_equal("#chan", m.action_dest)
			assert.is_nil(m.privmsg_dest)
			assert.is_nil(m.notice_dest)
		end)
	end)

	describe("pm messages", function()
		it("should dispatch privmsg to source.nick in PM", function()
			local m = makeMock()
			m:Msg("privmsg", "botnick", { nick = "user" }, "pm")
			assert.are_equal("user", m.privmsg_dest)
			assert.is_nil(m.notice_dest)
			assert.is_nil(m.action_dest)
		end)

		it("should dispatch notice to source.nick in PM", function()
			local m = makeMock()
			m:Msg("notice", "botnick", { nick = "user" }, "pm")
			assert.are_equal("user", m.notice_dest)
			assert.is_nil(m.privmsg_dest)
			assert.is_nil(m.action_dest)
		end)

		it("should dispatch action to source.nick in PM", function()
			local m = makeMock()
			m:Msg("action", "botnick", { nick = "user" }, "pm")
			assert.are_equal("user", m.action_dest)
			assert.is_nil(m.privmsg_dest)
			assert.is_nil(m.notice_dest)
		end)

		it("should fall back to raw source string when no .nick", function()
			local m = makeMock()
			m:Msg("privmsg", "botnick", "user", "pm")
			assert.are_equal("user", m.privmsg_dest)
		end)
	end)

	describe("extra args forwarding", function()
		it("should forward extra args to the handler", function()
			local m = makeMock()
			m:Msg("privmsg", "#chan", "user!u@h", "%s %d", "hello", 42)
			assert.are_equal(4, #m.last_args)
			assert.are_equal("#chan", m.last_args[1])
			assert.are_equal("%s %d", m.last_args[2])
			assert.are_equal("hello", m.last_args[3])
			assert.are_equal(42, m.last_args[4])
		end)
	end)
	end)

describe("test webserver", function()
    describe("webserver tests", function()
        it("should listen", function()
            local webserver = assert(loadfile('core/webserver.lua'))(ivar2)
            local cqueue = cqueues.running()
            local new =cqueues.new()
            local server = webserver.start('localhost', 9999, new)
            queue:wrap(function()
                assert(server:listen())
                assert_loop(new)
            end)
            webserver.regUrl('/test', function(self, req, res)
              assert.are_equal(req.url, '/test')
              res:append(":status", "200")
              req:write_headers(res, false)
              req:write_body_from_string('Hello world!')
            end)
            webserver.regUrl('/simplereturn', function(self, req, res)
              return 'OK'
            end)
            queue:wrap(function()
                util.simplehttp('http://127.0.0.1:9999/asdf', function(data)
                    assert.are_equal(data, 'Nyet. I am four oh four')
                end)
            end)
            queue:wrap(function()
                util.simplehttp('http://[::1]:9999/test', function(data)
                    assert.are_equal(data, 'Hello world!')
                end)
                local data = util.simplehttp('http://[::1]:9999/simplereturn')
                assert.are_equal(data, 'OK')
            end)
            queue:wrap(function()
                util.simplehttp({
                    url='http://127.0.0.1:9999/test',
                }, function(data)
                    assert.are_equal(data, 'Hello world!')
                end)
            end)
            queue:wrap(function()
                util.simplehttp({
                    url='http://xt.gg/test.txt',
                }, function(data)
                    assert.are_equal(data, 'Hello world!\n')
                end)
            end)
            for i=1,10 do
                queue:wrap(function()
                    local data = util.simplehttp('http://[2a02:cc41:100f::10]/test.txt')
                    assert.are_equal(data, 'Hello world!\n')
                end)
            end
                assert_loop(queue, TEST_TIMEOUT)

        end)
    end)
end)
