-- Module for subscribing to RSS and announce to channels
feedparser = require 'feedparser' -- http://feedparser.luaforge.net/
{:simplehttp, :json, :urlEncode, :bold} = require'util'
html2unicode = require 'html'

moduleName = 'rss'
key = moduleName
store = ivar2.persist

-- Function that add functionality to extract specific information for specific sites
feedSpecific = (link, id, entry) ->
  if link == 'https://comics.io/my/'

    title = entry.summary\match '<h3>(.-)</h3>' or ''
    img, alt = entry.summary\match '<img src="(.-)".- title="(.-)".-></p>'
    return "#{html2unicode title} #{img} #{html2unicode alt}"

  return "#{entry.title} - #{entry.link}"

poll = ->
  for c,_ in pairs(ivar2.channels)
    channelKey = key..':'..c
    channels = store[channelKey] or {}
    -- TODO separate channel logic for polling logic for the cases where
    -- two channels subscribe to the same feed
    for name, channel in pairs(channels)
      lastKey = channelKey .. ':' .. name .. ':last'
      lastmKey = lastKey..'modified'
      last = store[lastKey] or ''
      lastlastModified = store[lastmKey]
      simplehttp {url:channel.url,headers:{'If-Modified-Since':lastlastModified}}, (data, url, response) ->
        lastModified = response.headers['Last-Modified']
        if not lastModified
          lastModified = response.headers['Date']

        store[lastmKey] = lastModified

        -- Unmodified content
        if response.status_code == 304
          -- return from the simplehttp callback
          return

        feed, err = feedparser.parse data
        if err
          ivar2\Log 'error', "#{moduleName}: Error during parsing: <#{err}> data for feed: <#{name}> with URL <#{channel.url}>"
        else
          out = {}
          for i, e in pairs(feed.entries)
            -- Attempt to get a unique entry ID
            guid = e.guid
            if not guid then guid = e.id
            if not guid then guid = e.link
            if not guid
              ivar2\Log 'error', "#{moduleName}: No GUID when parsing entry: <#{e}> data for feed: <#{name}> with URL <#{channel.url}>"

            if guid == last
              break

            table.insert out, "[#{bold name}]: #{feedSpecific(feed.feed.id, feed.feed.link, e)}"

            -- First entry is the newest entry, look for that one on the 
            -- next iteration
            if i == 1
              store[lastKey] = guid

            -- First time
            if last == ''
              break

          if #out > 0
            say "RSS "..table.concat(out, ', ')

subscribe = (source, destination, name, url) =>
  channelKey = key..':'..destination
  channels = store[channelKey] or {}
  channels[name] = {channel:destination, name:name, url:url}
  store[channelKey] = channels
  reply "Ok. Subscribed to #{bold name}"
  poll!

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
ivar2\Timer(moduleName, 300, 300, poll)

PRIVMSG:
  '^%prss latest (.*)': getLatest
  '^%prss subscribe (.-) (.*)': subscribe
  '^%prss unsubscribe (.*)': unsubscribe
  '^%prss list': list
  -- for debugging
  '^%prss poll': poll
