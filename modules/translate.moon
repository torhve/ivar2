-- google translate
json = require'json'
simplehttp = require'simplehttp'

languages =
  "af": "Afrikaans",
  "sq": "Albanian",
  "ar": "Arabic",
  "az": "Azerbaijani",
  "eu": "Basque",
  "bn": "Bengali",
  "be": "Belarusian",
  "bg": "Bulgarian",
  "ca": "Catalan",
  "zh-CN": "Simplified Chinese",
  "zh-TW": "Traditional Chinese",
  "hr": "Croatian",
  "cs": "Czech",
  "da": "Danish",
  "nl": "Dutch",
  "en": "English",
  "eo": "Esperanto",
  "et": "Estonian",
  "tl": "Filipino",
  "fi": "Finnish",
  "fr": "French",
  "gl": "Galician",
  "ka": "Georgian",
  "de": "German",
  "el": "Greek",
  "gu": "Gujarati",
  "ht": "Haitian Creole",
  "iw": "Hebrew",
  "hi": "Hindi",
  "hu": "Hungarian",
  "is": "Icelandic",
  "id": "Indonesian",
  "ga": "Irish",
  "it": "Italian",
  "ja": "Japanese",
  "kn": "Kannada",
  "ko": "Korean",
  "la": "Latin",
  "lv": "Latvian",
  "lt": "Lithuanian",
  "mk": "Macedonian",
  "ms": "Malay",
  "mt": "Maltese",
  "no": "Norwegian",
  "fa": "Persian",
  "pl": "Polish",
  "pt": "Portuguese",
  "ro": "Romanian",
  "ru": "Russian",
  "sr": "Serbian",
  "sk": "Slovak",
  "sl": "Slovenian",
  "es": "Spanish",
  "sw": "Swahili",
  "sv": "Swedish",
  "ta": "Tamil",
  "te": "Telugu",
  "th": "Thai",
  "tr": "Turkish",
  "uk": "Ukrainian",
  "ur": "Urdu",
  "vi": "Vietnamese",
  "cy": "Welsh",
  "yi": "Yiddish"

getCode = (language) ->
  for code, lang in pairs languages
    if lang\lower! == language\lower!
      return code
    else if language\lower! == code\lower!
      return code

urlEncode = (str, space) ->
  space = space or '+'
  str = tostring(str)

  str = str\gsub '([^%w ])', (c) ->
    string.format  "%%%02X", string.byte(c) 
  return str\gsub(' ', space)


buildQueryStr = (tbl) ->
  out = {}
  for k,v in pairs tbl
    table.insert out, k..'='..urlEncode(v)
  table.concat out, '&'

translate = (source, destination, origin, target, term) =>
  origin = getCode(origin) or 'auto'
  target = getCode(target) or 'en'
  args =
    client: 'p'
    hl: 'en'
    multires: 1
    sc: 1
    sl: origin
    ssel: 0
    tl: target
    tsel: 0
    uptl: "en"
    text: term

  simplehttp "https://translate.google.com/translate_a/t?" .. buildQueryStr(args), (data) ->
    if #data > 4
      parsed = json.decode data
      language = parsed.src
      out = table.concat [k.trans for k in *parsed.sentences]
      if #out > 0
        @Msg 'privmsg', destination, source, "\002#{languages[target]}\002: #{out}"

PRIVMSG:
  '^%ptranslate ([%w%-]+) ([%w%-]+) (.*)$': translate
