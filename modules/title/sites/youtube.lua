local simplehttp = require'simplehttp'
local json = require'json'

local siValue = function(val)
	val = tonumber(val)
	if(val >= 1e6) then
		return ('%.1f'):format(val / 1e6):gsub('%.', 'M')
	elseif(val >= 1e4) then
		return ("%.1f"):format(val / 1e3):gsub('%.', 'k')
	else
		return val
	end
end

local fetchInformation = function(queue, vid)
	local key = ivar2.config.youtubeAPIKey
	local url = string.format('https://www.googleapis.com/youtube/v3/videos?part=snippet%%2CcontentDetails%%2Cstatistics&id=%s&key=%s', vid, key)
	simplehttp(
		url,
		function(data)
			local info = json.decode(data)
			local video = info.items[1]
			local title = video.snippet.title
			local uploader = video.snippet.channelTitle
			local duration = video.contentDetails.duration
			local views = siValue(video.statistics.viewCount)
			local likeCount = siValue(video.statistics.likeCount)
			local dislikeCount = siValue(video.statistics.dislikeCount)

			local output = string.format('%s (%s) by %s [+%s/-%s, %s views]', title, duration, uploader, likeCount, dislikeCount, views)
			queue:done(output)
		end
	)
end


customHosts['youtube%.com'] = function(queue, info)
	local query = info.query
	local path = info.path
	local fragment = info.fragment
	local vid

	if(query and query:match('v=[a-zA-Z0-9_-]+')) then
		vid = query:match('v=([a-zA-Z0-9_-]+)')
	elseif(fragment and fragment:match('.*/%d+/([a-zA-Z0-9_-]+)')) then
		vid = fragment:match('.*/%d+/([a-zA-Z0-9_-]+)')
		-- FIXME: lua-handler's URI parser doesn't split path and fragment
		-- correctly when there's no query present.
	elseif(path) then
		if(path:match('#.*/%d+/([a-zA-Z0-9_-]+)')) then
			vid = path:match('#.*/%d+/([a-zA-Z0-9_-]+)')
		elseif(path:match('/v/([a-zA-Z0-9_-]+)')) then
			vid = path:match('/v/([a-zA-Z0-9_-]+)')
		end
	end

	if(vid) then
		fetchInformation(queue, vid)

		return true
	end
end

customHosts['youtu%.be'] = function(queue, info)
	local path = info.path
	local vid

	if(path and path:match('/([a-zA-Z0-9_-]+)')) then
		vid = path:match('/([a-zA-Z0-9_-]+)')
	end

	if(vid) then
		fetchInformation(queue, vid)

		return true
	end
end
