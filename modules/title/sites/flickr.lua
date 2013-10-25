local simplehttp = require'simplehttp'
local html2unicode = require'html'
local base58 = require'base58'

local handler = function(queue, info)
	local path = info.path

	-- http://farm{farm-id}.static.flickr.com/{server-id}/{id}_{secret}.jpg
	-- http://farm{farm-id}.static.flickr.com/{server-id}/{id}_{secret}_[mstzb].jpg
	-- http://farm{farm-id}.static.flickr.com/{server-id}/{id}_{o-secret}_o.(jpg|gif|png)
	if(path and path:match('/[^/]+/([^_]+)')) then
		local photoid = path:match('/[^/]+/([^_]+)')
		local url = string.format(
			"http://api.flickr.com/services/rest/?method=flickr.photos.getInfo&api_key=%s&photo_id=%s",
			ivar2.config.flickrAPIKey,
			photoid
		)

		simplehttp(
			url,

			function(data, url, response)
				local title = html2unicode(data:match('<title>([^<]+)</title>'))
				local owner = html2unicode(data:match('realname="([^"]+)"') or data:match('nsid="([^"]+)"'))

				queue:done(string.format(
					'%s by %s <http://flic.kr/p/%s/>',
					title,
					owner,
					base58.encode(photoid)
				))
			end
		)

		return true
	end
end

customHosts['farm%d+%.static%.flickr.com'] = handler
customHosts['farm%d+%.staticflickr.com'] = handler
