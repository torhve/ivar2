util = require'util'
json = util.json
simplehttp = util.simplehttp

pick = (data) ->
  children = data.data.children
  thejoke = children[math.random 1, #children]
  title = thejoke.data.title
  joketext = title .. ' ' .. thejoke.data.selftext
  return joketext

joke = (subreddit, cb) ->
  simplehttp "http://www.reddit.com/r/#{subreddit}.json", (data) ->
    data = json.decode data
    -- try to find a short joke
    for i=0, 100 do
      joketext = pick data
      if #joketext < 300
        return cb joketext

PRIVMSG:
  '^%pjoke': (source, destination, arg) =>
    joke 'jokes', (text) ->
      say text
  '^%pdadjoke': (source, destination, arg) =>
    joke 'dadjokes', (text) ->
      say text
