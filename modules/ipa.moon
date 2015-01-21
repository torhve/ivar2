-- international phonetic alphabet
{:simplehttp, :urlEncode, :json} = require'util'
PRIVMSG:
  '^%pipa (.*)$': (source, destination, input) =>
    simplehttp "http://rhymebrain.com/talk?function=getWordInfo&word=#{urlEncode input}", (data) ->
      data = json.decode(data)
      say data.ipa
