local simplehttp = require'simplehttp'
local json = require'json'

local utify8 = function(str)
	str = str:gsub("\\u(....)", function(n)
		n = tonumber(n, 16)

		if(n < 128) then
			return string.char(n)
		elseif(n < 2048) then
			return string.char(192 + ((n - (n % 64)) / 64), 128 + (n % 64))
		else
			return string.char(224 + ((n - (n % 4096)) / 4096), 128 + (((n % 4096) - (n % 64)) / 64), 128 + (n % 64))
		end
	end)

	return str
end

local headers = {
	['Authorization'] = string.format("Client-ID %s", ivar2.config.imgurClientID)
}

-- Yes...
local nsfw = {
	['nsfw'] = true,
	['gonewild'] = true,
}

local generateTitle = function(gallery, withURL)
	local out = {}

	if(withURL) then
		table.insert(out, string.format("http://imgur.com/%s", gallery.id))
	end

	if(type(gallery.title) == "string") then
		if(withURL) then
			table.insert(out, "-")
		end

		table.insert(out, gallery.title)
	end

	local tags = {}
	if(gallery.with and gallery.height) then
		table.insert(tags, string.format("%dx%d", gallery.width, gallery.height))
	end

	if(gallery.ups and gallery.downs) then
		table.insert(tags, string.format("+%d/-%d", gallery.ups, gallery.downs))
	end

	if(nsfw[gallery.section]) then
		table.insert(tags, 'NSFW')
	end

	if(gallery.animated) then
		table.insert(tags, "gif")
	end

	if(gallery.images_count) then
		table.insert(tags, string.format("%d images", gallery.images_count))
	end

	if(gallery.views) then
		table.insert(tags, string.format("%d views", gallery.views))
	end

	table.insert(out, string.format("[%s]", table.concat(tags, ", ")))

	return table.concat(out, " ")
end

local function handleOutput(queue, hash, data, withURL, try)
	data = utify8(data)
	data = json.decode(data)
	local gallery = data.data

	if(data.status == 404) then
		local url = ('https://api.imgur.com/3/image/%s.json'):format(hash)
		return simplehttp(
			{
				url = url,
				headers = headers
			},

			function(data)
				return handleOutput(queue, hash, data, withURL, true)
			end,
			true,
			DL_LIMIT
		)
	elseif(try and type(gallery.title) == 'function' and gallery.section) then
		local section = gallery.section
		local url = ('https://api.imgur.com/3/gallery/r/%s/%s.json'):format(section, hash)
		return simplehttp(
			{
				url = url,
				headers = headers
			},

			function(data)
				return handleOutput(queue, hash, data, withURL)
			end,
			true,
			DL_LIMIT
		)
	end

	queue:done(generateTitle(gallery, withURL))
end

customHosts['^imgur%.com'] = function(queue, info)
	if(not info.path) then return end

	local section, hash = info.path:match('/(r?/?%w+)/([^.]+)$')
	if(not hash) then return end

	if(section:sub(1, 2) == "r/") then
		section = "gallery/" .. section
	end

	local url
	if(section == 'a') then
		url = ('https://api.imgur.com/3/album/%s'):format(hash)
	else
		url = ('https://api.imgur.com/3/%s/%s.json'):format(section, hash)
	end

	simplehttp(
		{
			url = url,
			headers = headers,
		},

		function(data, _, response)
			return handleOutput(queue, hash, data)
		end,
		true,
		DL_LIMIT
	)

	return true
end

customHosts['i%.imgur%.com'] = function(queue, info)
	if(not info.path) then return end

	local hash = info.path:match('/([^.]+)%.[a-zA-Z]+$')
	if(not hash) then return end

	local url = ('https://api.imgur.com/3/gallery/%s.json'):format(hash)
	simplehttp(
		{
			url = url,
			headers = headers,
		},

		function(data, _, response)
			return handleOutput(queue, hash, data, true)
		end,
		true,
		DL_LIMIT
	)

	return true
end
