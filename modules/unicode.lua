local sql = require'lsqlite3'
-- utf-8 functions (C) Rici Lake
-- http://luaparse.luaforge.net/libquery.lua.html
local function X(str) return tonumber(str, 16) end
local elevenBits = X"7FF"
local sixteenBits = X"FFFF"
local math = require 'math'
local mod = math.mod
local strchar = string.char
local strbyte = string.byte
local strfind = string.find
local offset2 = X"C0" * 64 + X"80"
local offset3 = X"E0" * 4096 + X"80" * (64 + 1)
local offset4 = X"F0" * 262144 + X"80" * (4096 + 64 + 1)


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

local function fromUtf8(str)
    if strfind(str, "^[\1-\127%z]$") then return strbyte(str)
    elseif strfind(str, "^[\194-\223][\128-\191]$") then
        return strbyte(str, 1) * 64 + strbyte(str, 2) - offset2
    elseif strfind(str, "^[\225-\236\238\239][\128-\191][\128-\191]$")
        or strfind(str, "^\224[\160-\191][\128-\191]$")
        or strfind(str, "^\237[\128-\159][\128-\191]$") then
        return strbyte(str, 1) * 4096 + strbyte(str, 2) * 64 + strbyte(str, 3)
        - offset3
    elseif strfind(str, "^\240[\144-\191][\128-\191][\128-\191]$")
        or strfind(str, "^[\241\242\243][\128-\191][\128-\191][\128-\191]$")
        or strfind(str, "^\244[\128-\143][\128-\191][\128-\191]$") then
        return (strbyte(str, 1) * 262144 - offset4)
        + strbyte(str, 2) * 4096 + strbyte(str, 3) * 64 + strbyte(str, 4)
    end
end


local function handleSearch(self, source, destination, name)
    local db = sql.open("cache/unicode.sql")
    local selectStmt  = db:prepare('SELECT * FROM unicode WHERE LOWER(name) LIKE LOWER(?) LIMIT 50')
    selectStmt:bind_values('%'..name..'%')

    local out = {}
    for row in selectStmt:nrows() do
        table.insert(out, string.format('%s %s', toUtf8(row.cp), row.name))
    end

    db:close()

    if(#out) then
        say(table.concat(out, ', '))
    end
end

local function handleSearchShort(self, source, destination, name)
    local db = sql.open("cache/unicode.sql")
    local selectStmt  = db:prepare('SELECT cp FROM unicode WHERE LOWER(name) LIKE LOWER(?) LIMIT 500')
    selectStmt:bind_values('%'..name..'%')

    local out = {}
    for row in selectStmt:nrows() do
        table.insert(out, string.format('%s', toUtf8(row.cp)))
    end

    db:close()

    if(#out) then
        say(table.concat(out, ''))
    end
end

local function handleLookup(self, source, destination, str)
    local db = sql.open("cache/unicode.sql")
    local out = {}
    for uchar in string.gfind(str, "([%z\1-\127\194-\244][\128-\191]*)") do
        uchar = fromUtf8(uchar)
        if uchar then 
            local cp = string.format('%04x', uchar)
            local selectStmt  = db:prepare('SELECT * FROM unicode WHERE LOWER(cp) LIKE LOWER(?)')
            selectStmt:bind_values(cp)

            for row in selectStmt:nrows() do
                table.insert(out, string.format('U+%s %s', (row.cp), row.name))
            end
        end
    end

    db:close()

    if(#out) then
        say(table.concat(out, ', '))
    end
end

return {
    PRIVMSG = {
        ['^%pu (.*)$'] = handleSearch,
        ['^%pus (.*)$'] = handleSearchShort,
        ['^%pw (.*)$'] = handleLookup,
    }
}
