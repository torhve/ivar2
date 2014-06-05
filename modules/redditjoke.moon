json = require'json'
simplehttp = require'simplehttp'
math = require'math'

pick = (data) ->
  children = data.data.children
  thejoke = children[math.random 1, #children]
  title = thejoke.data.title
  joketext = title .. ' ' .. thejoke.data.selftext
  return joketext

joke = (source, destination, subreddit) =>
  simplehttp "http://www.reddit.com/r/#{subreddit}.json", (data) ->
    data = json.decode data
    -- try to find a short joke
    for i=0, 100 do
      joketext = pick data
      if #joketext < 300
        @Msg 'privmsg', destination, source, pick data
        break

PRIVMSG:
  '^%pjoke': (source, destination, arg) =>
    joke @, source, destination, 'jokes'
  '^%pdadjoke': (source, destination, arg) =>
    joke @, source, destination, 'dadjokes'
