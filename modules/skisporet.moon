util = require'util'
simplehttp = util.simplehttp
json = util.json
urlEncode = util.urlEncode
store = ivar2.persist

moduleName = 'skisporet'

getSegment = (segmentid) ->
  data = simplehttp "https://beta.skisporet.no/map/segment/#{urlEncode segmentid}?_data=routes%2Fmap%2Fsegment.%24segmentId"
  unless data
    say 'No reply from API'
  data = json.decode(data)
  unless data
    say 'Invalid json'
    return

  segment = data['segment']

  return segment


format = (segment) ->
  days = segment['newestPrep']['days']
  hours = segment['newestPrep']['hours']
  level = segment['newestPrep']['level'] + 1

  colors = {util.green, util.yellow, util.purple, util.teal, util.bold}

  name = nil
  if segment.trails
    name = segment.trails[1].name

  out = {}
  out[#out+1] = "[" .. util.bold name .. "]"
  if days > 0
    out[#out+1] = colors[level] days
    out[#out+1] = 'dagar'
  out[#out+1] = colors[level] hours
  out[#out+1] = 'timar'

  return table.concat(out, ' ')

lookup = (s, d, segmentid) =>
  segment = getSegment segmentid
  say(format(segment))


poll = ->
  for c,_ in pairs(ivar2.channels)
    channelKey = moduleName..':'..c
    channels = store[channelKey] or {}
    for segmentid, channel in pairs(channels)
      lastKey = channelKey .. ':' .. segmentid .. ':last'
      last = store[lastKey] or 99 -- just use a high number as initial value, so it gets announced first time
      segment = getSegment segmentid
      level = segment['newestPrep']['level'] + 1
      -- save the last prep level, and compare to that
      if level < last
        msg = format segment
        ivar2\Msg 'privmsg', channel.channel, nil, msg
      store[lastKey] = level

unsubscribe = (source, destination, segmentid) =>
  channelKey = moduleName..':'..destination
  channels = store[channelKey] or {}
  unless channels[segmentid]
    reply "Wasn't subscribed. But, sure."
  else
    channels[segmentid] = nil
    store[channelKey] = channels
    lastKey = channelKey .. ':' .. segmentid .. ':last'
    store[lastKey] = nil
    reply "Ok. Stopped caring about #{bold segmentid}"

list = (source, destination) =>
  channelKey = moduleName..':'..destination
  channels = store[channelKey] or {}
  out = {}
  for name, game in pairs(channels)
      out[#out+1] = name
  say "Subscribed to: #{table.concat(out, ', ')}"

add = (s, destination, segmentid) =>
  channelKey = moduleName..':'..destination
  channels = store[channelKey] or {}
  channels[segmentid] = {channel:destination, segmentid:segmentid}
  store[channelKey] = channels
  reply "Ok. Subscribed to #{util.bold segmentid}"
  poll!

ivar2\Timer(moduleName, 60*60, 60*60, poll)

PRIVMSG:
  '^%pprepp (.*)$': lookup
  '^%ppreppevarsel (.*)$': add
  '^%ppreppevarselremove (.*)': unsubscribe
  '^%ppreppevarsellist': list
