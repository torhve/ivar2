util = require'util'
html2unicode = require'html'

an = [[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789,.?!"'`()[]{}<>&_]]
charmaps = {
ci: 'ⒶⒷⒸⒹⒺⒻⒼⒽⒾⒿⓀⓁⓂⓃⓄⓅⓆⓇⓈⓉⓊⓋⓌⓍⓎⓏⓐⓑⓒⓓⓔⓕⓖⓗⓘⓙⓚⓛⓜⓝⓞⓟⓠⓡⓢⓣⓤⓥⓦⓧⓨⓩ⓪①②③④⑤⑥⑦⑧⑨'
bl: '𝔄𝔅ℭ𝔇𝔈𝔉𝔊ℌℑ𝔍𝔎𝔏𝔐𝔑𝔒𝔓𝔔ℜ𝔖𝔗𝔘𝔙𝔚𝔛𝔜ℨ𝔞𝔟𝔠𝔡𝔢𝔣𝔤𝔥𝔦𝔧𝔨𝔩𝔪𝔫𝔬𝔭𝔮𝔯𝔰𝔱𝔲𝔳𝔴𝔵𝔶𝔷'
ud: [[∀BƆDƎℲפHIſK˥WNOԀQRS┴∩ΛMX⅄Zɐqɔpǝɟƃɥᴉɾʞlɯuodbɹsʇnʌʍxʎz0ƖᄅƐㄣϛ9ㄥ86'˙¿¡,,,)(][}{><⅋‾]]
nc: [[🅐🅑🅒🅓🅔🅕🅖🅗🅘🅙🅚🅛🅜🅝🅞🅟🅠🅡🅢🅣🅤🅥🅦🅧🅨🅩🅐🅑🅒🅓🅔🅕🅖🅗🅘🅙🅚🅛🅜🅝🅞🅟🅠🅡🅢🅣🅤🅥🅦🅧🅨🅩⓿]]
sq: [[🄰🄱🄲🄳🄴🄵🄶🄷🄸🄹🄺🄻🄼🄽🄾🄿🅀🅁🅂🅃🅄🅅🅆🅇🅈🅉🄰🄱🄲🄳🄴🄵🄶🄷🄸🄹🄺🄻🄼🄽🄾🄿🅀🅁🅂🅃🅄🅅🅆🅇🅈🅉0123456789,⊡]]
ns: [[🅰🅱🅲🅳🅴🅵🅶🅷🅸🅹🅺🅻🅼🅽🅾🅿🆀🆁🆂🆃🆄🆅🆆🆇🆈🆉🅰🅱🅲🅳🅴🅵🅶🅷🅸🅹🅺🅻🅼🅽🅾🅿🆀🆁🆂🆃🆄🆅🆆🆇🆈🆉]]
ds: [[𝔸𝔹ℂ𝔻𝔼𝔽𝔾ℍ𝕀𝕁𝕂𝕃𝕄ℕ𝕆ℙℚℝ𝕊𝕋𝕌𝕍𝕎𝕏𝕐ℤ𝕒𝕓𝕔𝕕𝕖𝕗𝕘𝕙𝕚𝕛𝕜𝕝𝕞𝕟𝕠𝕡𝕢𝕣𝕤𝕥𝕦𝕧𝕨𝕩𝕪𝕫𝟘𝟙𝟚𝟛𝟜𝟝𝟞𝟟𝟠𝟡]]
bo: [[𝐀𝐁𝐂𝐃𝐄𝐅𝐆𝐇𝐈𝐉𝐊𝐋𝐌𝐍𝐎𝐏𝐐𝐑𝐒𝐓𝐔𝐕𝐖𝐗𝐘𝐙𝐚𝐛𝐜𝐝𝐞𝐟𝐠𝐡𝐢𝐣𝐤𝐥𝐦𝐧𝐨𝐩𝐪𝐫𝐬𝐭𝐮𝐯𝐰𝐱𝐲𝐳𝟎𝟏𝟐𝟑𝟒𝟓𝟔𝟕𝟖𝟗]]
bi: [[𝑨𝑩𝑪𝑫𝑬𝑭𝑮𝑯𝑰𝑱𝑲𝑳𝑴𝑵𝑶𝑷𝑸𝑹𝑺𝑻𝑼𝑽𝑾𝑿𝒀𝒁𝒂𝒃𝒄𝒅𝒆𝒇𝒈𝒉𝒊𝒋𝒌𝒍𝒎𝒏𝒐𝒑𝒒𝒓𝒔𝒕𝒖𝒗𝒘𝒙𝒚𝒛0123456789]]
bs: [[𝓐𝓑𝓒𝓓𝓔𝓕𝓖𝓗𝓘𝓙𝓚𝓛𝓜𝓝𝓞𝓟𝓠𝓡𝓢𝓣𝓤𝓥𝓦𝓧𝓨𝓩𝓪𝓫𝓬𝓭𝓮𝓯𝓰𝓱𝓲𝓳𝓴𝓵𝓶𝓷𝓸𝓹𝓺𝓻𝓼𝓽𝓾𝓿𝔀𝔁𝔂𝔃]]
pt: [[⒜⒝⒞⒟⒠⒡⒢⒣⒤⒥⒦⒧⒨⒩⒪⒫⒬⒭⒮⒯⒰⒱⒲⒳⒴⒵⒜⒝⒞⒟⒠⒡⒢⒣⒤⒥⒦⒧⒨⒩⒪⒫⒬⒭⒮⒯⒰⒱⒲⒳⒴⒵0⑴⑵⑶⑷⑸⑹⑺⑻⑼]]
}
codepoints = (str) ->
  str\gmatch("[%z\1-\127\194-\244][\128-\191]*")


-- Construct a table which can be used for lookup replacement later
-- Iterate over normal ascii and find counterparts in the weirdo strings as substrings
maps = {}
for charmap, chars in pairs charmaps
  i = 1
  maps[charmap] = {}
  for uchar in util.utf8.chars(chars)
    maps[charmap][an\sub(i,i)] = uchar
    i = i +1

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
    say wireplace(0xFEE0, arg)
  '^%pblackletter (.+)$': (source, destination, arg) =>
    say remap(maps.bl, arg)
  '^%pcircled (.+)$': (source, destination, arg) =>
    say remap(maps.ci, arg)
  '^%pzalgo (.+)$': (source, destination, arg) =>
    say zalgo(arg, 7)
  '^%pupsidedown (.+)$': (source, destination, arg) =>
    say remap(maps.ud, util.utf8.reverse(arg))
  '^%pflip (.+)$': (source, destination, arg) =>
    say remap(maps.ud, arg)
  '^%pthrow (.+)$': (source, destination, arg) =>
    say "（╯°□°）╯︵ #{remap maps.ud, util.utf8.reverse(arg)}"
  '^%pparanthesized (.+)$': (source, destination, arg) =>
    say remap(maps.pt, arg)
  '^%pnegcircle (.+)$': (source, destination, arg) =>
    say remap(maps['nc'], arg)
  '^%psquare (.+)$': (source, destination, arg) =>
    say remap(maps.sq, arg)
  '^%pnegsquare (.+)$': (source, destination, arg) =>
    say remap(maps.ns, arg)
  '^%pdoublestruck (.+)$': (source, destination, arg) =>
    say remap(maps.ds, arg)
  '^%pubold (.+)$': (source, destination, arg) =>
    say remap(maps.bo, arg)
  '^%pbolditalic (.+)$': (source, destination, arg) =>
    say remap(maps.bi, arg)
  '^%pboldscript (.+)$': (source, destination, arg) =>
    say remap(maps.bs, arg)
  '^%putfuk (.+)$': (source, destination, arg) =>
    keys = [x for x,_ in pairs(maps)]
    say table.concat([remap(maps[keys[math.random(#keys)]], letter) for letter in codepoints(arg)])
