cycleNeeded = (source, destination, arg) =>
  -- Don't care about our own events
  if source.nick == @config.nick
    return
  -- Check if we are the last nick in the channel
  counter = 0
  for nick, meta in pairs @channels[destination].nicks
    if nick == @config.nick
      -- Check if we have op
      for m in *meta.modes
        if m == 'o'
          return
    unless nick == @config.nick or nick == source.nick
      counter += 1

  if counter == 0
    @Log 'info', 'Cycling opless channel %s', destination
    @Part(destination)
    @Join(destination)


{
  PART: {
    cycleNeeded
  }
  QUIT: {
    cycleNeeded
  }
}
