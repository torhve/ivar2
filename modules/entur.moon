util = require'util'
simplehttp = util.simplehttp
json = util.json
urlEncode = util.urlEncode

client_name = 'ivar2 - entur_irc'
access_token = 'jwt bearer token'

--getToken = (name) ->
--	data = simplehttp{
--		method: 'POST',
--		url: 'https://partner.entur.org/oauth/token',
--		headers: 'content-type: application/json',
--		data: '{
--			"client_id": "ivar2",
--			"client_secret": "raviravi",
--			"audience":"https://api.entur.io",
--			"grant_type":"client_credentials"
--		}'
--	}
--
--	info = json.decode data
--	acess_token = info.access_token
--
formatLeg = (leg) ->
  if leg == 'foot'
    return '👟'
  if leg == 'bus'
    return '🚌'
  if leg == 'water'
    return '🚤'
  if leg == 'metro'
    return '🚇'
  if leg == 'tram'
    return '🚊'
  if leg == 'air'
    return '✈'
  if leg == 'rail'
    return '🚄'
  if leg == 'coach'
    return '🚍'
  return leg

parseDate = (datestr) ->
	year, month, day, hour, min, sec = datestr\match "([^-]+)%-([^-]+)%-([^T]+)T([^:]+):([^:]+):(%d%d)"
	return os.time{
		year: year,
		month: month,
		day: day,
		hour: hour,
		min: min,
		sec: sec,
	}

getStop = (name) ->
  data = simplehttp{
    url:"https://api.entur.io/geocoder/v1/autocomplete?text=#{urlEncode name}&lang=nn",-- nynorsk!
    headers: {
        ['Et-Client-Name']: client_name
    }
  }
  info = json.decode data
  if info
    _, feature = next info.features
    return feature


getRoutes = (source, destination, arg) =>
  if not arg or arg == '' or not arg\match','
      patt = @ChannelCommandPattern('^%pentur (17:00,)<from>,<to>(, 17:00)', "entur", destination)\sub(1)
      patt = patt\gsub('^%^%%p', '!')
      @Msg('privmsg', destination, source, 'Usage: '..patt)
      return

  args = util.split(arg, ',')

  frm_idx = 1
  to_idx = 2
  time_idx = 3
  if args[1]\match '%d'
    frm_idx = 2
    to_idx = 3
    time_idx = 1

  frm = args[frm_idx]
  to = args[to_idx]
  frm = getStop(frm)
  to = getStop(to)

  datetime = ''
  if args[time_idx]
    hour, minute = args[time_idx]\match '(%d%d).*(%d%d)'
    time = os.date("%Y-%m-%dT#{hour}:#{minute}:%S%z")
    datetime = 'dateTime: \\"'..time..'\\" '
    if time_idx == 3
      datetime ..= 'arriveBy: true '

  print(json.encode(frm))
  print(json.encode(to))


  graphql = '{
    trip(
      '..datetime..'
      from: {
        coordinates: {
          latitude: '..frm.geometry.coordinates[2]..',
          longitude:' ..frm.geometry.coordinates[1]..',
        }
      },
      to: {
        coordinates: {
          latitude: '..to.geometry.coordinates[2]..',
          longitude:' ..to.geometry.coordinates[1]..',
        }
      },
      numTripPatterns: 3,
    ) {
   dateTime
   fromPlace {
      name

    }
    toPlace {
      name

    }
    tripPatterns {
      startTime
      endTime
      duration
      waitingTime
      distance
      walkTime
      walkDistance
      legs {
        mode
        fromPlace {
          name
        }
        toPlace {
          name
        }
      }
    }
    }
  }
  '
  graphql = graphql\gsub '\n', ''
  post_data = '{"query":"'..graphql..'","variables":null}'
  print post_data
  data, uri, response = simplehttp {url:'https://api.entur.io/journey-planner/v3/graphql', method:'POST', data:post_data , headers:{['Et-Client-Name']: client_name, ['Content-Type']:'application/json'}}
  if response.status_code != 200
    say data
  else
    out = {}
    print data
    data = json.decode(data).data
    for i, trip in ipairs data.trip.tripPatterns
      time = parseDate trip.startTime
      datetime = os.date '*t', time
      relative = (time - os.time!) / 60

      a_time = parseDate trip.endTime
      a_datetime = os.date '*t', a_time
      legs = {}
      for leg in *trip.legs
        -- don't include the walking to the station, just ugly
        if #legs == 0 and leg.mode == 'foot'
          continue
        legs[#legs+1] = formatLeg(leg.mode)

      -- don't include walking from the station to the destiation, just ugly
      if legs[#legs] == formatLeg('foot') and #legs > 1
        legs[#legs] = nil
      if #legs == 0
        legs[#legs+1] = formatLeg('foot')
      legs = table.concat legs, ''
      out[#out+1] = "#{datetime.hour}:#{string.format('%02d', datetime.min)} (#{string.format('%d', relative)}m) [#{legs}]-> #{a_datetime.hour}:#{string.format('%02d', a_datetime.min)}"

    say table.concat(out, ', ')



PRIVMSG:
  '^%pstop (.*)$': (s, d, a) =>
    say json.encode(getStop(a))
  '^%pentur%s*(.*)$': getRoutes