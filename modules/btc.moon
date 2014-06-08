simplehttp = require'simplehttp'
json = require'json'

PRIVMSG: 
  '^%pbtc$': (source, destination, input) =>
    simplehttp 'https://blockchain.info/no/ticker', (data) ->
      if result = json.decode data
        say '\0021\002 BTC is worth \002%s\002 € (~15m)', result["EUR"]["15m"]
