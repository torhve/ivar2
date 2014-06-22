local sql = require'lsqlite3'

local function openDB()
	local dbfilename = string.format("cache/karma.%s.sql", ivar2.network)
	local db = sql.open(dbfilename)

	db:exec([[
		CREATE TABLE IF NOT EXISTS karma (
			item text,
			time timestamp default current_timestamp,
			change integer,
			nick text
		);
	]])

	return db
end

local itemIsNick = function(nick)
	for channel, data in pairs(ivar2.channels) do
		for chanNick in pairs(data.nicks) do
			if(chanNick == nick) then return true end
		end
	end
end

local function outputKarma(self, source, destination, item)
	local db = openDB()
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
	item = ivar2.util.trim(item)

	local config = self.config.karma
	if change then
		if(config and not config.allowStepping) then return end

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

	if(config and config.nicksOnly) then
		if(not itemIsNick(item)) then
			return
		elseif(source.nick == item) then
			say("%s: Silly human, your karma must be decided by others!", source.nick)
			return
		end
	end

	local db = openDB()
	local insStmt = db:prepare("INSERT INTO karma (item, change, nick) VALUES(?, ?, ?)")
	local code = insStmt:bind_values(item, value, source.nick)
	code = insStmt:step()
	code = insStmt:finalize()

	db:close()

    outputKarma(self, source, destination, item)
end

local getKarma = function(self, source, destination, dir, text)
	local db = openDB()

	local out = {}

	for row in db:nrows('SELECT item, SUM(change) AS sum FROM karma GROUP BY item ORDER BY sum '..dir..' limit 5') do
		table.insert(out, string.format('\002%s\002:%s', row.item, row.sum))
	end

	db:close()

	say("%s karma: %s", text, table.concat(out, ', '))
end

local botKarma = function(self, source, destination, inp)
	getKarma(self, source, destination, 'ASC', 'Lowest')
end

local topKarma = function(self, source, destination, inp)
	getKarma(self, source, destination, 'DESC', 'Top')
end

return {
	PRIVMSG = {
		['^([%w %-_]+)(%+%+)$'] = handleKarma,
		['^([%w %-_]+)(%-%-)$'] = handleKarma,
		['^([%w %-_]+)(%+=)%s?(%d+)$'] = handleKarma,
		['^([%w %-_]+)(-=)%s?(%d+)$'] = handleKarma,
		['^%pkarma ([%w -_]+)$'] = outputKarma,
		['^%pkarma$'] = topKarma,
		['^%pkarmatop$'] = topKarma,
		['^%pkarmabot$'] = botKarma,
		['^%pkarmabottom$'] = botKarma,
	}
}
