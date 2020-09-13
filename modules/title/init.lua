--- HTML Title resolving module
local util = require'util'
local simplehttp = util.simplehttp
local trim = util.trim
local uri_parse = util.uri_parse
local iconv = require"iconv"
local html2unicode = require'html'
local lfs = require'lfs'
local exif = require'exif'
local googlevision = require'googlevision' -- requires google vision cloud API key

local DL_LIMIT = 2^24 -- 16 MiB

local gvision_apikey = ivar2.config.cloudvisionAPIKey or 'AIzaSyBTLSPVnk6yUFTm8USlCOIxEqbkOpAauxQ'

local patterns = {
	-- X://Y url
	"^(https?://%S+)",
	"^<(https?://%S+)>",
	"%f[%S](https?://%S+)",
	-- www.X.Y url
	"^(www%.[%w_-%%]+%.%S+)",
	"%f[%S](www%.[%w_-%%]+%.%S+)",
}

local translateCharset = {
	utf8 = 'utf-8',
	['x-sjis'] = 'sjis',
	['ks_c_5601-1987'] = 'euc-kr',
	['ksc_5601'] = 'euc-kr',
}

-- RFC 2396, section 1.6, 2.2, 2.3 and 2.4.1.
local smartEscape = function(str)
	local pathOffset = str:match("//[^/]+/()")

	-- No path means nothing to escape.
	if(not pathOffset) then return str end
	local prePath = str:sub(1, pathOffset - 1)

	-- lowalpha: a-z | upalpha: A-Z | digit: 0-9 | mark: -_.!~*'() |
	-- reserved: ;/?:@&=+$, | delims: <>#%" | unwise: {}|\^[]` | space: <20>
	local pattern = '[^a-zA-Z0-9%-_%.!~%*\'%(%);/%?:@&=%+%$,<>#%%"{}|\\%^%[%] ]'
	local path = str:sub(pathOffset):gsub(pattern, function(c)
		return ('%%%02X'):format(c:byte())
	end)

	return prePath .. path
end

local parseAJAX
do
	local escapedChars = {}
	local q = function(i)
		escapedChars[string.char(i)] = string.format('%%%X', i)
	end

	for i=0, tonumber(20, 16) do
		q(i)
	end

	for i=tonumber('7F', 16), tonumber('FF', 16) do
		q(i)
	end

	q(tonumber(23, 16))
	q(tonumber(25, 16))
	q(tonumber(26, 16))
	q(tonumber('2B', 16))

	function parseAJAX(url)
		local offset, shebang = url:match('()#!(.+)$')

		if(offset) then
			url = url:sub(1, offset - 1)

			shebang = shebang:gsub('([%z\1-\127\194-\244][\128-\191]*)', escapedChars)
			url = url .. '?_escaped_fragment_=' .. shebang
		end

		return url
	end
end

local verify = function(charset)
	if(charset) then
		charset = charset:lower()
		charset = translateCharset[charset] or charset

		return charset
	end
end

local guessCharset = function(headers, data)
	local charset

	-- BOM:
	local bom4 = data:sub(1,4)
	local bom2 = data:sub(1,2)
	if(data:sub(1,3) == '\239\187\191') then
		return 'utf-8'
	elseif(bom4 == '\255\254\000\000') then
		return 'utf-32le'
	elseif(bom4 == '\000\000\254\255') then
		return 'utf-32be'
	elseif(bom4 == '\254\255\000\000') then
		return 'x-iso-10646-ucs-4-3412'
	elseif(bom4 == '\000\000\255\254') then
		return 'x-iso-10646-ucs-4-2143'
	elseif(bom2 == '\255\254') then
		return 'utf-16le'
	elseif(bom2 == '\254\255') then
		return 'utf-16be'
	end

	-- TODO: tell user if it's downloadable stuff, other mimetype, like PDF or whatever

	-- Header:
	local contentType = headers['content-type']
	if(contentType and contentType:match'charset') then
		charset = verify(contentType:match('charset=([^;]+)'))
		if(charset) then return charset end
	end

	-- XML:
	charset = verify(data:match('<%?xml .-encoding=[\'"]([^\'"]+)[\'"].->'))
	if(charset) then return charset end

	-- HTML5:
	charset = verify(data:match('<meta charset=[\'"]([\'"]+)[\'"]>'))
	if(charset) then return charset end

	-- HTML:
	charset = data:lower():match('<meta.-content=[\'"].-(charset=.-)[\'"].->')
	if(charset) then
		charset = verify(charset:match'=([^;]+)')
		if(charset) then return charset end
	end
