an = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
ci = 'ⒶⒷⒸⒹⒺⒻⒼⒽⒾⒿⓀⓁⓂⓃⓄⓅⓆⓇⓈⓉⓊⓋⓌⓍⓎⓏⓐⓑⓒⓓⓔⓕⓖⓗⓘⓙⓚⓛⓜⓝⓞⓟⓠⓡⓢⓣⓤⓥⓦⓧⓨⓩ⓪①②③④⑤⑥⑦⑧⑨'
bl = '𝔄𝔅ℭ𝔇𝔈𝔉𝔊ℌℑ𝔍𝔎𝔏𝔐𝔑𝔒𝔓𝔔ℜ𝔖𝔗𝔘𝔙𝔚𝔛𝔜ℨ𝔞𝔟𝔠𝔡𝔢𝔣𝔤𝔥𝔦𝔧𝔨𝔩𝔪𝔫𝔬𝔭𝔮𝔯𝔰𝔱𝔲𝔳𝔴𝔵𝔶𝔷'

an2ci = {}
-- Circled letters are 3 bytes, just use sub string
for i=1, #an
  f = i*3+1-3
  t = i*3
  an2ci[an\sub(i,i)] = ci\sub(f, t)

an2bl = {}
i=1
-- Since blackletters have varying byte length, use the common lua pattern to find multibyte chars
for uchar in string.gfind(bl, "([%z\1-\127\194-\244][\128-\191]*)")
  an2bl[an\sub(i,i)] = uchar
  i = i +1

wireplace = (offset, arg) ->
    html2unicode = require'html'
    s = arg or ''
    t = {}
    for i = 1, #s
      bc = string.byte(s, i, i)
      -- Replace space width ideographic space for fullwidth offset
      if bc == 32 and offset == 0xFEE0
        t[#t + 1] = '\227\128\128'
      elseif bc == 32
        t[#t + 1] = ' '
      elseif bc < 0x80 then
        t[#t + 1] = html2unicode("&#" .. (offset + bc) .. ";")
      else
        t[#t + 1] = s\sub(i, i)

    table.concat(t, "")

remap = (map, s) ->
  table.concat [map[s\sub(i,i)] or s\sub(i,i) for i=1, #s], ''

PRIVMSG:
  '^%pwide (.+)$': (source, destination, arg) =>
    @Msg 'privmsg', destination, source, wireplace(0xFEE0, arg)
  '^%pblackletter (.+)$': (source, destination, arg) =>
    @Msg 'privmsg', destination, source, remap(an2bl, arg)
  '^%pcircled (.+)$': (source, destination, arg) => 
    @Msg 'privmsg', destination, source, remap(an2ci, arg)
