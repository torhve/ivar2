local sql = require'lsqlite3'
local function X(str) return tonumber(str, 16) end
local elevenBits = X"7FF"
local sixteenBits = X"FFFF"
local math = require 'math'
local mod = math.mod
local strchar = string.char


local function toUtf8(i)
    i = X(i)
    if i <= 127 then return strchar(i)
    elseif i <= elevenBits then
        return strchar(i / 64 + 192, mod(i, 64) + 128)
    elseif i <= sixteenBits then
        return strchar(i / 4096 + 224,
        mod(i / 64, 64) + 128,
        mod(i, 64) + 128)
    else
        return strchar(i / 262144 + 240,
        mod(i / 4096, 64) + 128,
        mod(i / 64, 64) + 128,
        mod(i, 64) + 128)
    end
end

local function handleSearch(self, source, destination, name)
	local db = sql.open("cache/unicode.sql")
	local selectStmt  = db:prepare('SELECT * FROM unicode WHERE LOWER(name) LIKE LOWER(?)')
	selectStmt:bind_values('%'..name..'%')

    local out = {}
    -- self:Msg('privmsg', destination, source, 'hmm:%s', row)
    for row in selectStmt:nrows() do
        table.insert(out, string.format('%s %s', toUtf8(row.cp), row.name))
    end

	db:close()

	if(#out) then
		self:Msg('privmsg', destination, source, table.concat(out, ', '))
	end
end

return {
	PRIVMSG = {
		['^%pu (.*)$'] = handleSearch,
	}
}
