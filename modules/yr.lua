-- vim: set noexpandtab:
local sql = require'lsqlite3'
local iconv = require'iconv'

local utf2iso = iconv.new('iso-8859-15', 'utf-8')

local days = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

local lower = ivar2.util.utf8.lower

local lang = 'en'
local getUrl

local arrow = function(dir)
	-- Turn the direction of arrow to the way wind is coming from
	local utf8arrow = ivar2.util.utf8.arrow
	local ndir = dir:gsub('.', function(n)
		if     n == 'N' then n = 'S'
		elseif n == 'E' then n = 'W'
		elseif n == 'S' then n = 'N'
		elseif n == 'W' then n = 'E' end
		return n
	end)
	return utf8arrow(ndir)
end

local parseDate = function(datestr)
	local year, month, day, hour, min, sec = datestr:match("([^-]+)%-([^-]+)%-([^T]+)T([^:]+):([^:]+):(%d%d)")
	return os.time{
		year = year,
		month = month,
		day = day,
		hour = hour,
		min = min,
		sec = sec,
	}
end

local i18n = {
	['Current weather in'] = {
		nn = 'Vêret no,',
		nb = 'Nåværende,'
	},
	['feels like'] = {
		nn = 'følt',
		nb = 'følt'
	},
	['Tonight'] = {
		nn = 'I kveld',
		nb = 'I kveld'
	},
	['Tomorrow'] = {
		nn = 'I morgon',
		nb = 'I morgen'
	},
	['Sun'] = {
		nn = 'Sun',
		nb = 'Søn'
	},
	['Mon'] = {
		nn = 'Mån',
		nb = 'Man'
	},
	['Tue'] = {
		nn = 'Tys',
		nb = 'Tir'
	},
	['We'] = {
		nn = 'Ons',
		nb = 'Ons'
	},
	['Thu'] = {
		nn = 'Tor',
		nb = 'Tor'
	},
	['Fri'] = {
		nn = 'Fre',
		nb = 'Fre'
	},
	['Sat'] = {
		nn = 'Lau',
		nb = 'Lør'
	},
	['Longterm for'] = {
		nn = 'Langtidsvarsel for',
		nb = 'Langtidsvarsel for'
	},
}
local _ = function(s)
	if i18n[s] and i18n[s][lang] then
		return i18n[s][lang]
	end
	return s
end

local feelsLike = function(celsius, wind)
	if not tonumber(wind) then return celsius end
	local V = wind * 3.6
	return math.floor(13.12 + 0.6215 * celsius - 11.37 * V^0.16 + 0.3965 * celsius * V^0.16 + .5)
end

-- yr has it's own quirks for URL encoding
local yrUrlEncode = function(str)
	return ivar2.util.urlEncode(str):gsub('%+', '_')
end

local formatPeriod = function(period)
	local out = {}

	table.insert(out, string.format("%s, %s°C (%s %s°C)", period.symbol.name, period.temperature.value, _('feels like'), period.temperature.feels, period.temperature.feels))

	local rain = period.precipitation
	if(rain.value ~= "0") then
		if(rain.minvalue and rain.maxvalue) then
			table.insert(out, string.format("%s-%s mm", rain.minvalue, rain.maxvalue))
		else
			table.insert(out, string.format("%s mm", rain.value))
		end
	end

	table.insert(out,
		string.format(
			"%s %s %s %s mps",
			arrow(period.windDirection.code:sub(-2, -1)),
			period.windSpeed.name,
			period.windDirection.name,
			period.windSpeed.mps
		)
	)

	return table.concat(out, ", ")
end

local formatShortPeriod = function(period)
	local wday = os.date('*t', period.from)['wday']
	return string.format(
		"\002%s\002: %s, %s°C (%s %s°C)",
		_(days[wday]),
		period.symbol.name,
		period.temperature.value,
		_('feels like'),
		period.temperature.feels
	)
end

local handleData = function(type, line)
	local out = {}
	local data = line:match(string.format("<%s (.-) />", type))
	if not data then return end

	string.gsub(data, '(%w+)="([^"]+)"', function(a, b)
		out[a] = b
	end)

	return out
end

