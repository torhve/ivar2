util = require'util'
simplehttp = util.simplehttp
json = util.json
urlEncode = util.urlEncode


quote = (a, withname) ->
  if not withname
    withname = false
  data = simplehttp "https://query1.finance.yahoo.com/v10/finance/quoteSummary/#{a}?modules=price"
  data = json.decode(data)
  res = data['quoteSummary']['result'][1]
  price = res.price

  out = {}

  c =  price.currency
  if price.currencySymbol
    c = price.currencySymbol
  out[#out+1] = c

  current_price = price.regularMarketPrice.fmt
  current_per = price.regularMarketChangePercent.fmt
  current_raw_per = price.regularMarketChangePercent.raw
  regularmarket = true
  premarket = false
  postmarket = false
  if price.preMarketTime
    if price.preMarketTime > price.regularMarketTime
      current_price = price.preMarketPrice.fmt
      current_per = price.preMarketChangePercent.fmt
      current_raw_per = price.preMarketChangePercent.raw
      premarket = true
    elseif price.postMarketTime and price.postMarketTime > price.regularMarketTime
      current_price = price.postMarketPrice.fmt
      current_per = price.postMarketChangePercent.fmt
      current_raw_per = price.postMarketChangePercent.raw
      postmarket = true


  out[#out+1] = current_price
  if current_raw_per > 0
    current_per = util.green current_per
  else
    current_per = util.red current_per
  out[#out+1] = "("..current_per ..")"

  --if price.preMarketPrice.fmt
  --  out[#out+1] = "("..price.preMarketPrice.fmt..")"

  --if price.postMarketPrice.fmt
  --  out[#out+1] = "("..price.postMarketPrice.fmt..")"
  --
  --

  if withname
    if price.longName == json.null
      out[#out+1] = price.shortName
    else
      out[#out+1] = price.longName

    if premarket or postmarket
      out[#out+1] = "🥱"

  return table.concat(out, ' ')


sayquote = (s, d, a) =>
  say quote(a, true)

meme = (s, d, a) =>
  stonks = {'GME', 'AMC', 'BB', 'NOK'}
  out = {}
  for stonk in *stonks
    out[#out+1] = stonk .. ' ' .. quote(stonk)

  say table.concat(out, ' ')

PRIVMSG:
  '^%pq (.*)$': sayquote
  '^%pstonks': meme
