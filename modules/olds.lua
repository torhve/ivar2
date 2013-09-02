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

-- check for existing url
local checkOlds = function(self, destination, source, url)
	local db = sql.open("cache/urls.sql")
	-- create a select handle
	local sth = db:prepare([[
		SELECT
			nick,
			timestamp,
			count
		FROM urls
		WHERE
			url=?
			AND
			channel=?
		ORDER BY time ASC
	]])

	-- execute select with a url bound to variable
	sth:bind_values(url, destination)
	local iter, vm = sth:nrows()
	local row = iter(vm)

	if(row and row.count > 0) then
		local age = date.relativeTimeShort(os.time() - row.timestamp)

		if(count > 1) then
			ivar2:Msg('privmsg', destination, source, 'Old! Linked %s times before. First %s by %s', count, age, row.nick)
		else
			ivar2:Msg('privmsg', destination, source, 'Old! Linked before, %s by %s', age, row.nick)
		end
	end
end

local handleUrl = function(self, source, destination, msg, url)
	-- Check if this module is disabled and just stop here if it is
	if not self:IsModuleDisabled('olds', destination) then
		checkOlds(self, destination, source, url)
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
