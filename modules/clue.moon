-- Clue module requires clue data files and tosql.py from emnh/clue2

require'logging.console'
log = logging.console()
pgsql = require "cqueues_pgsql"

conn = false

attrs = {'grammar','reference', 'country', 'context', 'text'}

connect = ->
  conn = pgsql.connectdb("dbname=#{ivar2.config.dbname} user=#{ivar2.config.dbuser} password=#{ivar2.config.dbpass} host=#{ivar2.config.dbhost} port=#{ivar2.config.dbport}")
  if conn\status! != pgsql.CONNECTION_OK
    log\error conn\errorMessage
    return

dbh = ->
  connect! unless conn

  if conn\status() != pgsql.CONNECTION_OK
    log\error conn\errorMessage
    connect!

  success, err = conn\exec('SELECT NOW()')
  unless success
    log\error "SQL Connection :#{err}"
    connect!

  return conn

res2rows = (res) ->
  if not res\status! == 2 then error(res\errorMessage(), nil)
  rows = {}

  for i=1, res\ntuples()
    row = {}
    for j=1, res\nfields!
      row[res\fname(j)] = res\getvalue(i, j)
    rows[#rows+1] = row
  return rows

lookup = (source, destination, lookup) =>
  stmt = dbh!\exec [[
    SELECT
      tablename
    from
      pg_catalog.pg_tables
    where
      tablename like 'cl%'
    ]]
  tables = {}
  if not stmt\status! == 2 then error(stmt\errorMessage(), nil)
  for i=1, stmt\ntuples()
    tables[#tables+1] = stmt\getvalue(i, 1)

  out = {}
  for dict in *tables
    out[dict] = res2rows dbh!\execParams [[
      SELECT
        *
      FROM
        ]]..dict..[[
      WHERE
        word = $1
      ]], lookup

  i = 0
  for dict, rows in pairs out
    res = {}
    dfrom = dict\sub(3, 4)
    to = dict\sub(5, 6)
    first = true
    for row in *rows
      i += 1
      if first
        table.insert(res, "[#{ivar2.util.bold row.word}]")
        table.insert(res, "(#{ivar2.util.italic dfrom}")
        table.insert(res, "-> #{ivar2.util.italic to})")
        first = false
      for attr in *attrs
        if row[attr] != nil and row[attr] != ''
          if attr == 'grammar'
            table.insert(res, "(#{row[attr]}. )")
          else
            table.insert(res, row[attr])
    if #res > 0
      say table.concat(res, ' ')
  if i == 0
    reply 'Nope.'

upper = (s) ->
  (string.upper(s)\gsub('æ','Æ')\gsub('ø','Ø')\gsub('å','Å'))

getWord = (lang, wordclass, count, maxlen, startswith) ->
  unless startswith
    startswith = ''
  else
    startswith = "AND left(word,1) = '#{startswith}'"
  sql = [[
    SELECT
     *
    FROM
      ]]..lang..[[
    WHERE
      grammar = $1
    AND
      length(word) < $2
    ]]..startswith..[[
    ORDER BY
      random()
    LIMIT $3
  ]]
  res2rows dbh!\execParams(sql, wordclass, maxlen, count)

bankid = (source, destination) =>

  adj = getWord 'clnono', 'adj', 1, 8
  sub = getWord 'clnono', 's', 1, 10

  say "#{upper adj[1].word} #{upper sub[1].word}"

isLogWord = (word) ->
  myconn = dbh!
  sql = [[
    SELECT
     count(*)
    FROM
      log
    WHERE
      message ~* '\y]]..word..[[\y'
  ]]
  stmt = myconn\exec sql
  count = stmt.getvalue(1, 1)
  return tonumber(count) > 0

bankid2 = (source, destination) =>

  adj = ""
  sub = ""
  while true
    adj = getWord 'clnono', 'adj', 1, 20
    adj = adj[1].word
    continue unless isLogWord(adj)
  while true
    sub = getWord 'clnono', 's', 1, 20
    sub = sub[1].word
    continue unless isLogWord(sub)

  say "#{upper adj} #{upper sub}"

bankidmany = (source, destination, count) =>
  count = math.min(count, 100)

  adj = getWord 'clnono', 'adj', count, 8
  sub = getWord 'clnono', 's', count, 10

  out = {}
  for i=1, count
    table.insert(out, "#{upper adj[i].word} #{upper sub[i].word}")
  say table.concat(out, ', ')

adjsub = (source, destination, count) =>
  count = tonumber count
  if not count
    count = 1
  count = math.min(count, 100)

  adj = getWord 'clukuk', 'adj', count, 8
  sub = getWord 'clukuk', 'n', count, 10

  out = {}
  for i=1, count
    table.insert(out, "#{adj[i].word} #{sub[i].word}")
  say table.concat(out, ', ')

adj = (source, destination, count) =>
  count = 30

  word = getWord 'clnono', 'adj', count, 5

  out = {}
  for i=1, count
    table.insert(out, "#{word[i].word}")
  say table.concat(out, ', ')

PRIVMSG:
  '^%pclue (.+)$': lookup
  '^%pbankid$': bankid
  '^%pbankid (%d+)$': bankidmany
  '^%padj$': adj
  '^%padjsub$': adjsub
  '^%padjsub (%d+)$': adjsub
  '^%p?[Ff]lu+ffle (.+)$': (source, destination, arg) =>
    choice = math.random(1, 26)
    alliteration = ('abcdefghjijklmnopqrstuvxyz')\sub(choice, choice)
    adj = getWord 'clukuk', 'adj', 1, 8, alliteration
    sub = getWord 'clukuk', 'n', 1, 10, alliteration
    n = ''
    if alliteration\match '[aeiou]'
      n = 'n'
    say "#{ivar2.util.trim arg} got fluffled by a#{n} #{adj[1].word} #{sub[1].word}"
  --'^%pbankid2$': bankid2


