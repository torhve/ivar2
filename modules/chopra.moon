simplehttp = require 'simplehttp'

PRIVMSG:
  '^%pchopra$': (source, destination) =>
    simplehttp 'http://www.wisdomofchopra.com/iframe.php', (html) ->
       quote = html\match [[<meta property="og:description" content="'(.+)' www.wisdomofchopra.com" />]]
       if quote
         say quote
