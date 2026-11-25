busted = require'busted'
describe = busted.describe
it = busted.it
util = require'util'
describe "uri parse", ->
  it "should work with utf8 chars", ->
      yrurl = 'http://www.yr.no/stad/Norway/Akershus/Bærum/Kolsås~2333471/forecast.xml'
      urip = util.uri_parse(yrurl)
      res = {
        host: 'www.yr.no',
        path: '/stad/Norway/Akershus/B%C3%A6rum/Kols%C3%A5s~2333471/forecast.xml',
        scheme: 'http',
      }
      assert.are_same urip, res
