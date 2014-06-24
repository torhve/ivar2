
URL = 'http://worldcup.sfg.io/matches/'

bold = ivar2.util.bold

formatMatch = (m) ->
  out = "#{m.home_team.country} #{bold m.home_team.goals} - #{bold m.away_team.goals} #{m.away_team.country}"
  if m.status == 'in progress'
    out ..= " " .. ivar2.util.underline "In progress!"
  return out


PRIVMSG:
  '^%pwc today$': =>
    ivar2.util.simplehttp URL..'today', (json) ->
      data = ivar2.util.json.decode(json)
      out = {}
      for _,m in pairs(data)
        out[#out+1] = "["..formatMatch(m).."]"
      say table.concat(out, ' ')
  '^%pwc tomorrow$': =>
    ivar2.util.simplehttp URL..'tomorrow', (json) ->
      data = ivar2.util.json.decode(json)
      out = {}
      for _,m in pairs(data)
        out[#out+1] = "["..formatMatch(m).."]"
      say table.concat(out, ' ')
  '^%pwc$': =>
    ivar2.util.simplehttp URL..'current', (json) ->
      data = ivar2.util.json.decode(json)
      out = {}
      for _,m in pairs(data)
        out[#out+1] = "[#{m.home_team.code} #{bold m.home_team.goals} - #{bold m.away_team.goals} #{m.away_team.code}]"
      if #out < 1
        return reply "No match being played."
      say table.concat(out, ' ')
