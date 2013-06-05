local sql = require'lsqlite3'

local function outputKarma(self, source, destination, item)
	local db = sql.open("cache/karma.sql")
	local selectStmt  = db:prepare('SELECT SUM(change) AS sum FROM karma WHERE LOWER(item) = LOWER(?)')
	selectStmt:bind_values(item)

	local iter, vm = selectStmt:nrows()
	local karma = iter(vm)

	db:close()

	if(karma) then
		self:Msg('privmsg', destination, source, "\002%s\002 karma is %s", item, karma.sum)
	end
end

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

	db:close()

    outputKarma(self, source, destination, item)
end

local getKarma = function(self, source, destination, dir, text)
	local db = sql.open("cache/karma.sql")

	local out = {}

	for row in db:nrows('SELECT item, SUM(change) AS sum FROM karma GROUP BY item ORDER BY sum '..dir..' limit 5') do
		table.insert(out, string.format('\002%s\002:%s', row.item, row.sum))
	end

	db:close()

	self:Msg('privmsg', destination, source, "%s karma: %s", text, table.concat(out, ', '))
    
end

local botKarma = function(self, source, destination, inp)
	getKarma(self, source, destination, 'ASC', 'Lowest')
end

local topKarma = function(self, source, destination, inp)
	getKarma(self, source, destination, 'DESC', 'Top')
end

return {
	PRIVMSG = {
		['^([%w -_%.]+)(%+%+)$'] = handleKarma,
		['^([%w -_%.]+)(%-%-)$'] = handleKarma,
		['^([%w -_%.]+)(%+=)%s?(%d+)$'] = handleKarma,
		['^([%w -_%.]+)(-=)%s?(%d+)$'] = handleKarma,
		['^%pkarma ([%w -_%.]+)$'] = outputKarma,
		['^%pkarma$'] = topKarma,
		['^%pkarmatop$'] = topKarma,
		['^%pkarmabot$'] = botKarma,
		['^%pkarmabottom$'] = botKarma,
        
	}
}
