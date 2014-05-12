html2unicode = require'html'
math = require'math'

an = [[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789,.?!"'`()[]{}<>&_]]
ci = 'ⒶⒷⒸⒹⒺⒻⒼⒽⒾⒿⓀⓁⓂⓃⓄⓅⓆⓇⓈⓉⓊⓋⓌⓍⓎⓏⓐⓑⓒⓓⓔⓕⓖⓗⓘⓙⓚⓛⓜⓝⓞⓟⓠⓡⓢⓣⓤⓥⓦⓧⓨⓩ⓪①②③④⑤⑥⑦⑧⑨'
bl = '𝔄𝔅ℭ𝔇𝔈𝔉𝔊ℌℑ𝔍𝔎𝔏𝔐𝔑𝔒𝔓𝔔ℜ𝔖𝔗𝔘𝔙𝔚𝔛𝔜ℨ𝔞𝔟𝔠𝔡𝔢𝔣𝔤𝔥𝔦𝔧𝔨𝔩𝔪𝔫𝔬𝔭𝔮𝔯𝔰𝔱𝔲𝔳𝔴𝔵𝔶𝔷'
ud = [[∀BƆDƎℲפHIſK˥WNOԀQRS┴∩ΛMX⅄Zɐqɔpǝɟƃɥᴉɾʞlɯuodbɹsʇnʌʍxʎz0ƖᄅƐㄣϛ9ㄥ86'˙¿¡,,,)(][}{><⅋‾]]

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


an2ud = {}
i=1
for uchar in string.gfind(ud, "([%z\1-\127\194-\244][\128-\191]*)")
  an2ud[an\sub(i,i)] = uchar
  i = i +1

codepoints = (str) ->
  str\gmatch("[%z\1-\127\194-\244][\128-\191]*")

unichr = (n) ->
  html2unicode('&#x%x;'\format(n))

wireplace = (offset, arg) ->
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

zalgo = (text, intensity=50) ->
  zalgo_chars = {}
  for i=0x0300, 0x036f
    zalgo_chars[i-0x2ff] = unichr(i)

  zalgo_chars[#zalgo_chars + 1] = unichr(0x0488)
  zalgo_chars[#zalgo_chars + 0] = unichr(0x0489)

  zalgoized = {}
  for letter in codepoints(text)
    zalgoized[#zalgoized + 1] = letter
    zalgo_num = math.random(1, intensity)
    for i=1, zalgo_num
      zalgoized[#zalgoized + 1] = zalgo_chars[math.random(1, #zalgo_chars)]
  table.concat(zalgoized)


PRIVMSG:
  '^%pwide (.+)$': (source, destination, arg) =>
    @Msg 'privmsg', destination, source, wireplace(0xFEE0, arg)
  '^%pblackletter (.+)$': (source, destination, arg) =>
    @Msg 'privmsg', destination, source, remap(an2bl, arg)
  '^%pcircled (.+)$': (source, destination, arg) => 
    @Msg 'privmsg', destination, source, remap(an2ci, arg)
  '^%pzalgo (.+)$': (source, destination, arg) => 
    @Msg 'privmsg', destination, source, zalgo(arg, 10)
  '^%pupsidedown (.+)$': (source, destination, arg) => 
    @Msg 'privmsg', destination, source, remap(an2ud, arg)
