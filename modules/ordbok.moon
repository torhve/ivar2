util = require'util'
simplehttp = util.simplehttp
json = util.json
bold = util.bold
urlEncode = util.urlEncode

APIBASE = "https://ord.uib.no/"

lookup = (word, dict, number) ->
  unless dict
    dict = 'bm'
  unless number
      number =1
  --data = simplehttp "#{APIBASE}/suggest?q=#{urlEncode word}&dict=#{dict}&n=#{number}"
  scope = "eif"
  data = simplehttp "#{APIBASE}api//articles?w=#{urlEncode word}&dict=#{dict}&scope=#{scope}"
  data = json.decode(data)
  res = data['articles'][dict][1]

  url = "#{APIBASE}#{dict}/article/#{res}.json"
  data = simplehttp url
  data = json.decode(data)
  out = {}

  definition = data.body.definitions[1].elements[1].content

  ic = data.lemmas[1].inflection_class

  output = "[#{util.bold(data.suggest[1])}]: #{ic} (#{definition})"
  table.insert(out, output)

  return table.concat(out, ' ')

nnlookup = (s, d, a) =>
  say lookup(a, 'nn')

nnlookup = (s, d, a) =>
  say lookup(a, 'bm')

PRIVMSG:
  '^%pbm (.*)$': bmlookup
  '^%pnn (.*)$': nnlookup
--  '^%pnynorsk (.*)$': ordbok
--  '^%pordbok (.*)$': ordbok

