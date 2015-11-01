util = require 'util'

rtcolor = (score) ->
  if not tonumber(score) then return score
  if tonumber(score) > 59
    return util.red(string.format("%s%%", score))
  else
    return util.green(string.format("%s%%", score))

metacolor = (score) ->
  if not tonumber(score) then return score
  if tonumber(score) >= 60
    return util.green(string.format("%s%%", score))
  elseif tonumber(score) >= 40
    return util.yellow(string.format("%s%%", score))
  else
    return util.red(string.format("%s%%", score))

omdbfetch = (arg, cb) ->
  util.simplehttp "http://www.omdbapi.com/?t=#{util.urlEncode arg}&y=&plot=short&r=json&tomatoes=true", (data) ->
    js = util.json.decode(data)
    if js and not js.Error
      cb(js)
    else
      say('%s', js.Error)

omdb = (source, destination, arg) =>
  omdbfetch arg, (js) ->
    say "[#{util.bold js.Title}] (#{js.Year}) #{js.Genre} Metacritic: [#{metacolor js.Metascore}] RT: [#{rtcolor js.tomatoMeter} / #{rtcolor js.tomatoUserMeter}] IMDB: [#{js.imdbRating}] http://www.imdb.com/title/#{js.imdbID} Actors: [#{js.Actors}] #{js.Plot}"

plot = (source, destination, arg) =>
  omdbfetch arg, (js) ->
    say "[#{util.bold js.Title}] (#{js.Year}) #{js.Plot}"

PRIVMSG:
  '^%pomdb (.+)': omdb
  '^%pimdb (.+)': omdb
  '^%prt (.+)': omdb
  '^%pmovie (.+)': omdb
  '^%pplot (.+)': plot
