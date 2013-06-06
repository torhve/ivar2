local simplehttp = require'simplehttp'
local json = require'json'

local fetchInformation = function(queue, vid)
	simplehttp(
		("http://vimeo.com/api/v2/video/%s.json"):format(vid),

		function(data)
			-- Invalid video.
			if(data:match('^%d+ not found%.')) then
				return
			end

			data = json.decode(data)
			if(not data) then return end

			local info = data[1]
			local title = info.title
			local uploader = info.user_name
			local duration = info.duration

			local output
			if(duration) then
				if(duration > 3600) then
					duration = string.format(
						'%d:%02d:%02d',
						math.floor(duration / 3600),
						math.floor((duration % 3600) / 60),
						duration % 60
					)
				else
					duration = string.format(
						'%d:%02d',
						math.floor(duration / 60),
						duration % 60
					)
				end

				output = string.format('%s (%s) by %s', title, duration, uploader)
			else
				output = string.format('%s by %s', title, uploader)
			end

			queue:done(output)
		end
	)
end

customHosts['vimeo%.com'] = function(queue, info)
	local path = info.path
	local vid

	if(path and path:match('^/(%d+)')) then
		vid = path:match('^/(%d+)')
	end

	if(vid) then
		fetchInformation(queue, vid)

		return true
	end
end
