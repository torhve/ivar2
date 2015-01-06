moduleName = 'alias'
key = 'alias:aliases'

listAliases = =>
  out = {}
  for name,command in pairs(ivar2.persist[key] or {})
    table.insert(out, name)
  say "Aliases: #{table.concat(out, ', ')}"

showAlias = (s, d, name) =>
  c = ivar2.persist[key][name]
  if c then
    say "Alias: #{ivar2.util.bold name} => #{ivar2.util.bold c}"
  else
    reply "Noperino. Failerino."

aliasHelp = =>
  help = 'Usage: ¤alias add <name> <command>. Ex: ¤alias add ahelp alias help. Delete: ¤alias del <name>. List: ¤alias list. Show: ¤alias show <name>. Use § to denote | for piping commands."'
  patt = @ChannelCommandPattern('^%p', moduleName, destination)
  if patt == '^%p'
    patt = '!'
  help = help\gsub '¤', patt
  reply help

aliasHandler = (source, destination, pattern) =>
  return (source, destination, arg) =>
    patt = @ChannelCommandPattern('^%p', moduleName, destination)
    if patt == '^%p'
      patt = '!'
    pattern = pattern\gsub('§', '|'..patt)
    ivar2\DispatchCommand 'PRIVMSG', patt..pattern, source, destination

-- Register the command
regCommand = (source, destination, name, pattern) =>
  store = ivar2.persist[key] or {}
  store[name] = pattern
  ivar2.persist[key] = store
  patt = @ChannelCommandPattern('^%p', moduleName, destination)
  @RegisterCommand moduleName, patt..name, aliasHandler(@, source, destination, pattern)
  if source and destination
    reply "Registered new alias #{ivar2.util.bold name} for #{ivar2.util.bold pattern}"

-- Register aliases *after* module load
ivar2\Timer 'regAlias', 1, ->
  for name,command in pairs(ivar2.persist[key] or {})
    regCommand(ivar2, nil, nil, name, command)

delCommand = (source, destination, name) =>
  store = ivar2.persist[key] or {}
  store[name] = nil
  ivar2.persist[key] = store
  reply 'Ok, I guess'


PRIVMSG:
  '^%palias$': aliasHelp
  '^%palias help$': aliasHelp
  '^%palias add (%S+) (.+)$': regCommand
  '^%palias del (.+)$': delCommand
  '^%palias list$': listAliases
  '^%palias show (.+)$': showAlias
