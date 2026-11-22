-- luacheck: ignore customHosts handleData limitOutput DL_LIMIT
local util = require'util'
local simplehttp = util.simplehttp
local html2unicode = require'html'
local trim = util.trim

local UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'

-- Collect <meta> tags. og:image repeats for carousels, so it gets its own list.
local function parseMeta(data)
	local meta, images = {}, {}
	for tag in data:gmatch('<%s*meta%s+[^>]*>') do
		local prop = tag:match('property%s*=%s*"([^"]*)"') or tag:match('name%s*=%s*"([^"]*)"')
		local content = tag:match('content%s*=%s*"([^"]*)"')
		if(prop and content) then
			content = trim(html2unicode(content))
			if(#content > 0) then
				if(prop == 'og:image') then
					table.insert(images, content)
				elseif(not meta[prop]) then
					meta[prop] = content
				end
			end
		end
	end

	return meta, images
end

-- Full size images (and video poster frames) are served signed, so keep the query string.
local function pickMedia(meta, images)
	for _, key in ipairs{'og:video:secure_url', 'og:video:url', 'og:video', 'twitter:player:stream'} do
		if(meta[key]) then
			return meta[key], 'video'
		end
	end

	for _, url in ipairs(images) do
		-- rsrc.php is the placeholder avatar served for missing or private posts.
		if(not url:match('/rsrc%.php')) then
			return url, 'image'
		end
	end
end

local titleHandler = function(queue, info)
	local path = info.path or ''
	-- Profiles and search pages have no post media to extract.
	if(not (path:match('^/share/') or path:match('^/t/') or path:match('/post/'))) then
		return false
	end

	simplehttp({
		url = info.url,
		headers = {['User-Agent'] = UA},
	}, function(data, _, response)
		if(not data) then return end

		-- Nothing extracted: fall back to whatever the generic handler makes of it.
		local bail = function()
			queue:done(handleData(response.headers, data))
		end

		local meta, images = parseMeta(data)

		-- Deleted, private or moved posts don't carry a post og:url.
		if(not (meta['og:url'] or ''):match('/post/')) then
			return bail()
		end

		local media, kind = pickMedia(meta, images)
		if(not media) then
			return bail()
		end

		local display, handle = (meta['og:title'] or ''):match('^(.-)%s*%((@[^)]+)%)%s*on%s+Threads$')
		if(display and handle) then
			display = ('%s (%s)'):format(display, handle)
		else
			display = meta['og:title']
		end

		local text = limitOutput(trim((meta['og:description'] or ''):gsub('%s%s+', ' ')))

		local bits = {}
		if(display and display ~= '') then
			table.insert(bits, ('<%s>'):format(display))
		end
		if(text ~= '') then
			table.insert(bits, text)
		end

		local width, height = meta['og:image:width'], meta['og:image:height']
		if(width and height) then
			table.insert(bits, ('[ %sx%s ]'):format(width, height))
		end
		if(#images > 1) then
			table.insert(bits, ('[%s +%d]'):format(kind, #images - 1))
		else
			table.insert(bits, util.bold(kind))
		end

		local emit = function(mediaurl)
			table.insert(bits, mediaurl)
			queue:done(table.concat(bits, ' '))
		end

		-- The CDN links are signed and long, so hand out a redirect when possible.
		if(ivar2.shorten) then
			ivar2.shorten(media, emit)
		else
			emit(media)
		end
	end, true, DL_LIMIT)

	return true
end

customHosts['^threads%.'] = titleHandler
