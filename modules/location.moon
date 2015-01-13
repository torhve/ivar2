{:simplehttp, :json, :urlEncode} = require'util'

on_finished = (req, resp) ->
  channel = req.url\match('channel=(.+)')
  unless channel
    html = 'Invalid channel'
    resp\set_status(404)
    resp\set_header('Content-Type', 'text/html')
    resp\set_header('Content-Length', #html)
    resp\set_body(html)
    resp\send()
    return
  else
    channel = '#'..channel

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
  <script src="//google-maps-utility-library-v3.googlecode.com/svn/trunk/markerclustererplus/src/markerclusterer_packed.js"></script>
  </head><body>
  <div id="map" style="width: 100%; height: 100%"></div>
  <script type="text/javascript">
]]
  markerdata = {}
  for n,t in pairs ivar2.channels[channel].nicks
    pos = ivar2.persist["location:coords:#{n}"]
    if pos
      lat, lon = pos\match('([^,]+),([^,]+)')
      marker = {
        account: n,
        formattedAddress: ivar2.persist["location:place:#{n}"] or 'N/A',
        lng: tonumber(lon),
        lat: tonumber(lat),
        channel: channel
      }
      markerdata[#markerdata + 1] = marker

  if #markerdata == 0 then
    html = 'Invalid channel'
    resp\set_status(404)
    resp\set_header('Content-Type', 'text/html')
    resp\set_header('Content-Length', #html)
    resp\set_body(html)
    resp\send()
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
  resp\set_status(200)
  resp\set_header('Content-Type', 'text/html')
  resp\set_header('Content-Length', #html)
  resp\set_body(html)
  resp\send()

ivar2.webserver.regUrl "/location/(.*)$", on_finished

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
    channel = destination\sub(2)
    say "http://irc.lart.no:#{ivar2.config.webserverport}/location/?channel=#{channel}"
