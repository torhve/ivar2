util = require 'util'


hex_to_char = (x) ->
  string.char(tonumber(x, 16))

unescape = (url) ->
  url\gsub("%%(%x%x)", hex_to_char)

handlers = {
  push: (repo, destination, json) ->
    branch = json.ref\gsub 'refs/heads/', ''
    for i, c in pairs(json.commits)
      if i > 3
        break
      message = c.message\gsub '\n.*', ''
      ivar2\Msg 'privmsg', destination, nil, "#{repo}: #{branch}, #{c.author.username}: #{message} #{c.url}"
    if #json.commits > 3
      ivar2\Msg 'privmsg', destination, nil, "#{repo}: #{branch}, #{#json.commits-3} more commits not displayed."
  watch: (repo, destination, json) ->
    action = json.action
    ivar2\Msg 'privmsg', destination, nil, "#{repo}: #{json.sender.login}: #{action} watching"

}

ivar2.webserver.regUrl '/github/(.*)', (req, res) ->
  destination = req.url\match('/github/(.+)/?$')
  destination = unescape(destination)
  json = util.json.decode(req.body)

  repo = json.repository.full_name

  event = req.headers['X-GitHub-Event']
  handler = handlers[event]
  if handler
    handler(repo, destination, json)
  else
    ivar2\Log('error', 'Unknown github event: %s', event)

  res\set_status(200)
  res\set_header('Content-Type', 'text/plain')
  res\set_body('ok')
  res\send()

return {}
