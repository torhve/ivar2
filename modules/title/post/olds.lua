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

local openDB = function()
	local dbfilename = string.format("cache/urls.%s.sql", ivar2.network)
	local db = sql.open(dbfilename)

	db:exec([[
		CREATE TABLE IF NOT EXISTS urls (
			nick text,
			timestamp integer,
			url text,
			channel text
		);
	]])

	return db
end

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
	local db = openDB()
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

		return first.nick, count, age
	end
end

local updateDB = function(source, destination, url)
	local db = openDB()

	local sth = db:prepare[[
		INSERT INTO urls(nick, channel, url, timestamp)
		values(?, ?, ?, ?)
	]]

	sth:bind_values(source.nick, destination, url, os.time())
	sth:step()
	sth:finalize()
end

do
	return function(source, destination, queue)
		local nick, count, age = checkOld(source, destination, queue.url)
		updateDB(source, destination, queue.url)

		-- relativeTimeShort() returns nil if it gets fed os.time().
		if(not age) then return end

		local prepend
		if(count > 1) then
			prepend = string.format("Old! %s times, first by %s %s ago", count, nick, age)
		else
			prepend = string.format("Old! Linked by %s %s ago", nick, age)
		end

		if(queue.output) then
			queue.output = string.format("%s - %s", prepend, queue.output)
		else
			queue.output = prepend
		end
	end
end
