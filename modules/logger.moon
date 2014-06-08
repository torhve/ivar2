dbi = require 'DBI'
require'logging.console'
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

  insert = dbh!\prepare('INSERT INTO log(nick,channel,message,type) values(?,?,?,?)')
  stmt, err = insert\execute(nick, destination, arg, type)
  unless stmt
    log\error err


return {
  PRIVMSG: {
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
