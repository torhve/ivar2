util = require'util'
simplehttp = util.simplehttp
json = util.json
urlEncode = util.urlEncode
store = ivar2.persist

moduleName = 'loypernet'


-- Assuming 'pb' (lua-protobuf) and 'simplehttp' are available
pb = require "pb"

-- 1. Define the MVT schema (minimal version for segments)
-- This tells the protobuf library how to read the binary data
pb.load [[
  message Tile {
    message Value {
      optional string string_value = 1;
      optional float float_value = 2;
      optional double double_value = 3;
      optional int64 int_value = 4;
      optional bool bool_value = 7;
    }
    message Feature {
      optional uint64 id = 1;
      repeated uint32 tags = 2 [packed=true];
      optional uint32 type = 3;
      repeated uint32 geometry = 4 [packed=true];
    }
    message Layer {
      required string name = 1;
      repeated Feature features = 2;
      repeated string keys = 3;
      repeated Value values = 4;
      optional uint32 extent = 5;
    }
    repeated Layer layers = 3;
  }
]]

-- Helper to convert the MVT tag pool into a clean MoonScript table
unpackProperties = (layer, feature) ->
    props = {}
    for i = 1, #feature.tags, 2
        key = layer.keys[feature.tags[i] + 1]
        val_wrapper = layer.values[feature.tags[i+1] + 1]
        -- Get the first value from the value union (string, int, or bool)
        _, value = next val_wrapper
        props[key] = value
    return props

-- Main function to fetch segments from a specific tile
getTileSegments = (z, x, y) ->
    ts = os.time! * 1000
    url = "https://api.loyper.net/segments/#{z}/#{x}/#{y}?t=#{ts}"
    
    binary_data = simplehttp url
    
    unless binary_data
        return nil

    -- Decode binary Protobuf to Lua Table
    tile = pb.decode "Tile", binary_data
    unless tile
        return nil

    segments = {}
    
    for layer in *tile.layers
        if layer.name == "segments"
            for feat in *layer.features
                -- Extract metadata (id, lighted, track_id, etc)
                segment_data = unpackProperties layer, feat
                table.insert segments, segment_data

    return segments

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