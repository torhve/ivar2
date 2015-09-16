api_key = 'dc6zaTOxFJmzC'


PRIVMSG:
  '^%pgiphy (.+)': (source, destination, arg) =>
      ivar2.util.simplehttp "http://api.giphy.com/v1/gifs/search?q=#{ivar2.util.urlEncode arg}&api_key=#{api_key}", (json) ->
        data = ivar2.util.json.decode json
        if not data then return

        url = data.data[1].images.original.url
        say url
