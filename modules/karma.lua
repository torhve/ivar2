local sql = require'lsqlite3'

local function handleKarma(self, source, destination, item, sign, change) 

	local value = 0

	if change then
		if sign == '+=' then
			value = tonumber(change)
		elseif sign == '-=' then
			value = -tonumber(change)
		end
	else
		if sign == '++' then
			value = 1
		elseif sign == '--' then
			value = -1
		end
	end

	local db = sql.open("cache/karma.sql")
	local insStmt = db:prepare("INSERT INTO karma (item, change, nick) VALUES(?, ?, ?)")
	local code = insStmt:bind_values(item, value, source.nick)
		  code = insStmt:step()
		  code = insStmt:finalize()

	local selectStmt  = db:prepare('SELECT SUM(change) AS sum FROM karma WHERE LOWER(item) = LOWER(?)')
	selectStmt:bind_values(item)

	local iter, vm = selectStmt:nrows()
	local karma = iter(vm)

	db:close()

	if(karma) then
		self:Msg('privmsg', destination, source, "\002%s\002 karma is now %s", item, karma.sum)
	end
end

return {
	PRIVMSG = {
		['^([%w -_%.]+)(%+%+)$'] = handleKarma,
		['^([%w -_%.]+)(%-%-)$'] = handleKarma,
		['^([%w -_%.]]+)(%+=)%s?(%d+)$'] = handleKarma,
		['^([%w -_%.]+)(-=)%s?(%d+)$'] = handleKarma,
	}
}
