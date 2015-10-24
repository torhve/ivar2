util = require 'util'


hex_to_char = (x) ->
  string.char(tonumber(x, 16))

unescape = (url) ->
  url\gsub("%%(%x%x)", hex_to_char)

handlers = {
  push: (repo, destination, json) ->
    branch = util.bold(json.ref\gsub 'refs/heads/', '')
    for i, c in pairs(json.commits)
      if i > 3
        break
      message = c.message\gsub '\n.*', ''
      if i == 1
        message = message .. ' ' .. json.compare
      ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: #{branch}, #{util.nonickalertword c.author.username}: #{message}"
    if #json.commits >= 4
      ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: #{branch}, #{#json.commits-3} more commits not displayed."
  watch: (repo, destination, json) ->
    action = json.action
    if action == 'started'
      ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: #{util.nonickalertword json.sender.login}: +1 ★ (Total: #{json.repository.stargazers_count})"
    else
      ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: #{util.nonickalertword json.sender.login}: #{action} watching"
  ping: (repo, destination, json) ->
    ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: ping"
  commit_comment: (repo, destination, json) ->
    --commenter = json.comment.user.login
    body = json.comment.body
    ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: #{util.nonickalertword json.sender.login}: commented #{body}"
  pull_request: (repo, destination, json) ->
    action = json.action
    number = util.bold json.number
    ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: #{util.nonickalertword json.sender.login}: #{action} PR ##{number}: #{json.pull_request.title} #{json.pull_request.html_url}"
  issues: (repo, destination, json) ->
    action = json.action
    nr = util.bold json.issue.number
    ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: #{util.nonickalertword json.sender.login}: #{action} issue ##{nr}: #{json.issue.title} #{json.issue.html_url}"
  issue_comment: (repo, destination, json) ->
    action = json.action
    nr = util.bold json.issue.number
    ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: #{util.nonickalertword json.sender.login}: comment on issue ##{nr}: #{json.comment.body} #{json.issue.html_url}"
  fork: (repo, destination, json) ->
    ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: #{util.nonickalertword json.sender.login}: forked to #{json.forkee.html_url}"
  create: (repo, destination, json) ->
    ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: #{util.nonickalertword json.sender.login}: created #{json.ref_type} #{util.bold json.ref}"
  delete: (repo, destination, json) ->
    ivar2\Msg 'privmsg', destination, nil, "[#{repo}]: #{util.nonickalertword json.sender.login}: deleted #{json.ref_type} #{util.bold json.ref}"
  gollum: (repo, destination, json) ->
    return
  release: (repo, destination, json) ->
    return
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
