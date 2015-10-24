-- vim: set noexpandtab:
local sql = require'lsqlite3'
local iconv = require'iconv'

local utf2iso = iconv.new('iso-8859-15', 'utf-8')

local days = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

local lower = ivar2.util.utf8.lower

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

	table.insert(out, string.format("%s, %s°C (feels like %s°C)", period.symbol.name, period.temperature.value, period.temperature.feels, period.temperature.feels))

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
			"%s, %s %s mps",
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
		"\002%s\002: %s, %s°C (feels like %s°C)",
		days[wday],
		period.symbol.name,
		period.temperature.value,
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

local handleObservationOutput = function(self, source, destination, data)
	local tabular = data:match("<observations>(.*)</observations>")
	for stno, sttype, name, distance, lat, lon, source, data in tabular:gmatch([[<weatherstation stno="([^"]+)" sttype="([^"]+)" name="([^"]+)" distance="([^"]+)" lat="([^"]+)" lon="([^"]+)" source="([^"]+)">(.-)</weatherstation]]) do
		local windDirection = handleData('windDirection', data)
		local windSpeed = handleData("windSpeed", data)
		local windSpeedname = ''
		if windSpeed then windSpeedname = windSpeed.name end
		if windSpeed then windSpeed = windSpeed.mps else windSpeed = '' end
		local temperature = handleData('temperature', data)
		-- Continue to next observation if no temperature
		if temperature then
			local time = temperature.time:match('T([0-9][0-9]:[0-9][0-9])')
			if windDirection then windDirection = windDirection.name else windDirection = '' end
			local color
			if tonumber(temperature.value) > 0 then
				color = self.util.red
			else
				color = self.util.lightblue
			end
			-- Use the first result
			return '%s °C (feels like %s °C), %s %s (%s, %s)', color(temperature.value), color(feelsLike(temperature.value, windSpeed)), windDirection, windSpeedname, name, time
		end
	end
end

local function handleOutput(source, destination, seven, data, city, try)
	local location = data:match("<location>(.-)</location>")
	if(not location and not try) then
		ivar2.util.simplehttp(
			("http://yr.no/place/%s/%s/%s~%s/varsel.xml"):format(
				yrUrlEncode(city.countryName),
				yrUrlEncode(city.adminName1),
				yrUrlEncode(city.toponymName),
				city.geonameId
			),
			function(data)
				handleOutput(source, destination, seven, data, city, true)
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

		table.insert(out, 1, string.format('Longterm for \002%s\002 (%s)', name, country))
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

		table.insert(out, string.format("Current weather in \002%s\002 (%s): %s", name, country, formatPeriod(now)))

		if(later) then
			table.insert(out, string.format("\002Tonight\002: %s", formatPeriod(later)))
		end

		if(tomorrow) then
			table.insert(out, string.format("\002Tomorrow\002: %s", formatPeriod(tomorrow)))
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

local getUrl = function(self, source, destination, place)
	local lang = self.persist['yr:lang:'..source.nick]
	if(not lang) then
		return place.url
	else
		return place.url:gsub('/place/', '/'..lang..'/')
	end
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
					result.url,
					function(data)
						handleOutput(source, destination, seven == '7', data)
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

					self.util.simplehttp(
						("http://yr.no/place/%s/%s/%s/varsel.xml"):format(
							yrUrlEncode(city.countryName),
							yrUrlEncode(city.adminName1),
							yrUrlEncode(city.toponymName)
						),
						function(data)
							handleOutput(source, destination, seven == '7', data, city)
						end
					)
				end
			)
		end,

		-- Currently only handles Norwegian cities.
		['^%ptemp%s*(.*)$'] = function(self, source, destination, input)
			local place = getPlace(self, source, destination, input)
			local result = getPlaceNorway(place)

			if(result) then
				self.util.simplehttp(
					getUrl(self, source, destination, result),
					function(data)
						say(handleObservationOutput(self, source, destination, data))
					end
				)
			end
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
			local lang = languages[input]
			if(lang) then
				self.persist['yr:lang:'..source.nick] = lang
				reply('I shall not forget. I am good at remembering things.')
			else
				reply('Unknown language: %s, use bokmål, nynorsk, english', lang)
			end
		end,
	}
}
