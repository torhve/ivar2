local util = require'util'
local simplehttp = util.simplehttp
local json = util.json
local date = require'idate'

local parseDuration
do
	local elementPattern = '(%d+%.?%d*)([YMWDTHS])'

	local fmtTable = {
		y = 12*30*24*60*60,
		m = 30*24*60*60,
		w = 7*24*60*60,
		d = 24*60*60,
		H = 60*60,
		M = 60,
		S = 1,
	}

	parseDuration = function(str)
		if(not (str:sub(1,1) == "P" and str:sub(-1):match("[YMWDHS]"))) then
			return nil, "Invalid ISO 8601 duration."
		end

		local duration = 0
		local date, time = str:match("P([^T]*)T?(.*)$")
		for dur, elm in date:gmatch(elementPattern) do
			elm = elm:lower()
			duration = duration + (dur * fmtTable[elm])
		end

		for dur, elm in time:gmatch(elementPattern) do
			duration = duration + (dur * fmtTable[elm])
		end

		return duration
	end
end

local siValue = function(val)
	val = tonumber(val)
	if(val >= 1e6) then
		return ('%.1f'):format(val / 1e6):gsub('%.', 'M'):gsub('M0', 'M')
	elseif(val >= 1e4) then
		return ("%.1f"):format(val / 1e3):gsub('%.', 'k'):gsub('k0', 'k')
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
			if not info.items then return end
			local video = info.items[1]
			local title = video.snippet.title
			local uploader = video.snippet.channelTitle
			local duration = date.relativeDuration(parseDuration(video.contentDetails.duration))
			local live = video.snippet.liveBroadcastContent and video.snippet.liveBroadcastContent == 'live'
			if live then -- Live videos doesn't have duration, so overload this field
				duration = '🔴 LIVE'
			end
			local views = siValue(video.statistics.viewCount)
			local likeCount = siValue(video.statistics.likeCount or 0)
			local dislikeCount = siValue(video.statistics.dislikeCount or 0)

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
		elseif(path:match('/shorts/([a-zA-Z0-9_-]+)')) then
			vid = path:match('/shorts/([a-zA-Z0-9_-]+)')
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
