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

-- save url to db
local handleUrl = function(self, source, destination, msg, url)
    local nick = source.nick

    log:info(string.format('Inserting URL into db. %s,%s, %s, %s', nick, destination, msg, url))
    -- TODO save connection
    local dbh = DBI.Connect('PostgreSQL', self.config.dbname, self.config.dbuser, self.config.dbpass, self.config.dbhost, self.config.dbport)

    -- check status of the connection
    -- local alive = dbh:ping()
    
    -- create a handle for an insert
    local insert = dbh:prepare('INSERT INTO urls(nick,channel,url,message) values(?,?,?,?)')

    -- execute the handle with bind parameters
    local stmt, err = insert:execute(nick, destination, url, msg)

    -- commit the transaction
    dbh:commit()
    
    --local ok = dbh:close()
end

ivar2.event:Register('olds', handleUrl)

return {
	-- Dummy event
	['9999'] = {
		function(...)
            return
        end,
    }
}
