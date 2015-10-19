-- GNU GCIDE dict, see tools/gcide2sqlite.lua
sql = require'lsqlite3'

lookup = (s, d, word) =>
  db = sql.open 'cache/words.sqlite3'
  stmt = db\prepare "SELECT * FROM words WHERE lower(word) = lower(?)"
  code = stmt\bind_values word
  out = {}
  i = 0
  for row in stmt\rows!
    i = i +1
    vals = stmt\get_values!
    word = vals[1]
    pos = vals[2]
    if pos then pos = " (#{ivar2.util.italic pos})" else pos = ''
    field = vals[3]
    if field then field = " #{field}" else field = ''
    definition = vals[4]
    table.insert out, "[#{ivar2.util.bold i}] #{pos}#{field} : #{definition}"
  db\close!
  if #out == 0
    -- Invalid name
    reply 'Nope. You suck. '
  else
    say "[#{ivar2.util.bold word}] #{table.concat out, ' '}"


PRIVMSG:
  '^%pdict (.+)$': lookup
  '^%pdefine (.+)$': lookup
