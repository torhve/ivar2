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

imdbcolor = (score) ->
  if not tonumber(score) then return score
  if tonumber(score) >= 8.0
    return util.green(string.format("%.1f", score))
  elseif tonumber(score) >= 6.0
    return util.yellow(string.format("%.1f", score))
  elseif tonumber(score) >= 4.0
    return util.orange(string.format("%.1f", score))
  else
    return util.red(string.format("%.1f", score))

omdbfetch = (say, arg, year, cb) ->
  is_id = arg\match '^tt%d+$'
  url = if is_id
    "http://www.omdbapi.com/?i=#{arg}&plot=short&r=json&tomatoes=true&apikey=#{ivar2.config.omdbAPIKey}"
  else
    "http://www.omdbapi.com/?t=#{util.urlEncode arg}&y=#{year or ''}&plot=short&r=json&tomatoes=true&apikey=#{ivar2.config.omdbAPIKey}"
  util.simplehttp url, (data) ->
    js = util.json.decode(data)
    if js and not js.Error
      cb(js)
    else
      say('%s', (js and js.Error) or 'unknown error')

omdb = (source, destination, arg) =>
  render = (js) ->
    say "[#{util.bold js.Title}] (#{js.Year}) #{js.Genre} Metacritic: [#{metacolor js.Metascore}] RT: [#{rtcolor js.tomatoMeter} / #{rtcolor js.tomatoUserMeter}] IMDB: [#{imdbcolor js.imdbRating}] http://www.imdb.com/title/#{js.imdbID} Actors: [#{js.Actors}] #{js.Plot}"

  if arg\match '^tt%d+$'
    omdbfetch say, arg, nil, render
  else
    title = arg
    year, _ = arg\match('([0-9][0-9][0-9][0-9])')
    if year
      title = title\gsub('[0-9][0-9][0-9][0-9]', '')
    omdbfetch say, title, year, render

plot = (source, destination, arg) =>
  omdbfetch say, arg, nil, (js) ->
    say "[#{util.bold js.Title}] (#{js.Year}) #{js.Plot}"

PRIVMSG:
  '^%pomdb (.+)': omdb
  '^%pimdb (.+)': omdb
  '^%prt (.+)': omdb
  '^%pmovie (.+)': omdb
  '^%pplot (.+)': plot
