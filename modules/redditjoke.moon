json = require'json'
simplehttp = require'simplehttp'
math = require'math'

PRIVMSG:
  '^%pjoke': (source, destination, arg) =>
    simplehttp 'http://www.reddit.com/r/jokes.json', (data) ->
      data = json.decode data
      children = data.data.children
      joke = children[math.random 1, #children]
      title = joke.data.title
      joketext = title .. ' ' .. joke.data.selftext
      @Msg 'privmsg', destination, source, joketext
