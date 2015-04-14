local ivar2 = ...
local util = require'util'

return function(url, callback)
	local x0 = ivar2.persist
	if(x0["x0:" .. url]) then
		local url = x0["x0:" .. url]

		return callback(url)
	end

	util.simplehttp(
		'https://xt.gg/url?url=' .. util.urlEncode(url),
		function(data, url)
			data = util.json.decode(data).url
			x0["x0:" .. url] = data
			return callback(data)
		end
	)
end
