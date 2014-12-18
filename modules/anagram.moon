html2unicode = require'html'

PRIVMSG:
  '^%panagram (.+)$': (s, d, arg) =>
    ivar2.util.simplehttp "http://www.wordsmith.org/anagram/anagram.cgi?t=50&anagram=" .. ivar2.util.urlEncode(arg), (s) ->
      s = s\match "(Displaying%s.-)</?[Pp][ />]"
      unless s
        return say "Did not find result"
      s = s\gsub "<[Bb][Rr][ />]", ", "
      -- Strip tags
      s = s\gsub "%b<>", ""
      say html2unicode(s)\gsub(":%s*,", ":")\gsub(",%s*$", "")


