local sql = require'lsqlite3'
local date = require'date'

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
local checkOld = function(source, destination, url)
	local db = sql.open("cache/urls.sql")
	-- create a select handle
	local sth = db:prepare([[
		SELECT
			nick,
			timestamp
		FROM urls
		WHERE
			url=?
			AND
			channel=?
		ORDER BY timestamp ASC
	]])

	-- execute select with a url bound to variable
	sth:bind_values(url, destination)

	local count, first = 0
	while(sth:step() == sql.ROW) do
		count = count + 1

		if(count == 1) then
			first = sth:get_named_values()
		end
	end

	sth:finalize()
	db:close()

	if(count > 0) then
		local age = date.relativeTimeShort(first.timestamp)

		if(count > 1) then
			ivar2:Msg('privmsg', destination, source, 'Old! Linked %s times before. First %s ago by %s', count, age, first.nick)
		else
			ivar2:Msg('privmsg', destination, source, 'Old! Linked before, %s ago by %s', age, first.nick)
		end
	end
end

local updateDB = function(source, destination, url)
	local db = sql.open("cache/urls.sql")

	local sth = db:prepare[[
		INSERT INTO urls(nick, channel, url, timestamp)
		values(?, ?, ?, ?)
	]]

	sth:bind_values(source.nick, destination, url, os.time())
	sth:step()
	sth:finalize()
end

local handleUrl = function(self, source, destination, url)
	checkOld(source, destination, url)
	updateDB(source, destination, url)
end

return {
	PRIVMSG = {
		function(self, source, destination, argument)
			-- We don't want to pick up URLs from commands.
			if(argument:sub(1,1) == '!') then return end

			for split in argument:gmatch('%S+') do
				for i=1, #patterns do
					local _, count = split:gsub(patterns[i], function(url)
						if(url:sub(1,4) ~= 'http') then
							url = 'http://' .. url
						end

						handleUrl(self, source, destination, smartEscape(url))
					end)

					if(count > 0) then
						break
					end
				end
			end
		end,
	}
}
