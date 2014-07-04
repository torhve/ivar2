PRIVMSG:
  '^%pexcuse': (source, destination) =>
    ivar2.util.simplehttp 'http://www.programmerexcuses.com/', (html) ->
      cruft, match = html\match[[<center(.*)>(.-)</a></center>]]
      if match
        say match
