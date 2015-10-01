-- GNU GCIDE dict, see tools/gcide2sqlite.lua
sql = require'lsqlite3'

lookup = (s, d, word) =>
  db = sql.open 'cache/words.sqlite3'
  stmt = db\prepare "SELECT * FROM words WHERE lower(word) = lower(?)"
  code = stmt\bind_values word
  code = stmt\step!
  if code == sqlite3.DONE
    -- Invalid name
    db\close!
    reply 'Nope. You suck. '
    return
  vals = stmt\get_values!
  db\close!
  pos = vals[2]
  if pos then pos = " (#{ivar2.util.italic pos})" else pos = ''
  field = vals[3]
  if field then field = " #{field}" else field = ''
  definition = vals[4]
  say "[#{ivar2.util.bold vals[1]}]#{pos}#{field} : #{definition}"

PRIVMSG:
  '^%pdict (.+)$': lookup
