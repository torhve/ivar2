Prettyfi = (patt) ->
  -- Make them prettier
  patt = patt\gsub('%^%%p', '!')
  patt = patt\gsub('%$$', '')
  patt = patt\gsub('^%^', '')
  patt = patt\gsub '%$', ''
  return patt

listModules = (source, destination, arg) =>
  out = {}
  for moduleName, moduleTable in next, @Events!['PRIVMSG']
    unless @IsModuleDisabled moduleName, destination
      table.insert out, moduleName
  if #out > 0
    say "Type !help name-of-module to list patterns for each module. Modules: %s", table.concat(out, ' ')

listPatterns = (source, destination, moduleName) =>
  moduleTable = @Events!['PRIVMSG'][moduleName]
  unless moduleTable
    return

  if @IsModuleDisabled moduleName, destination
    return

  out = {}
  for pattern, callback in next, moduleTable
    patt = @ChannelCommandPattern(pattern, moduleName, destination)
    patt = Prettyfi patt
    table.insert out, patt

  if #out > 0
    say "%s patterns:\n %s", moduleName, table.concat(out, ',\n ')

Apropos = (s, d, what) =>
  moduleTable = @Events!['PRIVMSG']
  unless moduleTable
    return

  out = {}
  for moduleName, moduleTable in next, moduleTable
    if @IsModuleDisabled moduleName, destination
      return

    for pattern, callback in next, moduleTable
      if type(pattern) == 'string'
        patt = @ChannelCommandPattern(pattern, moduleName, destination)
        if patt and type(patt) == 'string' and patt\match(what)
          out[#out+1] = "#{ivar2.util.bold moduleName} module has pattern #{ivar2.util.italic Prettyfi patt}"
  if #out == 0
    say "Could not find a command pattern that matches that."
  else
    say table.concat(out, ',\n')


PRIVMSG:
  '^%plist$': listModules
  '^%plist (%w+)$': listPatterns
  '^%phelp$': listModules
  '^%phelp (%w+)$': listPatterns
  '^%papropos (.*)$': Apropos
