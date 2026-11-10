moduleName = 'systemd-watchdog'
notifyInterval = 30

-- os.execute returns different shapes across runtimes: Lua 5.2 gives
-- (true, "exit", code), while Lua 5.1 and LuaJIT give the bare exit status.
runCommand = (cmd) ->
  execOk, r1, r2, r3 = pcall os.execute, cmd
  unless execOk
    return false, tostring(r1)
  if type(r1) == 'number'
    return true if r1 == 0
    return false, "#{cmd} exited with #{r1}"
  if r1 == nil or r1 == false
    return false, "#{cmd} failed: #{tostring(r2)} #{tostring(r3)}"
  true

-- 1. Signal that the bot has finished loading
readyOk, readyErr = runCommand 'systemd-notify --ready'
unless readyOk
  ivar2\Log 'error', "#{moduleName}: #{readyErr}"

-- 2. Pet the watchdog. This uses a named timer, not a raw cqueues thread,
-- because ivar2:Timer cancels any existing timer with the same id. The old
-- queue\wrap loop leaked: ivar2:Connect() reloads every module, so every
-- reconnect stacked another immortal loop forking systemd-notify.
notify = ->
  petOk, petErr = runCommand 'systemd-notify WATCHDOG=1'
  unless petOk
    ivar2\Log 'error', "#{moduleName}: #{petErr}"

ivar2\Timer moduleName, notifyInterval, notifyInterval, notify
