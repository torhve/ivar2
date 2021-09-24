util = require'util'
simplehttp = util.simplehttp
json = util.json
urlEncode = util.urlEncode

siValue = (val) ->
  if val >= 1e6
    return ('%.1f')\format(val / 1e6)\gsub('%.', 'M')\gsub('M0', 'M')
  elseif(val >= 1e4) then
    return ("%.1f")\format(val / 1e3)\gsub('%.', 'k')\gsub('k0', 'k')
  else
   return val


lookup = (s, d, a) =>
  data = simplehttp "http://prisguiden.no/sok?module=PGBridgeService&service=getData&providers%5B%5D%3D=searchResults&q=#{urlEncode a}&o=0&l=1"
  unless data
    say 'No reply from API'
  data = json.decode(data)
  unless data
    say 'Invalid json'
    return
  -- get the first search result
  res = data['searchResults']['products'][1]

  price = res.price
  if price > 10000
    price = siValue price
  price ..= ' kr'

  offer = ''
  if res.ratio and res.ratio != json.null
    if res.ratio < 0
      offer = " " ..util.green(tostring(res.ratio .. ' %'))

  priceCount = res.priceCount
  if priceCount > 1
    priceCount ..= ' prisar'
  else
    priceCount ..= ' pris'

  out = {}
  out[#out+1] = res.title
  out[#out+1] = '[ '.. price..' ]'
  out[#out+1] = offer
  out[#out+1] = priceCount
  if res.productId
    out[#out+1] = "http://pris.guide/produkt/" .. res.productId
  else
    out[#out+1] = "http://pris.guide" .. res.url

  say table.concat(out, ' ')


PRIVMSG:
  '^%ppg (.*)$': lookup
  '^%pprisuiden (.*)$': lookup
