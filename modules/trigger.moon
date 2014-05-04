sql = require'lsqlite3'

openDb = ->
  db = sql.open 'cache/trigger.sql'

  db\exec [[
    CREATE TABLE IF NOT EXISTS trigger (
      pattern UNIQUE ON CONFLICT REPLACE,
      funcstr
    );
    ]]
  return db

triggerHelp  = (source, destination, argument) =>
   @Msg 'privmsg', source, destination, 'Usage: !trigger add <lua pattern>|<lua code>. Ex: !trigger add !help (%w+)|say "%s, you need help'

-- Construct a safe environ for trigger with two functions; say and reply
--- TODO: actually make it safe :-)
--- Preferrably you should be able to cross-call modules here to make aliasing possible
sandbox = (func) ->
  (source, destination, ...) =>
    -- Store args so we can use them in env
    arg = {...}
    env =
      say: (str) ->
        @Msg 'privmsg', destination, source, str, unpack(arg),
      reply: (str) ->
        @Msg 'privmsg', destination, source, source.nick..': '..str, unpack(arg),
      print: (str) ->
        @Msg 'privmsg', destination, source, str, unpack(arg),
      simplehttp:require'simplehttp'
      json:require'json'
      :string
      :type
      :tostring
      :tonumber
      :ipars
      :pairs
      :table
      :next

    --setfenv func, setmetatable(env, {__index: _G })
    setfenv func, env
    success, err = pcall func, arg
    if err
      @Msg 'privmsg', destination, source, err
    else
      success

-- Construct a safe function to run and return a handler
triggerHandler = (source, destination, funcstr) =>
  func, err = loadstring funcstr
  unless func
    @Msg 'privmsg', destination, source, 'Trigger error: %s', err
  else
    sandbox(func)


-- Stub to create a trigger name in event table
handlerName = (pattern) ->
  "trigger#{pattern}"

-- Register the command
regCommand = (source, destination, pattern, funcstr) =>
  db = openDb!
  ins = db\prepare "INSERT INTO trigger (pattern, funcstr) VALUES(?, ?)"
  code = ins\bind_values pattern, funcstr
  code = ins\step!
  code = ins\finalize!
  db\close!

  @RegisterCommand handlerName(pattern), pattern, triggerHandler(@, source, destination, funcstr)

delCommand = (source, destination, pattern) =>
  db = openDb!
  ins = db\prepare "DELETE FROM trigger WHERE pattern = ?"
  code = ins\bind_values pattern
  code = ins\step!
  code = ins\finalize!
  db\close!
  @UnregisterCommand handlerName(pattern)

-- Register commands on startup
db = openDb!
for row in db\nrows 'SELECT pattern, funcstr FROM trigger'
  print ivar2
  ivar2\RegisterCommand handlerName(row.pattern), row.pattern, triggerHandler(ivar2, nil, nil, row.funcstr)

PRIVMSG:
  '%ptrigger$': triggerHelp
  '%ptrigger add (.+)|(.+)$': regCommand
  '%ptrigger del (.+)$': delCommand
