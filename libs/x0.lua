local simplehttp = require'simplehttp'
local x0 = ivar2.persist

return {
	lookup = function(url, callback)
		if(x0["x0:" .. url]) then
			local url = x0["x0:" .. url]

			return callback(url)
		end

		simplehttp(
			'http://api.x0.no/?' .. url,
			function(data, url)
				if(data:sub(8,9) =='x0') then
					x0["x0:" .. url] = data

					return callback(data)
				end
			end
		)
	end,
}
