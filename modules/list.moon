
listModules = (source, destination, arg) =>
  out = {}
  for moduleName, moduleTable in next, @Events!['PRIVMSG']
    unless @IsModuleDisabled moduleName, destination
      table.insert out, moduleName
  if #out > 0
    @Msg 'privmsg', destination, source, "Modules: %s", table.concat(out, ', ')

listPatterns = (source, destination, moduleName) =>
  moduleTable = @Events!['PRIVMSG'][moduleName]
  unless moduleTable
    return

  if @IsModuleDisabled moduleName, destination
    return

  out = {}
  for pattern, callback in next, moduleTable
    table.insert out, pattern

  if #out > 0
    @Msg 'privmsg', destination, source, "%s patterns: %s", moduleName, table.concat(out, ', ')

PRIVMSG:
  '%plist$': listModules
  '%plist (%w+)$': listPatterns
