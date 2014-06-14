local simplehttp = require'simplehttp'
local zlib = require'zlib'
local anidbSearch = require'anidbsearch'
local html2unicode = require'html'
require'tokyocabinet'
require'logging.console'

local catWhitelist = {
	['Action'] = true,
	['Adventure'] = true,
	['Angst'] = true,
	['Art'] = true,
	['Band'] = true,
	['Clubs'] = true,
	['College'] = true,
	['Comedy'] = true,
	['Daily Life'] = true,
	['Detective'] = true,
	['Drama'] = true,
	['Ecchi'] = true,
	['Fantasy'] = true,
	['Harem'] = true,
	['Horror'] = true,
	['Idol'] = true,
	['Josei'] = true,
	['Lolicon'] = true,
	['Magic'] = true,
	['Martial Arts'] = true,
	['Music'] = true,
	['Romance'] = true,
	['Sci-Fi'] = true,
	['Seinen'] = true,
	['Shotacon'] = true,
	['Shoujo'] = true,
	['Shounen'] = true,
	['Sports'] = true,
	['Super Power'] = true,
	['Thriller'] = true,
	['Tragedy'] = true,
	['Vampires'] = true,
}

local log = logging.console()
local anidb = tokyocabinet.hdbnew()

local trim = function(s)
	return s:match('^%s*(.-)%s*$')
end

local buildOutput = function(...)
	local out = {}

	for i=1, select('#', ...) do
		local str = select(i, ...)
		if(str) then table.insert(out, str) end
	end

	return table.concat(out)
end

local handleXML = function(xml)
	local error = xml:match('<error>([^<]+)</error>')
	if(error) then
		log:error(string.format('anidb: %s', error))
		return string.format('Error: %s', error)
	end

	local url = 'http://anidb.net/a' .. xml:match('id="(%d+)"')
	local type = xml:match('<type>([^<]+)</type>')
	local episodecount = tonumber(xml:match('<episodecount>([^<]+)</episodecount>'))
	local startdate = xml:match('<startdate>([^<]+)</startdate>') or '?'
	local enddate = xml:match('<enddate>([^<]+)</enddate>') or '?'

	startdate = startdate:gsub('%-', '.')
	enddate = enddate:gsub('%-', '.')

	local titles = {}
	for lang, type, title in xml:gmatch('<title xml:lang="([^"]+)" type="([^"]+)">([^<]+)</title>') do
		if(type == 'main') then
			titles.main = title
		elseif(lang == 'ja' and type == 'official') then
			titles.japanese = title
		end
	end

	local categories = {}
	do
		local weighted = {}
		local catString = xml:match('<categories>(.-)</categories>')
		if(catString) then
			for weight, name in catString:gmatch('weight="([^"]+)">\n<name>([^<]+)</name>') do
				if(catWhitelist[name]) then
					table.insert(weighted, {name = name, weight = tonumber(weight)})
				end
			end
			table.sort(weighted, function(a, b) return a.weight > b.weight end)
		end

		local i = 7
		repeat
			weighted[i] = nil
			i = i + 1
		until not weighted[i]

		for i=1,#weighted do
			table.insert(categories, weighted[i].name)
		end

		table.sort(categories)
	end

	local episodes, airedepisodes = {}, 0
	local today = os.date('%Y-%m-%d')
	local episodesString = xml:match('<episodes>\n(.-)</episodes>')
	if(episodesString) then
		for eptype, epno, airdate in episodesString:gmatch('type="([^"]+)">(%d+)</epno>.-<airdate>([^<]+)</airdate>') do
			if(eptype == '1') then
				local aired = airdate < today
				if(aired) then airedepisodes = airedepisodes + 1 end

				episodes[tonumber(epno)] = {airdate = airdate:gsub('%-', '.'), aired = aired}
			end
		end
	end

	local airing = airedepisodes ~= episodecount
	if(airedepisodes == 0) then airedepisodes = '?' end
	if(episodecount == 0 or enddate == '?') then episodecount = '?' end

	local rating
	do
		local permanent = xml:match('<permanent.->([^<]+)</permanent>')
		local temporary = xml:match('<temporary.->([^<]+)</temporary>')

		if(not airing) then
			rating = permanent
		else
			rating = temporary
		end

		if(not rating) then
			rating = permanent or temporary or 'no'
		end
	end

	return buildOutput(
		titles.main,
		titles.japanese and string.format(' // %s', titles.japanese),
		string.format(' (%s till %s) ', startdate, enddate),
		type,
		(type ~= 'Movie') and string.format(', %s/%s episodes', airedepisodes, episodecount),
		string.format(', %s rating', rating),
		#categories > 0 and string.format(' / %s', table.concat(categories, ', ')),
		string.format(' | %s', url)
	)
end

local doLookup = function(destination, source, aid)
	anidb:open('cache/anidb', anidb.OWRITER + anidb.OCREAT)

	-- Is it fresh and present in our cache?
	if(anidb[aid] and tonumber(anidb[aid .. ':time']) > os.time()) then
		log:debug(string.format('anidb: Fetching %d from cache.', aid))
		ivar2:Msg('privmsg', destination, source, anidb[aid])
		anidb:close()
		return
	else
		anidb:close()
		log:info(string.format('anidb: Requesting information on %d.', aid))

		simplehttp(
			('http://api.anidb.net:9001/httpapi?request=anime&aid=%d&client=ivarto&clientver=0&protover=1'):format(aid),
			function(data)
				local xml = zlib.inflate() (data)
				local output = html2unicode(handleXML(xml))
				if(output:sub(1,5) == 'Error') then
					ivar2:Msg('privmsg', destination, source, '%s: %s', source.nick, output)
				else
					anidb:open('cache/anidb', anidb.OWRITER + anidb.OCREAT)
					anidb:put(aid, output)
					-- Keep it for one day.
					anidb:put(aid .. ':time', os.time() + 86400)
					anidb:close()

					ivar2:Msg('privmsg', destination, source, output)
				end
			end,
			-- We have to close the socket ourselves if we want to stream it.
			nil
		)
	end
end

return {
	PRIVMSG = {
		['^%panidb (.+)$'] = function(self, source, destination, anime)
			-- Force a close in-case we didn't get to earlier.
			anidb:close()

			-- Relaod the DB.
			anidbSearch.reload()

			local aid = tonumber(anime)
			if(aid) then
				return doLookup(destination, source, aid)
			end

			local results = anidbSearch.lookup(trim(anime))
			local numResults = #results
			if(numResults == 0) then
				return self:Msg('privmsg', destination, source, 'No matches found :-(.')
			elseif(numResults == 1) then
				return doLookup(destination, source, results[1].aid)
			else
				do
					local w1000 = {}
					for i=1, numResults do
						local anime = results[i]
						if(anime.weight == 1e3) then
							table.insert(w1000, anime.aid)
						end
					end

					if(#w1000 == 1) then
						return doLookup(destination, source, w1000[1])
					end
				end

				do
					local out = {}
					for i=1, numResults do
						local anime = results[i]
						local aid = anime.aid
						local title = anime.title

							table.insert(out, string.format('\002[%s]\002 %s', aid, title))
						end

					return self:Msg(
						'privmsg', destination, source,
						table.concat(self:LimitOutput(destination, out, 1), ' ')
					)
				end
			end
		end,
	},
}