end

local limitOutput = function(str)
	local limit = 300
	if(#str > limit) then
		str = str:sub(1, limit)
		if(#str == limit) then
			-- Clip it at the last space:
			str = str:match('^.* ') .. '…'
		end
	end

	return str
end

local handleExif = function(data)
	-- Try to get interesting exif information from a blob of data
	--

	local exif_tags = {}
	local interesting_exif_tags = {'Make', 'Model','ISOSpeedRatings', 'ExposureTime', 'FNumber', 'FocalLength', 'DateTimeOriginal', }

	local exif_data = exif.loadbuffer(data)
	for i, ifd in pairs(exif_data:ifds()) do
		for j, entry in pairs(ifd:entries()) do
			for _, tag in pairs(interesting_exif_tags) do
				print(entry.tag, entry.value)
				if entry.tag == tag and entry.value then
					local value = entry.value
					if tag == 'ISOSpeedRatings' then
						value = string.format('ISO %s', value)
					end
					exif_tags[#exif_tags+1] = value
				end
			end
		end
	end

	local function toDecimal(d1, m1, s1, d2, m2, s2, ns, ew)
		local sign = 1
		if ns == 'S' then
			sign = -1
		end
		local decDeg1 = sign*(d1 + m1/60 + s1/3600)
		sign = 1
		if ew == 'W' then
			sign = -1
		end
		local decDeg2 = sign*(d2 + m2/60 + s2/3600)
		return decDeg1, decDeg2
	end

	local lat_ref = exif_data:ifd("GPS"):entry('GPSLatitudeRef')
	local lon_ref = exif_data:ifd("GPS"):entry('GPSLongitudeRef')
	local lat = exif_data:ifd("GPS"):entry('GPSLatitude')
	local lon = exif_data:ifd("GPS"):entry('GPSLongitude')
	local lat_split = util.split(tostring(lat), ', ')
	local lon_split = util.split(tostring(lon), ', ')
	if #lat_split == 3 and #lon_split == 3 then
		local lon_d, lat_d = toDecimal(lat_split[1], lat_split[2], lat_split[3],
		lon_split[1], lon_split[2], lon_split[3], lat_ref, lon_ref)
		local gmaps_link = string.format('https://maps.google.com/?q=%s,%s', lon_d, lat_d)
		exif_tags[#exif_tags+1] = gmaps_link
	end

	return exif_tags

end

local handleData = function(headers, data)
	local charset = guessCharset(headers, data)
	if(charset and charset ~= 'utf-8') then
		local cd, _ = iconv.new("utf-8", charset)
		if(cd) then
			data = cd:iconv(data)
		end
	end

	local head = data:match('<[hH][eE][aA][dD]>(.-)</[hH][eE][aA][dD]>') or data
	local title = head:match('<[tT][iI][tT][lL][eE][^/>]*>(.-)</[tT][iI][tT][lL][eE]>')
	if(title) then
		for _, pattern in ipairs(patterns) do
			title = title:gsub(pattern, '<snip />')
		end

		title = html2unicode(title)
		title = trim(title:gsub('%s%s+', ' '))

		if(title ~= '<snip />' and #title > 0) then
			return limitOutput(title)
		end
	end

	-- No title found, return some possibly usefule info
	local content_type = headers['content-type']
	local content_length = headers['content-length']
	if content_length then
		content_length = math.floor(content_length/1024)
	else
		content_length = math.floor(#data/1024) -- will be limited to DL_LIMIT
	end

	local exif_tags = {}
	local googlevision_tags = {}
	if string.find(content_type, 'image/jp') then
		exif_tags = handleExif(data)
		if #data < 10485760 then -- max upload limit
			googlevision_tags = googlevision.annotateData(gvision_apikey, data)
		end
	end

	local message
	message = string.format('[%s] %s kB', content_type, content_length)
	if #exif_tags > 0 then
		message = message .. ', ' .. table.concat(exif_tags, ', ')
	end

	if #googlevision_tags > 0 then
		message = message .. ', ' .. table.concat(googlevision_tags, ', ')
	end

	return message

end

local handleOutput = function(metadata)
	metadata.num = metadata.num - 1
	if(metadata.num ~= 0) then return end

	local output = {}
	for i=1, #metadata.queue do
		local lookup = metadata.queue[i]
		if(lookup.output) then
			table.insert(output, string.format('\002[%s]\002 %s', lookup.index, lookup.output))
		end
	end

	if(#output > 0) then
		ivar2:Msg('privmsg', metadata.destination, metadata.source, table.concat(output, ' '))
	end
end

local customHosts = {}
local customPost = {}
do
	local _PROXY = setmetatable(
		{
			DL_LIMIT = DL_LIMIT,

			ivar2 = ivar2,
			handleData = handleData,
			limitOutput = limitOutput,

		},{ __index = _G }
	)

	local loadFile = function(kind, path, filename)
		local customFile, customError = loadfile(path .. filename)
		if(customFile) then
			setfenv(customFile, _PROXY)

			local success, message = pcall(customFile, ivar2)
			if(not success) then
				ivar2:Log('error', 'Unable to execute %s title handler %s: %s.', kind, filename:sub(1, -5), message)
			else
				ivar2:Log('info', 'Loading %s title handler: %s.', kind, filename:sub(1, -5))
				return message
			end
		else
			ivar2:Log('error', 'Unable to load %s title handler %s: %s.', kind, filename:sub(1, -5), customError)
		end
	end

	-- Custom hosts
	do
		local path = 'modules/title/sites/'
		_PROXY.customHosts = customHosts

		for fn in lfs.dir(path) do
			if fn:match'%.lua$' then
				loadFile('custom',  path, fn)
			end
		end

		_PROXY.customHosts = nil
	end

	-- Custom post processing
	do
		local path = 'modules/title/post/'
		for fn in lfs.dir(path) do
			if fn:match'%.lua$' then
				local func = loadFile('post',  path, fn)
				if(func) then
					table.insert(customPost, func)
				end
			end
		end
	end
end

local fetchInformation = function(queue, lang)
	local info = uri_parse(queue.url)
	if(info) then
		info.url = queue.url
		if(info.path == '') then
			queue.url = queue.url .. '/'
		end

		local host = info.host:gsub('^www%.', '')
		for pattern, customHandler in next, customHosts do
			if(host:match(pattern) and customHandler(queue, info)) then
				-- Let the queue know it's being customhandled
				-- Can be used in postproc to make better decisions
				queue.customHandler = true
				return
			end
		end
	end

	simplehttp({
		url = parseAJAX(queue.url),
		headers = {
			['Accept-Language'] = lang
		}},
		function(data, _, response)
			local message = handleData(response.headers, data)
			if(#queue.url > 80) then
				ivar2.x0(queue.url, function(short)
					if message then
						queue:done(string.format('Short URL: %s - %s', short, message))
					else
						queue:done(string.format('Short URL: %s', short))
					end
				end)
			else
				queue:done(message)
			end
		end,
		true,
		DL_LIMIT
	)
end

local postProcess = function(source, destination, self, msg)
	for _, customHandler in next, customPost do
		customHandler(source, destination, self, msg)
	end
end

return {
	PRIVMSG = {
		function(self, source, destination, argument)
			-- We don't want to pick up URLs from commands.
			if(argument:match'^%p') then return end

			-- Handle CTCP ACTION
			if(argument:sub(1,1) == '\001' and argument:sub(-1) == '\001') then
				argument = argument:sub(9, -2)
			end

			local tmp = {}
			local tmpOrder = {}
			local index = 1
			for split in argument:gmatch('%S+') do
				for i=1, #patterns do
					local _, count = split:gsub(patterns[i], function(url)
						-- URLs usually do not end with , Strip it.
						url = url:gsub(',$', '')

						if(url:sub(1,4) ~= 'http') then
							url = 'http://' .. url
						end

						self.event:Fire('url', self, source, destination, argument, url)
						url = smartEscape(url)

						if(not tmp[url]) then
							table.insert(tmpOrder, url)
							tmp[url] = index
						else
							tmp[url] = string.format('%s+%d', tmp[url], index)
						end
					end)

					if(count > 0) then
						index = index + 1
						break
					end
				end
			end

			local lang = self:DestinationLocale(destination)
			if (lang:match('^nn')) then
				lang = 'nn, nb'
			elseif(lang:match('^nb')) then
				lang = 'nb, nn'
			else -- The default
				lang = 'en'
			end

			if(#tmpOrder > 0) then
				local output = {
					num = #tmpOrder,
					source = source,
					destination = destination,
					queue = {},
				}

				for i=1, #tmpOrder do
					local url = tmpOrder[i]
					output.queue[i] = {
						index = tmp[url],
						url = url,
						done = function(myself, msg)
							myself.output = msg

							postProcess(source, destination, myself, argument)
							handleOutput(output)
						end,
					}
					fetchInformation(output.queue[i], lang)
				end
			end
		end,
	},
}
