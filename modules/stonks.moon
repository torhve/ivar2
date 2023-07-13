util = require'util'
simplehttp = util.simplehttp
json = util.json
urlEncode = util.urlEncode

siValue = (val) ->
  val = val\gsub(',','')
  val = tonumber val
  if val >= 1e6
    return ('%.1f')\format(val / 1e6)\gsub('%.', 'M')\gsub('M0', 'M')
  elseif(val >= 1e4) then
    return ("%.1f")\format(val / 1e3)\gsub('%.', 'k')\gsub('k0', 'k')
  else
   return val

quote = (a, withname, withoutprice) ->
  if not withname
    withname = false
  if not withoutprice
    withoutprice = false
  data = simplehttp "https://query1.finance.yahoo.com/v6/finance/quoteSummary/#{urlEncode a}?modules=price"
  data = json.decode(data)
  res = data['quoteSummary']['result'][1]
  unless res return ''
  price = res.price

  out = {}

  unless withname
    out[#out+1] = price.symbol

  c =  price.currency
  if price.currencySymbol
    c = price.currencySymbol
  unless withoutprice
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

  unless withoutprice
    out[#out+1] = siValue(current_price)
  if current_raw_per > 0
    current_per = util.green current_per
  else
    current_per = util.red current_per
  out[#out+1] = " "..current_per .." "

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

multiquote = (stonks) ->
  out = {}
  for stonk in *stonks
    out[#out+1] = quote(stonk,  false, false)

  return table.concat(out, ' | ')

sayquote = (s, d, a) =>
  if string.find(a, ' ')
    say multiquote(util.split(a, ' '))
  else
    say quote(a, true, false)

meme = (s, d, a) =>
  stonks = {'GME', 'AMC', 'BTC-USD', 'TSLA'}
  say multiquote(stonks)

idx = (s, d, a) =>
  stonks = {'OSEBX.OL', '^IXIC', '^GSPC', '^DJI', '^NYA', '^N225'}
  say multiquote(stonks)

crypto = (s, d) =>
  say multiquote {'BTC-USD', 'ETH-USD', 'SOL-USD', 'XRP-USD', 'DOGE-USD'}


PRIVMSG:
  '^%pq (.*)$': sayquote
  '^%pstonks': meme
  '^%pidx$': idx
  '^%pcrypto$': crypto
