-- Module for announcing new videos to a youtube channel
-- Requires a developer API key set in configuration
{:simplehttp, :json, :urlEncode, :bold} = require'util'

moduleName = 'youtube'
key = moduleName
store = ivar2.persist

getItems = (channel, cb) ->
  url = "https://www.googleapis.com/youtube/v3/channels?part=contentDetails&forUsername=%s&key=%s"
  simplehttp url\format(urlEncode(channel), ivar2.config.youtubeAPIKey), (data) ->
    js = json.decode(data)
    if not (js and js.items and js.items[1] and js.items[1].contentDetails)
      ivar2\Log 'info', 'youtube: No items for youtube channel '..tostring(channel)
      return
    playlistId = js.items[1].contentDetails.relatedPlaylists.uploads
    if playlistId
      url = "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId=%s&key=%s"
      simplehttp url\format(playlistId, ivar2.config.youtubeAPIKey), (pldata) ->
        pljs = json.decode(pldata)
        cb(pljs.items)

getLatest = (source, destination, channel) =>
  getItems channel, (items) ->
    for item in *items
      if item.kind == "youtube#playlistItem"
        s = item.snippet
        videoId = s.resourceId.videoId
        say "[#{bold s.channelTitle}] http://youtu.be/#{videoId} #{s.title}"
        return

checkChannels = ->
  for c,_ in pairs(ivar2.channels)
    channelKey = key..':'..c
    channels = store[channelKey] or {}
    for name, channel in pairs(channels)
      lastKey = channelKey .. ':' .. name .. ':last'
      last = store[lastKey] or ''
      getItems name, (items) ->
        for item in *items
          if item.kind == "youtube#playlistItem"
            s = item.snippet
            videoId = s.resourceId.videoId
            -- Check if we already announced
            if videoId == last
              return
            -- Store first video in playlist as a marker
            if s.position == 0
              store[lastKey] = videoId
            ivar2\Msg 'privmsg', channel.channel, nil, "[#{bold s.channelTitle}] http://youtu.be/#{videoId} — #{s.title}"
            -- If we're newly subscribed, only tell once
            if last == ''
              return

subscribe = (source, destination, name) =>
  channelKey = key..':'..destination
  channels = store[channelKey] or {}
  channels[name] = {channel:destination, name:name}
  store[channelKey] = channels
  reply "Ok. Subscribed to #{bold name}"
  checkChannels()

unsubscribe = (source, destination, name) =>
  channelKey = key..':'..destination
  channels = store[channelKey] or {}
  unless channels[name]
    reply "Wasn't subscribed. But, sure."
  else
    channels[name] = nil
    store[channelKey] = channels
    lastKey = channelKey .. ':' .. name .. ':last'
    store[lastKey] = nil
    reply "Ok. Stopped caring about #{bold name}"

list = (source, destination) =>
  channelKey = key..':'..destination
  channels = store[channelKey] or {}
  out = {}
  for name, game in pairs(channels)
      out[#out+1] = name
  say "Subscribed to: #{table.concat(out, ', ')}"

-- Start the subscribe poller
ivar2\Timer('youtube', 300, 300, checkChannels)

PRIVMSG:
  '^%pyoutube latest (.*)': getLatest
  '^%pyoutube subscribe (.*)': subscribe
  '^%pyoutube unsubscribe (.*)': unsubscribe
  '^%pyoutube list': list
