local simplehttp = require'simplehttp'
local html2unicode = require'html'

customHosts['open.spotify.com'] = function(queue, info)
	local path = info.path

	if(path and path:match'/(%w+)/(.+)') then
		simplehttp(
			info.url,

			function(data, url, response)
				local title = html2unicode(data:match'<title>(.-)</title>')
				--local uri = data:match('property="al:android:url" content="([^"]+)"')

				queue:done(string.format('%s | http://play.spotify.com%s', title, info.path))
			end
		)

		return true
	end
end

customHosts['play.spotify.com'] = function(queue, info)
	local path = info.path

	if(path and path:match'/(%w+)/(.+)') then
		simplehttp(
			info.url:gsub("play%.spotify", "open.spotify"),

			function(data, url, response)
				local title = html2unicode(data:match'<title>(.-)/title>')
				local uri = data:match('property="og:audio" content="([^"]+)"')

				queue:done(string.format('%s | http://open.spotify.com%s', title, info.path))
			end
		)

		return true
	end
end
