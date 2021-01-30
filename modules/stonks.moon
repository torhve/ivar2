util = require'util'
simplehttp = util.simplehttp
json = util.json
urlEncode = util.urlEncode


quote = (s, d, a) =>
  data = simplehttp "https://query1.finance.yahoo.com/v10/finance/quoteSummary/#{a}?modules=price"
  data = json.decode(data)
  res = data['quoteSummary']['result'][1]
  price = res.price

  out = {}

  c =  price.currency
  if price.currencySymbol
    c = price.currencySymbol
  out[#out+1] = c
  out[#out+1] = price.regularMarketPrice.fmt
  per = price.regularMarketChangePercent.fmt
  if price.regularMarketChangePercent.raw > 0
    per = util.green per
  else
    per = util.red per
  out[#out+1] = "("..per ..")"

  if price.postMarketPrice.fmt
    out[#out+1] = "("..price.postMarketPrice.fmt..")"


  say table.concat(out, ' ')



PRIVMSG:
  '^%pq (.*)$': quote
