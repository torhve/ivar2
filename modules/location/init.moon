{:simplehttp, :json, :urlEncode} = require'util'
html2unicode = require 'html'
hex_to_char = (x) ->
  string.char(tonumber(x, 16))

urlBase = '/location/'

unescape = (url) ->
  url\gsub("%%(%x%x)", hex_to_char)

safe = (fn) ->
  f, ext = fn\match'^(.*)%.(.-)$'
  f = f\gsub '[^%w%-]', ''
  return f..'.'..ext

ivar2.webserver.regUrl "/location/(.*)$", (req, res) =>
  send = (body, code, content_type) ->
    if not code then code = "200"
    if not content_type then content_type = 'text/html'
    res\append ':status', code
    res\append 'content-type', content_type
    res\append 'content-length', tostring(#body)
    req\write_headers(res, false, 30)
    req\write_body_from_string(body, 30)

  try_file = (url) ->
    url = url\gsub(urlBase, '')
    fn = "modules/location/#{safe url}"
    att = lfs.attributes(fn)
    unless att
      return false
    size = att.size
    res\append ':status', '200'
    --res\append 'content-type', content_type
    res\append 'content-length', tostring(size)
    req\write_headers(res, false, 30)
    fd = io.open(fn, 'rb')
    req\write_body_from_file(fd, 5*60)
    fd\close!
    return true

  -- Serve file if it exists
  if req.url\match('%.') and try_file(req.url)
    return

  channel = req.url\match('channel=(.+)%s*')
  unless channel
    html = 'Invalid channel'
    send html, '404'
    return

  channel = html2unicode channel
  unescaped_channel = unescape channel

  html = [[
  <!DOCTYPE html>
  <html>
  <head>

  <!-- adapted from dbot's map by xt -->
  <!-- set location with !location set yourlocation -->

  <meta charset="utf-8">
  <meta name="viewport" content="initial-scale=1.0, user-scalable=no">
  <title>IRC member map</title>

  <style type="text/css">
  html { height: 100% }
  body { height: 100%; margin: 0; padding: 0 }
  </style>

  <script type="text/javascript" src="//maps.googleapis.com/maps/api/js?key=]]..ivar2.config.youtubeAPIKey..[[&amp;sensor=false"></script>

<!--this was removed so use it inline for now  <script src="//google-maps-utility-library-v3.googlecode.com/svn/trunk/markerclustererplus/src/markerclusterer_packed.js"></script>-->
  <script src="markerclusterer.js"></script>
  </head><body>
  <div id="map" style="width: 100%; height: 100%"></div>
  <script type="text/javascript">
]]
  markerdata = {}
  for n,t in pairs ivar2.channels[unescaped_channel].nicks
    pos = ivar2.persist["location:coords:#{n}"]
    if pos
      lat, lon = pos\match('([^,]+),([^,]+)')
      marker = {
        account: n,
        formattedAddress: ivar2.persist["location:place:#{n}"] or 'N/A',
        lng: tonumber(lon),
        lat: tonumber(lat),
        channel: unescaped_channel
      }
      markerdata[#markerdata + 1] = marker

  if #markerdata == 0 then
    html = 'Invalid channel'
    send html, '404'
    return

  html ..= [[
  var map = new google.maps.Map(document.getElementById("map"), {
    center: new google.maps.LatLng(0, 0),
    zoom: 3
  });
  var infoWindow = null;
  var markers = [];

  function makeInfoWindow(info) {
    return new google.maps.InfoWindow({
      content: makeMarkerDiv(info)
    });
  }

  function makeMarkerDiv(h) {
    return "<div style='line-height:1.35;overflow:hidden;white-space:nowrap'>" + h + "</div>";
  }

  function makeMarkerInfo(m) {
    return "<strong>" + m.get("account") + " on " + m.get("channel") + "</strong> " +
      m.get("formattedAddress");
  }

  function dismiss() {
    if (infoWindow !== null) {
      infoWindow.close();
    }
  }
  ]]..json.encode(markerdata)..[[.forEach(function (loc) {
    var marker = new google.maps.Marker({
      position: new google.maps.LatLng(loc.lat, loc.lng)
    });
    marker.setValues(loc);
    markers.push(marker);
    google.maps.event.addListener(marker, "mouseover", function () {
      dismiss();
      infoWindow = makeInfoWindow(makeMarkerInfo(marker));
      infoWindow.open(map, marker);
    });
    google.maps.event.addListener(marker, "mouseout", dismiss);
    google.maps.event.addListener(marker, "click", function () {
      map.setZoom(Math.max(8, map.getZoom()));
      map.setCenter(marker.getPosition());
    });
  });
  var mc = new MarkerClusterer(map, markers, {
    averageCenter: true
  });
  google.maps.event.addListener(mc, "mouseover", function (c) {
    dismiss();
    var markers = c.getMarkers();
    infoWindow = makeInfoWindow(markers.map(makeMarkerInfo).join("<br>"));
    infoWindow.setPosition(c.getCenter());
    infoWindow.open(map);
  });
  google.maps.event.addListener(mc, "mouseout", dismiss);
  google.maps.event.addListener(mc, "click", dismiss);

  </script>
  </body>
  </html>
  ]]
  --print('---- request finished, send response')
  return html
lookup = (address, cb) ->
  API_URL = 'http://maps.googleapis.com/maps/api/geocode/json'
  url = API_URL .. '?address=' .. urlEncode(address) .. '&sensor=false' .. '&language=en-GB'

  simplehttp url, (data) ->
      parsedData = json.decode data
      if parsedData.status ~= 'OK'
        return false, parsedData.status or 'unknown API error'

      location = parsedData.results[1]
      locality, country, adminArea

      findComponent = (field, ...) ->
        n = select('#', ...)
        for i=1, n
          searchType = select(i, ...)
          for _, component in ipairs(location.address_components)
            for _, type in ipairs(component.types)
              if type == searchType
                return component[field]

      locality = findComponent('long_name', 'locality', 'postal_town', 'route', 'establishment', 'natural_feature')
      adminArea = findComponent('short_name', 'administrative_area_level_1')
      country = findComponent('long_name', 'country') or 'Nowhereistan'

      if adminArea and #adminArea <= 5
        if not locality
          locality = adminArea
        else
          locality = locality..', '..adminArea

      locality = locality or 'Null'

      place = locality..', '..country

      cb place, location.geometry.location.lat..','..location.geometry.location.lng

PRIVMSG:
  '^%plocation set (.+)$': (source, destination, arg) =>
    lookup arg, (place, loc) ->
      nick = source.nick
      @.persist["location:place:#{nick}"] = place
      @.persist["location:coords:#{nick}"] = loc
      say '%s %s', place, loc
  '^%plocation map$': (source, destination, arg) =>
    channel = urlEncode destination
    say "#{ivar2.config.webserverprefix}/location/?channel=#{channel}"
