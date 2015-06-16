brain = require 'brain' -- https://luarocks.org/modules/darkstalker/brain

-- Cache/Store bots
bots = {}

getbot = (destination) ->
  bot = bots[destination]
  if not bot then
    filename = "cache/markov.#{ivar2.network}.#{destination}.sqlite3"
    bot = brain.new(filename, 1)
    bots[destination] = bot

  return bot

markov = (source, destination, arg) =>
  brain = getbot(destination)
  say brain\reply(arg)

return {
  PRIVMSG: {
    '^%pm (.+)$': markov
    '^%pm$': markov
    (source, destination, arg) =>
      brain = getbot(destination)
      nick = source.nick
      if arg\sub(1,1) == '\001' and arg\sub(-1) == '\001'
        arg = arg\sub(9, -2)

      brain\begin_batch!
      brain\learn arg
      -- Close db (commit)
      brain\end_batch!
  }
}
