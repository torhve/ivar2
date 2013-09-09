#!/usr/bin/env luajit
-- Simple weechat log parser and db inserter
require'logging.console'
local log = logging.console()
local dbi = require 'DBI'
local dbh = DBI.Connect('PostgreSQL', 'irc', '', '', '127.0.0.1', '5432')
function ltrim(s, pat)
  return (s:gsub("^"..pat, ""))
end
function split(str, pat)
   local t = {}  -- NOTE: use {n = 0} in Lua-5.0
   local fpat = "(.-)" .. pat
   local last_end = 1
   local s, e, cap = str:find(fpat, 1)
   while s do
      if s ~= 1 or cap ~= "" then
     table.insert(t,cap)
      end
      last_end = e+1
      s, e, cap = str:find(fpat, last_end)
   end
   if last_end <= #str then
      cap = str:sub(last_end)
      table.insert(t, cap)
   end
   return t
end
local patterns = {
	-- X://Y url
	"^(https?://%S+)",
	"%f[%S](https?://%S+)",
	-- www.X.Y url
	"^(www%.[%w_-%%]+%.%S+)",
	"%f[%S](www%.[%w_-%%]+%.%S+)",
}
-- RFC 2396, section 1.6, 2.2, 2.3 and 2.4.1.
local smartEscape = function(str)
	local pathOffset = str:match("//[^/]+/()")

	-- No path means nothing to escape.
	if(not pathOffset) then return str end
	local prePath = str:sub(1, pathOffset - 1)

	-- lowalpha: a-z | upalpha: A-Z | digit: 0-9 | mark: -_.!~*'() |
	-- reserved: ;/?:@&=+$, | delims: <>#%" | unwise: {}|\^[]` | space: <20>
	local pattern = '[^a-zA-Z0-9%-_%.!~%*\'%(%);/%?:@&=%+%$,<>#%%"{}|\\%^%[%] ]'
	local path = str:sub(pathOffset):gsub(pattern, function(c)
		return ('%%%02X'):format(c:byte())
	end)

	return prePath .. path
end

-- save url to db
local handleUrl = function(nick, destination, msg, url, timestamp)
    log:info(string.format('Inserting URL into db. %s,%s, %s, %s', nick, destination, msg, url))
    -- TODO save connection

    -- check status of the connection
    local alive = dbh:ping()
    
    -- create a handle for an insert
    local insert = dbh:prepare('insert into urls(time,nick,channel,url,message) values(?,?,?,?,?)')

    -- execute the handle with bind parameters
    local stmt, err = insert:execute(timestamp, nick, destination, url, msg)
    --ivar2:Msg('privmsg', destination, source, '%s:%s', stmt, err)

    -- commit the transaction
    dbh:commit()
    
end
local handleLine = function(source, destination, argument, timestamp)
    -- Skip notice
    if(source:sub(1,1) == '-') then return end
    -- We don't want to pick up URLs from commands.
    if(argument:sub(1,1) == '!') then return end

    local tmp = {}
    local tmpOrder = {}
    local index = 1
    for split in argument:gmatch('%S+') do
        for i=1, #patterns do
            local _, count = split:gsub(patterns[i], function(url)
                if(url:sub(1,4) ~= 'http') then
                    url = 'http://' .. url
                end

                url = smartEscape(url)

                if(not tmp[url]) then
                    table.insert(tmpOrder, url)
                    tmp[url] = index
                else
                    tmp[url] = string.format('%s+%d', tmp[url], index)
                end
            end)

            if(count > 0) then
                index = index + 1
                break
            end
        end
    end

    if(#tmpOrder > 0) then

        for i=1, #tmpOrder do
            local url = tmpOrder[i]
            handleUrl(source, destination, argument, url, timestamp)
        end
    end
end

if arg[1] == nil  or arg[2] == nil then
    print ('Usage: weechatlogparser.lua channelname logfile')
    os.exit(1)
end

local sep = '\t'
local f = io.open(arg[1])
for line in f:lines() do

    local s = split(line, sep)
    local timestamp = s[1]
    local nick = ltrim(ltrim(s[2], '@*'), '+')
    local len = #s
    local msg = ''
    if len >= 3 then
        msg = s[3]
        for i=4, len, 1 do
            msg = msg .. '\t' .. s[i]
        end
    end
    handleLine(nick, arg[1], msg, timestamp)
end


