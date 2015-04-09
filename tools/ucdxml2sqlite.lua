local lxp = require"lxp"
local sql = require'lsqlite3'

local db = sql.open("unicode.sql")
local callbacks = {
    StartElement = function (parser, tname, attributes)
		local name = attributes.na
		if name then
			name = string.lower(name)
			local cp = attributes.cp
			local insStmt = db:prepare("INSERT INTO unicode VALUES(?, ?)")
			insStmt:bind_values(cp, name)
			insStmt:step()
			insStmt:finalize()
		end

    end
}

local p = lxp.new(callbacks)

local ud = io.open('ucd.all.flat.xml')

for l in ud:lines() do  -- iterate lines
    p:parse(l)          -- parses the line
    p:parse("\n")       -- parses the end of line
end
p:parse()               -- finishes the document
p:close()               -- closes the parser
db:close()
