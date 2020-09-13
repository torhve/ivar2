util = require 'util'
hmac = require "openssl.hmac" -- from luaossl

hex_to_char = (x) ->
  string.char(tonumber(x, 16))

tohex = (b) ->
  x = ""
  for i = 1, #b do
    x = x .. string.format("%.2x", string.byte(b, i))
  return 'sha1='..x

unescape = (url) ->
  url\gsub("%%(%x%x)", hex_to_char)

acolor = (action) ->
  if action == 'opened'
    return util.green action
  if action == 'closed'
    return util.red action
  if action == 'deleted'
    return util.red action
  if action == 'synchronize'
    return util.purple action
  if action == 'labeled'
    return util.yellow action

  return action

strip_email = (text) ->
  out = {}
  for line in text\gmatch'[^\r\n]+'
    unless line\match'^%s*>'
      out[#out+1] = line
  table.concat out

handlers = {
  push: (repo, destination, json) ->
    branch = util.bold(json.ref\gsub 'refs/heads/', '')
    out = {"[#{repo}]: #{branch}"}
    lastauthor = ''
    for i, c in ipairs json.commits
      if i > 3
        break
      message = c.message\gsub '\n.*', ''
      if i == 1
        message ..= ' ' .. json.compare
      author = ''
      if c.author.username ~= lastauthor
        author = "<#{util.nonickalertword c.author.username}>"
      out[#out+1] = "#{author} #{message}\n"
      lastauthor = c.author.username
    if #json.commits >= 4
      out[#out+1] = "#{#json.commits-3} more commits not displayed."
    table.concat out, ' '
  watch: (repo, destination, json) ->
    action = json.action
    if action == 'started'
      "[#{repo}]: #{util.nonickalertword json.sender.login}: +1 #{util.yellow '★'} (Total: #{json.repository.stargazers_count})"
    else
      "[#{repo}]: #{util.nonickalertword json.sender.login}: #{action} watching"
  ping: (repo, destination, json) ->
    "[#{repo}]: ping"
  commit_comment: (repo, destination, json) ->
    --commenter = json.comment.user.login
    body = json.comment.body
    "[#{repo}]: <#{util.nonickalertword json.sender.login}> #{body}"
  pull_request: (repo, destination, json) ->
    action = acolor json.action
    number = util.bold json.number
    "[#{repo}]: #{util.nonickalertword json.sender.login}: #{action} PR ##{number}: #{json.pull_request.title} #{json.pull_request.html_url}"
  pull_request_review_comment: (repo, destination, json) ->
    body = json.comment.body
    number = util.bold json.pull_request.number
    "[#{repo}]: PR ##{number} <#{util.nonickalertword json.sender.login}> #{body}"
  pull_request_review: (repo, destinatino, json) ->
    body = json.review.body or ''
    if body == util.json.null
      body = ''
    number = util.bold json.pull_request.number
    state = json.review.state\gsub('_', ' ')
    if state == 'commented'
      -- Displaying that a review is in state comment is just noise
      return
    "[#{repo}]: PR ##{number} Review #{state} <#{util.nonickalertword json.sender.login}> #{body}"
  issues: (repo, destination, json) ->
    action = acolor json.action
    nr = util.bold json.issue.number
    extra = ''
    if json.action == 'labeled' -- Add label and color if action is label
      extra = "#{json.label.name}, ##{json.label.color} "
    "[#{repo}]: #{util.nonickalertword json.sender.login}: #{action} issue ##{nr}: #{extra}#{json.issue.title} #{json.issue.html_url}"
  issue_comment: (repo, destination, json) ->
    action = acolor json.action
    nr = util.bold json.issue.number
    "[#{repo}]: Issue ##{nr} <#{util.nonickalertword json.sender.login}> #{strip_email json.comment.body} #{json.issue.html_url}"
  fork: (repo, destination, json) ->
    "[#{repo}]: #{util.nonickalertword json.sender.login}: forked to #{json.forkee.html_url}"
  create: (repo, destination, json) ->
    "[#{repo}]: #{util.nonickalertword json.sender.login}: created #{json.ref_type} #{util.bold json.ref}"
  delete: (repo, destination, json) ->
    "[#{repo}]: #{util.nonickalertword json.sender.login}: deleted #{json.ref_type} #{util.bold json.ref}"
  gollum: (repo, destination, json) ->
    return
  release: (repo, destination, json) ->
    return
  status: (repo, destination, json) -> -- Travis CI event
    -- NYI
    return

}

ivar2.webserver.regUrl '/github/(.*)', (req, res) =>
  destination = req.url\match('/github/(.+)/?$')
  destination = unescape(destination)
  json = util.json.decode(req.body)

  repo = json.repository.full_name

  secret = req.headers['x-hub-signature']
  if secret
    confsecret = ivar2.config.channels[destination].githubSecret
    if not confsecret
      ivar2\Log('error', 'github event, no secret configured for destination: %s', destination)
      return
    mysum = tohex(hmac.new(confsecret)\final(req.body))
    if tostring(mysum) != tostring(secret)
      ivar2\Log('error', 'github event with invalid signature for destination: %s', destination)
      res\append ':status', "403"
      res\append 'Content-Type', 'text/plain'
      req\write_headers(res, false, 30)
      req\write_body_from_string('invalid secret', 30)
      return

  event = req.headers['x-github-event']
  handler = handlers[event]
  if handler
    if message = handler(repo, destination, json)
      ivar2\Msg 'privmsg', destination, nil, message
  else
    ivar2\Log('error', 'Unknown github event: %s', event)

  res\append ':status', "200"
  res\append 'Content-Type', 'text/plain'
  req\write_headers(res, false, 30)
  req\write_body_from_string('ok', 30)
