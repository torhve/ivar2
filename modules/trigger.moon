sql = require'lsqlite3'

openDb = ->
  db = sql.open 'cache/trigger.sql'

  db\exec [[
    CREATE TABLE IF NOT EXISTS trigger (
      name UNIQUE ON CONFLICT REPLACE,
      pattern UNIQUE ON CONFLICT REPLACE,
      funcstr
    );
    ]]
  return db

triggerHelp  = (source, destination, argument) =>
   @Msg 'privmsg', destination, source, 'Usage: !trigger add <name>|<lua pattern>|<lua code>. Ex: !trigger add help|^!help (%w+)|say "%s, you need help. Delete: !trigger del <name>"'

-- Construct a safe environ for trigger with two functions; say and reply
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

-- Register the command
regCommand = (source, destination, name, pattern, funcstr) =>
  db = openDb!
  ins = db\prepare "INSERT INTO trigger (name, pattern, funcstr) VALUES(?, ?, ?)"
  code = ins\bind_values name, pattern, funcstr
  code = ins\step!
  code = ins\finalize!
  db\close!

  @RegisterCommand 'trigger', pattern, triggerHandler(@, source, destination, funcstr)

delCommand = (source, destination, name) =>
  db = openDb!
  -- Find pattern which is used for deletion of handler
  stmt = db\prepare "SELECT pattern FROM trigger WHERE name = ?"
  code = stmt\bind_values name
  code = stmt\step!
  if code == sqlite3.DONE
    -- Invalid name
    db\close!
    @Msg 'privmsg', destination, source, 'Invalid name'
    return
  pattern = stmt\get_values()[1]

  -- Delete trigger from db
  ins = db\prepare "DELETE FROM trigger WHERE name = ?"
  code = ins\bind_values name
  code = ins\step!
  code = ins\finalize!
  db\close!

  @UnregisterCommand 'triggers', pattern
  @Msg 'privmsg', destination, source, "Trigger #{pattern} deleted"

listTriggers = (source, destination) =>
  db = openDb!
  stmt = db\prepare "SELECT name FROM trigger"
  out = {}
  for row in stmt\nrows! do
    table.insert out, row.name

  db\close!

  if #out > 0
    @Msg 'privmsg', destination, source, "Triggers: "..table.concat(out, ', ')

showTrigger = (source, destination, name) =>
  db = openDb!
  stmt = db\prepare "SELECT * FROM trigger WHERE name = ?"
  code = stmt\bind_values name
  for row in stmt\nrows! do
    @Msg 'privmsg', destination, source, "Trigger: \002#{row.name}\002, pattern: #{row.pattern}, code: #{row.funcstr}"
  db\close!

-- Register commands on startup
db = openDb!
for row in db\nrows 'SELECT pattern, funcstr FROM trigger'
  ivar2\RegisterCommand 'triggers', row.pattern, triggerHandler(ivar2, nil, nil, row.funcstr)
db\close!

PRIVMSG:
  '^%ptrigger$': triggerHelp
  '^%ptrigger add (.+)|(.+)|(.+)$': regCommand
  '^%ptrigger del (.+)$': delCommand
  '^%ptrigger list$': listTriggers
  '^%ptrigger show (.+)$': showTrigger
