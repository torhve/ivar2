#!/bin/env lua
--[[
# gcide2sqlite.lua
#
# Lightning-fast loader to transform GCIDE dictionary quasi-XML into a syllable
# count database. Reads `CIDE.*` and writes `words.sqlite3`.
#
# NOTE: GCIDE lacks conjugations, plurals, words, and sometimes falsely notates
#   polysyllabic words as monosyllabic. User beware.
#
# Grab GCIDE data files at: http://ftp.gnu.org/gnu/gcide/
#
--]]
local sql = require'lsqlite3'
local iconv = require"iconv"
local utf2iso = iconv.new('iso-8859-1', 'utf-8')

local db = sql.open("words.sqlite3")

db:exec"PRAGMA synchronous=OFF"
db:exec"PRAGMA count_changes=OFF"
db:exec"PRAGMA journal_mode=MEMORY"
db:exec"PRAGMA temp_store=MEMORY"
db:exec"PRAGMA auto_vacuum=FULL"

local ret, err = db:exec[[
  CREATE TABLE IF NOT EXISTS words (
    word text,
    pos text,
    field text,
    definition text
  );
]]
db:exec'DELETE FROM words;'

-- Cache uniques in mem
local words =  {}

for c in ('abcdefghijklmnopqrstuvxyz'):gmatch('.') do

  local file = 'CIDE.'..c:upper()
  local fd = io.open(file)
  local entry = {}
  while true do
      line = fd:read('*l')
      if not line then break end
      local entry = line:match('<hw>([^<]+)</hw>')
      local pos = line:match('<pos>([^<]+)</pos>')
      local def = line:match('<def>([^<]+)</def>')
      local field = line:match('<fld>([^<]+)</fld>')
      if entry and pos and def then
          entry, _ = entry:gsub('[^A-Za-z0-9]', '')
          if not words[entry] then
              words[entry] = true
              -- Remove brackets
              def, _ = def:gsub("%b<>", "")
              def, _ = def:gsub('[^A-Za-z%-%.; ]', '')
              db:execute 'BEGIN TRANSACTION'
              entry = utf2iso:iconv(entry)
              def= utf2iso:iconv(def)
              --print(entry, pos, field, def)
              local stmt = db:prepare('INSERT INTO words (word, pos, field, definition) VALUES (?, ?, ?, ?)')
              stmt:bind_values(entry, pos, field, def)
              stmt:step()
              stmt:finalize()
              db:execute 'COMMIT TRANSACTION'
            end
        end
    end
end

db:execute 'CREATE INDEX word_index ON words (word);'
db:close()

