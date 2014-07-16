verifyOwner = (src) ->
  for _,mask in pairs(ivar2.config.owners)
    if src.mask\match(mask)
      return true

verifyChannelOwner = (src, destination) ->
  channel = ivar2.config.channels[destination]

  if type(channel) == 'table' and type(channel.owners) == 'table'
    for _,mask in pairs(channel.owners)
      if src.mask\match(mask)
        return true

JOIN: {
  (source, destination, arg) =>
    if verifyOwner source
      @Log 'info', 'Automatically OPing owner'
      @Mode destination, "+o #{source.nick}"
    elseif verifyChannelOwner source, destination
      @Log 'info', 'Automatically OPing channel owner'
      @Mode destination, "+o #{source.nick}"

}
