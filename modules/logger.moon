dbi = require 'DBI'
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
  conn, err = DBI.Connect('PostgreSQL', ivar2.config.dbname, ivar2.config.dbuser, ivar2.config.dbpass, ivar2.config.dbhost, ivar2.config.dbport)
  unless conn
    log\error "Unable to connect to DB: #{err}"
    return

  conn\autocommit(true)

  --for s in *schemas
  --  a,b = DBI.Do(conn, s)


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


dblog = (type, source, destination, arg) =>
  nick = source.nick

  if type == 'PRIVMSG'
    -- action
    if arg\sub(1,1) == '\001' and arg\sub(-1) == '\001'
      arg = arg\sub(9, -2)
      type = 'ACTION'

  unless arg
    arg = ''

  insert = ->
    ins = dbh!\prepare('INSERT INTO log(nick,channel,message,type) values(?,?,?,?)')
    ins\execute(nick, destination, arg, type)

  -- First try to insert statement directly
  -- if that doesn't work; convert it from iso to utf and try again
  stmt, err = insert!
  unless stmt
    arg, err = toutf(arg)
    stmt, err = insert!
    unless stmt
      log\error err

history = (source, destination, nr) ->
  nr = tonumber(nr) or 1
  -- TODO ignore messages that are commands
  stmt = dbh!\prepare [[
    SELECT
      *
      FROM log
      WHERE channel=?
      AND (type = 'PRIVMSG' OR type = 'ACTION')
      ORDER BY time
      DESC LIMIT ?
    ]]
  stmt\execute destination, nr
  out = {}
  for row in stmt\rows(true) -- true for column names
    out[#out+1] = row

  if #out == 1
    return out[1].message
  return out

lastlog = (source, destination, arg) ->
  nr = tonumber(nr) or 1
  arg = '%'..arg..'%'
  stmt = dbh!\prepare [[
    SELECT
      *
      FROM log
      WHERE channel=?
      AND (type = 'PRIVMSG' OR type = 'ACTION')
      AND message LIKE ?
      ORDER BY time DESC
      LIMIT 20
    ]]
  stmt\execute destination, arg
  out = {}
  for row in stmt\rows(true) -- true for column names
    out[#out+1] = row

  if #out == 1
    return out[1].message
  return out

seen = (source, destination, nick) =>
  nick = ivar2.util.trim(nick)
  stmt, err = dbh!\prepare [[
    SELECT
        *,
        date_trunc('second', time) as sectime,
        date_trunc('second', age(now(), date_trunc('second', time))) as ago
      FROM log
      WHERE nick = ?
      ORDER BY time DESC
      LIMIT 1
    ]]
  unless stmt
    print(err)
  stmt\execute nick
  out = {}
  for row in stmt\rows(true) -- true for column names
    out[#out+1] = row

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
    '%pseen (.+)$': seen
    '%plast$': (source, destination) =>
      say history(source,destination,1)
    '%plastlog (.+)$': (source, destination, arg) =>
      out = {}
      for k,v in *lastlog(source, destination, arg)
        -- Skip commands
        unless k.message\match('^%p')
          table.insert out, string.format('<%s> %s', k.nick, k.message)
      say table.concat(out, ' ')
    (s, d, a) =>
      dblog @, 'PRIVMSG', s, d, a
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
