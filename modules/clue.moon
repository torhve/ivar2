-- Clue module requires clue data files and tosql.py from emnh/clue2

dbi = require 'DBI'
require'logging.console'
log = logging.console()
conn = false

attrs = {'grammar','reference', 'country', 'context', 'text'}

connect = ->
  conn, err = DBI.Connect('PostgreSQL', ivar2.config.dbname, ivar2.config.dbuser, ivar2.config.dbpass, ivar2.config.dbhost, ivar2.config.dbport)
  unless conn
    log\error "Unable to connect to DB: #{err}"
    return

  conn\autocommit(true)

dbh = ->
  connect! unless conn

  -- Check if connection is alive
  alive = conn\ping!
  connect! unless alive

  success, err = DBI.Do(conn, 'SELECT NOW()')
  unless success
    log\error "SQL Connection :#{err}"
    connect!

  return conn

lookup = (source, destination, lookup) =>
  stmt = dbh!\prepare [[
    SELECT
      tablename
    from
      pg_catalog.pg_tables
    where
      tablename like 'cl%'
    ]]
  stmt\execute!
  tables = {}
  for row in stmt\rows(true) -- true for column names
    tables[#tables+1] = row.tablename

  out = {}
  for dict in *tables
    out[dict] = {}
    stmt = dbh!\prepare [[
      SELECT
        *
      FROM
        ]]..dict..[[
      WHERE
        word = ?
      ]]
    stmt\execute lookup
    for row in stmt\rows(true) -- true for column names
      table.insert(out[dict], row)


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
    say table.concat(res, ' ')
  if i == 0
    reply 'Nope.'

upper = (s) ->
  (string.upper(s)\gsub('æ','Æ')\gsub('ø','Ø')\gsub('å','Å'))

getWord = (wordclass) ->
  stmt = dbh!\prepare [[
    SELECT
     *
    FROM
      clnono
    WHERE
      grammar = ?
    AND
      length(word) < 8
    ORDER BY
      random()
    LIMIT 1
  ]]
  stmt\execute wordclass
  out = {}
  for row in stmt\rows(true) -- true for column names
    table.insert(out, row)
  return out

bankid = (source, destination) =>

  adj = getWord 'adj'
  sub = getWord 's'

  say "#{upper adj[1].word} #{upper sub[1].word}"

PRIVMSG:
  '^%pclue (.+)$': lookup
  '^%pbankid$': bankid

