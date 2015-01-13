util = require 'util'

ivar2.webserver.regUrl '/github/(.*)', (req, res) ->
  destination = req.url\match('/github/(.+)/?$')
  destination = destination\gsub '%%23', '#'
  json = util.json.decode(req.body)

  repo = json.repository.full_name
  branch = json.ref\gsub 'refs/heads/', ''

  for c in *json.commits
    ivar2\Msg 'privmsg', destination, nil, "#{repo}: #{branch} #{c.author.username} #{c.message}"

  res\set_status(200)
  res\set_header('Content-Type', 'text/plain')
  res\set_body('ok')
  res\send()

return {}
