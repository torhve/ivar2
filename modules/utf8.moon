html2unicode = require'html'

replace = (offset, arg) ->
    s = arg or ''
    t = {}
    for i = 1, #s
      bc = string.byte(s, i, i)
      if bc == 32 
        t[#t + 1] = '\227\128\128'
      elseif bc < 0x80 then
        t[#t + 1] = html2unicode("&#" .. (offset + bc) .. ";")
      else
        t[#t + 1] = s\sub(i, i)

    table.concat(t, "")

wide = (source, destination, arg) =>
  @Msg 'privmsg', destination, source, replace(0xFEE0, arg)

blackletter = (source, destination, arg) =>
  @Msg 'privmsg', destination, source, replace(0x1D4A3, arg)

PRIVMSG:
  '^%pwide (.+)$': wide 
  '^%pblackletter (.+)$': blackletter 
