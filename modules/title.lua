local iconv = require"iconv"
local parse = require"socket.url".parse
local patterns = {
	-- X://Y url
	"^(https?://%S+)",
	"%f[%S](https?://%S+)",
	-- www.X.Y url
	"^(www%.[%w_-%%]+%.%S+)",
	"%f[%S](www%.[%w_-%%]+%.%S+)",
}

local danbooru = function(path)
	local path = path['path']

	if(path and path:match'/data/([^%.]+)') then
		local md5 = path:match'/data/([^%.]+)'
		local xml, s = utils.http('http://danbooru.donmai.us/post/index.xml?tags=md5:'..md5)
		if(s == 200) then
			local id = xml:match' id="(%d+)"'
			local tags = xml:match'tags="([^"]+)'

			return string.format('http://danbooru.donmai.us/post/show/%s/ - %s', id, tags)
		elseif(s == 503) then
			return string.format('http://danbooru.donmai.us/post?tags=md5:%s', md5)
		else
			return string.format('Server returned: %d', s)
		end
	end
end

local customLookup = {
	['danbooru.donmai.us'] = danbooru,
	['miezaru.donmai.us'] = danbooru,
	['hijiribe.donmai.us'] = danbooru,
	['open.spotify.com'] = function(path, url)
		local path = path['path']

		if(path and path:match'/(%w+)/(.+)') then
			local type, id = path:match'/(%w+)/(.+)'
			local old = socket.http.USERAGENT
			socket.http.USERAGENT = 'Otravi/1.0'
			local content = utils.http(url)
			socket.http.USERAGENT = old
			local title = content:match"<title>(.-)</title>"

			return string.format('%s: spotify:%s:%s', title, type, id)
		end
	end,
	['s3.amazonaws.com'] = function(path)
		local path = path['path']

		if(path and path:match'/danbooru/([^%.]+)') then
			local md5 = path:match'/danbooru/([^%.]+)'
			local xml, s = utils.http('http://danbooru.donmai.us/post/index.xml?tags=md5:'..md5)
			if(s == 200) then
				local id = xml:match' id="(%d+)"'
				local tags = xml:match'tags="([^"]+)'

				return string.format('http://danbooru.donmai.us/post/show/%s/ - %s', id, tags)
			end
		end
	end,
}

local renameCharset = {
	['x-sjis'] = 'sjis',
}

local validProtocols = {
	['http'] = true,
	['https'] = true,
}

local getTitle = function(url, offset)
	local path = parse(url)
	local host = path['host']:gsub('^www%.', '')

	if(customLookup[host]) then
		local title = customLookup[host](path, url)
		if(title) then
			return title
		end
	end

	local body, status, headers = utils.http(url)
	if(body) then
		local charset = body:lower():match'<meta.-content=["\'].-(charset=.-)["\'].->'
		if(charset) then
			charset = charset:match"charset=(.+)$?;?"
		end

		if(not charset) then
			charset = body:match'<%?xml.-encoding=[\'"](.-)[\'"].-%?>'
		end

		if(not charset) then
			local tmp = utils.split(headers['content-type'], ' ')
			for _, v in pairs(tmp) do
				if(v:lower():match"charset") then
					charset = v:lower():match"charset=(.+)$?;?"
					break
				end
			end
		end

		local title = body:match"<[tT][iI][tT][lL][eE]>(.-)</[tT][iI][tT][lL][eE]>"

		if(title) then
			for _, pattern in ipairs(patterns) do
				title = title:gsub(pattern, '<snip />')
			end
		end

		if(charset and title and charset:lower() ~= "utf-8") then
			charset = charset:gsub("\n", ""):gsub("\r", "")
			charset = renameCharset[charset] or charset
			local cd, err = iconv.new("utf-8", charset)
			if(cd) then
				title = cd:iconv(title)
			end
		end

		if(title and title ~= "" and title ~= '<snip />') then
			title = utils.decodeHTML(title)
			title = title:gsub("[%s%s]+", " ")

			if(#url >= 105) then
				local short = utils.x0(url)
				if(short ~= url) then
					title = "Downgraded URL: " ..short.." - "..title
				end
			end

			return title
		end
	end
end

local found = 0
local urls
local gsubit = function(url)
	found = found + 1

	local total = 1
	for k in pairs(urls) do
		total = total + 1
	end

	if(not url:match"://") then
		url = "http://"..url
	elseif(not validProtocols[url:match'^[^:]+']) then
		return
	end

	-- Strip out the anchors.
	url = url:gsub('#.+', '')
	if(not urls[url]) then
		local limit = 100
		local title = getTitle(url)
		if(#title > limit) then
			title = title:sub(1, limit)
			if(#title == limit) then
				-- Clip it at the last space:
				title = title:match('^.* ')
			end
		end

		urls[url] = {
			n = found,
			m = total,
			title = title,
		}
	else
		urls[url].n = string.format("%s+%d", urls[url].n, found)
	end
end

return {
	["^:(%S+) PRIVMSG (%S+) :(.+)$"] = function(self, src, dest, msg)
		if(self:srctonick(src) == self.config.nick or msg:sub(1,1) == '!' or self:srctonick(src):match"^CIA") then return end
		urls, found = {}, 0
		for key, msg in pairs(utils.split(msg, " ")) do
			for _, pattern in ipairs(patterns) do
				msg:gsub(pattern, gsubit)
			end
		end

		if(next(urls)) then
			local out = {}
			for url, data in pairs(urls) do
				if(data.title) then
					table.insert(out, data.m, string.format("\002[%s]\002 %s", data.n, data.title))
				end
			end

			if(#out > 0) then self:msg(dest, src, table.concat(out, " ")) end
		end
	end,
}
