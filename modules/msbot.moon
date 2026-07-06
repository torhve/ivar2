{:green, :red, :simplehttp, :json, :urlEncode} = require'util'

key2 = ivar2.config.msbotApiKey
_api = 'https://api.projectoxford.ai/vision/v1.0/'

phrases = {
  'That is'
  'That\'s',
  'I\'m looking at',
  'Looks like',
  'Probably',
  'I can see',
  'I\'m seeing'
}

errHandle = (arg) ->
  if arg.statusCode and arg.statusCode != 200
    return arg.message

PRIVMSG:
  '^%panalyze (.+)$': (source, destination, arg) =>
    simplehttp {url:_api..'analyze?visualFeatures=Categories,Tags,Description,Faces,ImageType,Color&details=Celebrities', data:json.encode({url:arg}), method:'POST', headers:{['Ocp-Apim-Subscription-Key']:key2}}, (res) ->
      say res
  '^%pocr (.+)$': (source, destination, arg) =>
    simplehttp {url:_api..'ocr?', data:json.encode({url:arg}), method:'POST', headers:{['Ocp-Apim-Subscription-Key']:key2}}, (res) ->
      d = json.decode res
      err = errHandle(d)
      if err
        say err
        return

      out = {}

      if not res or not d
        say 'Microsoftbot not clever enough.'

      for _, r in ipairs d.regions
        for _, w in ipairs r.lines
          for _, t in ipairs w.words
            out[#out+1] = t.text
          out[#out+1] = '\n'
        out[#out+1] = '\n'

      say table.concat(out, ' ')



  '^%pcaption (.+)$': (source, destination, arg) =>
    simplehttp {url:_api..'analyze?visualFeatures=Categories,Tags,Description,Faces,ImageType,Color&details=Celebrities', data:json.encode({url:arg}), method:'POST', headers:{['Ocp-Apim-Subscription-Key']:key2}}, (res) ->
      print(res)
      d = json.decode res
      err = errHandle(d)
      if err
        say err
        return
      out = {}

      description = d.description
      unless description
        say 'Microsoftbot not clever enough.'


      for _, t in ipairs(description.captions)
        out[#out+1] = t.text
        out[#out+1] = "I am #{math.floor t.confidence*100}% sure"

      if #out < 1 then
        out[#out+1] = 'no caption, but tags are '..table.concat(description.tags, ', ')

      for _, f in ipairs d.faces
        out[#out+1] = "face: age #{f.age}, #{f.gender}"

      choice = math.random(1, #phrases)
      phrase = phrases[choice]
      say phrase .. " " .. table.concat(out, ', ')

