
PRIVMSG:
  '^%pmannen$': =>
    ivar2.util.simplehttp 'http://www.vondess.com/mannen/api', (data) ->
      res = ivar2.util.json.decode data
      if res.falt_ned
        say 'Mannen har falt ned. Fucking finally.'
      else unless res.falt_ned
        say 'Nei. Mannen har ikke falt ned.'
