local iconv = require"iconv"
local uri = require"handler.uri"

local simplehttp = require'simplehttp'
local html2unicode = require'html'
local nixio = require'nixio'

local uri_parse = uri.parse
local DL_LIMIT = 2^17

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

local trim = function(str)
	return str:match('^%s*(.-)%s*$')
end

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

	-- Header:
	local contentType = headers['Content-Type']
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
	local limit = 100
	if(#str > limit) then
		str = str:sub(1, limit)
		if(#str == limit) then
			-- Clip it at the last space:
			str = str:match('^.* ') .. '…'
		end
	end

	return str
end

local handleData = function(headers, data)
	local charset = guessCharset(headers, data)
	if(charset and charset ~= 'utf-8') then
		local cd, err = iconv.new("utf-8", charset)
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
do
	local _PROXY = setmetatable(
		{
			customHosts = customHosts,
			DL_LIMIT = DL_LIMIT,

			ivar2 = ivar2,
			handleData = handleData,
			limitOutput = limitOutput,

		},{ __index = _G }
	)

	local path = 'modules/title/sites/'
	for custom in nixio.fs.dir(path) do
		local customFile, customError = loadfile(path .. custom)
		if(customFile) then
			setfenv(customFile, _PROXY)

			local success, message = pcall(customFile, ivar2)
			if(not success) then
				ivar2:Log('error', 'Unable to execute custom title handler %s: %s.', custom:sub(1, -5), message)
			else
				ivar2:Log('info', 'Loading custom title handler: %s.', custom:sub(1, -5))
			end
		else
			ivar2:Log('error', 'Unable to load custom title handler %s: %s.', custom:sub(1, -5), customError)
		end
	end
end

local fetchInformation = function(queue)
	local info = uri_parse(queue.url)
	info.url = queue.url
	if(info.path == '') then
		queue.url = queue.url .. '/'
	end

	local host = info.host:gsub('^www%.', '')
	for pattern, customHandler in next, customHosts do
		if(host:match(pattern) and customHandler(queue, info)) then
			return
		end
	end

	simplehttp(
		parseAJAX(queue.url):gsub('#.*$', ''),

		function(data, _, response)
			local message = handleData(response.headers, data)
            queue:done(message)
		end,
		true,
		DL_LIMIT
	)
end

return {
	PRIVMSG = {
		function(self, source, destination, argument)
			-- We don't want to pick up URLs from commands.
			if(argument:sub(1,1) == '!') then return end

			local tmp = {}
			local tmpOrder = {}
			local index = 1
			for split in argument:gmatch('%S+') do
				for i=1, #patterns do
					local _, count = split:gsub(patterns[i], function(url)
						if(url:sub(1,4) ~= 'http') then
							url = 'http://' .. url
						end

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
						done = function(self, msg)
							self.output = msg
							handleOutput(output)
						end,
					}
					fetchInformation(output.queue[i])
				end
			end
		end,
	},
}
