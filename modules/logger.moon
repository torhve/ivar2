pgsql = require "cqueues_pgsql"
require'logging.console'
iconv = require'iconv'
iso2utf = iconv.new('UTF-8'.."//TRANSLIT", 'ISO-8859-1')
log = logging.console()

conn = false

schemas = {[[
  CREATE TABLE IF NOT EXISTS log (
    time timestamp DEFAULT now(),
    nick text,
    channel text,
    message text,
    type text
  );]],
  [[CREATE INDEX idx_time ON log(time);]],
  [[CREATE INDEX idx_channel ON log(channel);]]
}

toutf = (s) ->
  iso2utf\iconv(s)

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

dblog = (type, source, destination, arg) =>
  nick = source.nick

  unless arg
    arg = ''

  unless nick
    -- for example server mode lines only has source.mask
    nick = ''

  if type == 'PRIVMSG'
    -- action
    if arg\sub(1,1) == '\001' and arg\sub(-1) == '\001'
      arg = arg\sub(9, -2)
      type = 'ACTION'

  insert = ->
    dbh!\execParams('INSERT INTO log(nick,channel,message,type) values($1,$2,$3,$4)', nick, destination, arg, type)

  -- First try to insert statement directly
  -- if that doesn't work; convert it from iso to utf and try again
  stmt = insert!
  unless stmt
    @Log 'error', "logger: no stmtmt when inserting line"
    return
  if stmt\status() ~= pgsql.PGRES_COMMAND_OK
    arg, err = toutf(arg)
    stmt = insert!
    if stmt\status() ~= pgsql.PGRES_COMMAND_OK
      @Log('error', "logger: error when inserting line: \"%s\": %s", stmt\errorMessage())

history = (source, destination, nr) ->
  nr = tonumber(nr) or 1
  -- TODO ignore messages that are commands
  sql = [[
    SELECT
      *
      FROM log
      WHERE channel=$1
      AND (type = 'PRIVMSG' OR type = 'ACTION')
      ORDER BY time
      DESC LIMIT $2
    ]]
  out = res2rows(dbh!\execParams sql, destination, nr)
  if #out == 1
    return out[1].message
  return out

lastlog = (source, destination, arg) ->
  arg = '%'..arg..'%'
  sql = [[
    SELECT
      *
      FROM log
      WHERE channel=$1
      AND (type = 'PRIVMSG' OR type = 'ACTION')
      AND message LIKE $2
      ORDER BY time DESC
      LIMIT 20
    ]]
  out = res2rows(dbh!\execParams sql, destination, arg)

  if #out == 1
    return out[1].message
  return out

seen = (source, destination, nick) =>
  nick = ivar2.util.trim(nick)
  sql = [[
    SELECT
        *,
        date_trunc('second', time) as sectime,
        date_trunc('second', age(now(), date_trunc('second', time))) as ago
      FROM log
      WHERE nick = $1
      ORDER BY time DESC
      LIMIT 1
    ]]
  out = res2rows(dbh!\execParams sql, nick)

  actions =
    'ACTION': 'talking in third person'
    'TOPIC': 'changing topic'
    'PRIVMSG': 'jabbering'
    'NICK': 'changing nick'
    'QUIT': 'quitting'
    'PART': 'leaving'
    'NOTICE': 'sending a notice'
    'MODE': 'changing a mode'
    'JOIN': 'joining'


  if #out == 1
    r = out[1]
    message = ''
    if #r.message
      message == " with message #{r.message}"
    say "#{ivar2.util.bold r.nick} was last observed #{ivar2.util.italic actions[r.type]}#{message} #{r.ago} ago (#{r.sectime} UTC)"
  else
    say "#{ivar2.util.bold nick} was not seen in my lifetime."

return {
  PRIVMSG: {
    '^%pseen (.+)$': seen
    '^%plast$': (source, destination) =>
      -- Last message is the command requesting last, so get the next to last
      last_two = history(source,destination, 2)
      say last_two[2].message
    '^%plastlog (.+)$': (source, destination, arg) =>
      out = {}
      for k,v in *lastlog(source, destination, arg)
        -- Skip commands
        unless k.message\match('^%p')
          table.insert out, string.format('<%s> %s', k.nick, k.message)
      say table.concat(out, ' ')
    (s, d, a) =>
      dblog @, 'PRIVMSG', s, d, a
  }
  PRIVMSG_OUT: {
    (s, d, a) =>
      dblog @, 'PRIVMSG', s, d, a
  }
  NOTICE_OUT: {
    (s, d, a) =>
      dblog @, 'NOTICE', s, d, a
  }
  NOTICE: {
    (s, d, a) =>
      dblog @, 'NOTICE', s, d, a
  }
  JOIN: {
    (s, d, a) =>
      dblog @, 'JOIN', s, d, a
  }
  PART: {
    (s, d, a) =>
      dblog @, 'PART', s, d, a
  }
  KICK: {
    (s, d, a) =>
      dblog @, 'KICK', s, d, a
  }
  MODE: {
    (s, d, a) =>
      dblog @, 'MODE', s, d, a
  }
  TOPIC: {
    (s, d, a) =>
      dblog @, 'TOPIC', s, d, a
  }
  NICK: {
    (s, d, a) =>
      dblog @, 'NICK', s, d, a
  }
  QUIT: {
    (s, d, a) =>
      dblog @, 'QUIT', s, d, a
  }
}