local function handleOutput(self, source, destination, seven, data, city, try)
	local location = data:match("<location>(.-)</location>")
	if(not location and not try) then
		local curl = {url=("http://yr.no/place/%s/%s/%s~%s/varsel.xml"):format(
			yrUrlEncode(city.countryName),
			yrUrlEncode(city.adminName1),
			yrUrlEncode(city.toponymName),
			city.geonameId
		)}
		ivar2.util.simplehttp(
			getUrl(self, source, destination, curl), function(data)
				handleOutput(self, source, destination, seven, data, city, true)
			end
		)
	end

	local name = location:match("<name>([^<]+)</name>")
	local country = location:match("<country>([^<]+)</country>")

	local overview = data:match('<link id="overview" url="([^"]+)" />')
	local longterm = data:match('<link id="longTermForecast" url="([^"]+)" />')

	local periods = {}
	local tabular = data:match("<tabular>(.*)</tabular>")
	for from, to, period, data in tabular:gmatch([[<time from="([^"]+)" to="([^"]+)" period="([^"]+)">(.-)</time>]]) do
		local time = {
			from = parseDate(from),
			to = parseDate(to),
			period = period
		}

		time.symbol = handleData('symbol', data)
		time.precipitation = handleData('precipitation', data)
		time.windDirection = handleData('windDirection', data)
		time.windSpeed = handleData("windSpeed", data)
		time.temperature = handleData('temperature', data)
		time.temperature.feels = feelsLike(time.temperature.value, time.windSpeed.mps)
		time.pressure = handleData('pressure', data)

		table.insert(periods, time)
	end

	local clocale = ivar2:DestinationLocale(destination)
	-- TODO support personal language here too
	if (clocale:match('^nn')) then
		lang = 'nn'
	elseif(clocale:match('^nb')) then
		lang = 'nb'
	else -- The default
		lang = 'en'
	end

	local time = os.date("*t")
	time.day = time.day + 1
	time.hour = 0
	time.min = 0
	time.sec = 0
	local nextDay = os.time(time)
	local out = {}
	if(seven) then
		for i=1, #periods do
			local period = periods[i]
			if(period.from > nextDay and period.period == "2") then
				table.insert(out, period)
			end

			if(#out == 7) then
				break
			end
		end

		for i=1, #out do
			out[i] = formatShortPeriod(out[i])
		end

		table.insert(out, 1, string.format('%s \002%s\002 (%s)', _('Longterm for'), name, country))
		table.insert(out, longterm)
	else
		local now = periods[1]
		local later = periods[2]

		if(later.from >= nextDay) then
			later = nil
		end

		local tomorrow
		for i=3, #periods do
			local period = periods[i]
			if(period.from > nextDay and period.period == "2") then
				tomorrow = period

				break
			end
		end

		table.insert(out, string.format("%s \002%s\002 (%s): %s", _('Current weather in'), name, country, formatPeriod(now)))

		if(later) then
			table.insert(out, string.format("\002%s\002: %s", _('Tonight'), formatPeriod(later)))
		end

		if(tomorrow) then
			table.insert(out, string.format("\002%s\002: %s", _('Tomorrow'), formatPeriod(tomorrow)))
		end

		table.insert(out, overview)
	end

	ivar2:Msg('privmsg', destination, source, table.concat(out, " - "))
end

local splitInput = function(input)
	input = lower(ivar2.util.trim(input))

	if(input:find(',', 1, true)) then
		local place, country = input:match('([^,]+),(.+)')
		country = ivar2.util.trim(country):upper()

		return place, country
	end

	return input
end

getUrl = function(self, source, destination, place)
	-- Get language specific URL
	local lang = ivar2.persist['yr:lang:'..source.nick]
	if lang then
		return place.url:gsub('/place/', '/'..lang..'/')
	end

	local clocale = self:DestinationLocale(destination)
	if (clocale:match('^nn')) then
		return place.url:gsub('/place/', '/stad/')
	elseif(clocale:match('^nb')) then
		return place.url:gsub('/place/', '/sted/')
	end

	return place.url
end

local getPlace = function(self, source, destination, input)
	if(not input or input == '') then
		local persist = self.persist['yr:place:'..source.nick]
		if(not persist) then
			local patt = self:ChannelCommandPattern('^%pset yr <location>', "yr", destination):sub(1)
			self:Msg('privmsg', destination, source, 'Usage: '..patt)
			return
		end

		input = persist
	end

	return splitInput(input)
end

local getPlaceNorway = function(place)
	local db = sql.open("cache/places-norway.sql")
	local selectStmt = db:prepare("SELECT name, url FROM places WHERE name = ? OR name = ?")

	local placeISO = utf2iso:iconv(place)
	selectStmt:bind_values(place, placeISO)

	local iter, vm = selectStmt:nrows()
	local data = iter(vm)

	db:close()

	return data
end

local apiBase = 'http://api.geonames.org/searchJSON?name=%s&featureClass=P&featureClass=S&username=haste'
return {
	PRIVMSG = {
		['^%pyr(7?)%s*(.*)$'] = function(self, source, destination, seven, input)
			local place, country = getPlace(self, source, destination, input)
			local result = getPlaceNorway(place)

			if(result) then
				self.util.simplehttp(
					getUrl(self, source, destination, result),
					function(data)
						handleOutput(self, source, destination, seven == '7', data)
					end
				)
				return
			end

			local url = apiBase:format(self.util.urlEncode(place))
			if(country) then
				url = url .. '&country=' .. country
			end

			self.util.simplehttp(
				url,
				function(data)
					local json = self.util.json.decode(data)
					if(json.totalResultsCount == 0) then
						return self:Msg('privmsg', destination, source, "Does that place even exist?")
					end

					local city = json.geonames[1]
					if(city.adminName1 == "") then city.adminName1 = "Other" end
					local curl = {url=("http://yr.no/place/%s/%s/%s/varsel.xml"):format(
						yrUrlEncode(city.countryName),
						yrUrlEncode(city.adminName1),
						yrUrlEncode(city.toponymName))
					}

					self.util.simplehttp(
						getUrl(self, source, destination, curl), function(data)
							handleOutput(self, source, destination, seven == '7', data, city)
						end
					)
				end
			)
		end,

		['^%pset yr (.+)$'] = function(self, source, destination, location)
			self.persist['yr:place:'..source.nick] = location
			reply('Location set to %s', location)
		end,

		['^%pset yrlang (.+)$'] = function(self, source, destination, input)
			local languages = {
				['nynorsk'] = 'stad',
				['bokmål'] = 'sted',
				['english'] = 'place',
			}

			input = lower(self.util.trim(input))
			local lng = languages[input]
			if(lng) then
				self.persist['yr:lang:'..source.nick] = lng
				reply('I shall not forget. I am good at remembering things.')
			else
				reply('Unknown language: %s, use bokmål, nynorsk, english', lng)
			end
		end,
	}
}
