local os = require 'os'
local iconv = require'iconv'
local dbi = require 'DBI'
require'logging.console'
local log = logging.console()


local patterns = {
	-- X://Y url
	"^(https?://%S+)",
    "^<(https?://%S+)>",
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

-- check for existing url
local checkOlds = function(self, dbh, destination, source, url) 

    -- create a select handle
    local sth = assert(dbh:prepare([[
            SELECT 
                date_trunc('second', time),
                date_trunc('second', age(now(), date_trunc('second', time))),
                nick
            FROM urls
            WHERE 
                url=? 
            AND
                channel=?
            ORDER BY time ASC
        ]]
        ))

    -- execute select with a url bound to variable
    sth:execute(url,destination)

    -- get list of column names in the result set
    --local columns = sth:columns()

    local count = 0
    local nick
    local when

    -- iterate over the returned data
    for row in sth:rows() do
        count = count + 1
        -- rows() with no arguments (or false) returns
        -- the data as a numerically indexed table
        -- passing it true returns a table indexed by
        -- column names
        if count == 1 then
            when = row[1]
            ago = row[2]
            nick = row[3]
            when = when .. ', ' .. ago .. ' ago'
        end
    end

    if count > 0 then
        local plural = ''
        if count > 1 then 
            plural = 's' 
            ivar2:Msg('privmsg', destination, source, 'Olds! Linked %s time%s before. First %s by %s', count, plural, when, nick)
        else
            ivar2:Msg('privmsg', destination, source, 'Olds! Linked before at %s by %s', when, nick)
        end
    end

end

local handleUrl = function(self, source, destination, msg, url)

    -- Check if this module is disabled and just stop here if it is
    if not self:IsModuleDisabled('olds', destination) then
		local nick = source.nick

		-- TODO save connection
		local dbh = DBI.Connect('PostgreSQL', self.config.dbname, self.config.dbuser, self.config.dbpass, self.config.dbhost, self.config.dbport)

		checkOlds(self, dbh, destination, source, url)


		--local ok = dbh:close()
		--
    end

	-- Fire the oldsdone event for sqllogger
	ivar2.event:Fire('olds', self, source, destination, msg, url)
end

ivar2.event:Register('url', handleUrl)

return {
	-- Dummy event
	['9999'] = {
		function(...)
            return
        end,
    }
}
