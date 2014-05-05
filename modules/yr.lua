local simplehttp = require'simplehttp'
local sql = require'lsqlite3'
local iconv = require'iconv'
local json = require'json'

local utf2iso = iconv.new('iso-8859-15', 'utf-8')

local days = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

local urlEncode = function(str)
	return str:gsub(
		'([^%w ])',
		function (c)
			return string.format ("%%%02X", string.byte(c))
		end
	):gsub(' ', '_')
end

local trim = function(s)
	return s:match('^%s*(.-)%s*$')
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

local feelsLike = function(celsius, wind)
	local V = wind * 3.6
	return math.floor(13.12 + 0.6215 * celsius - 11.37 * V^0.16 + 0.3965 * celsius * V^0.16 + .5)
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

local handleObservationOutput = function(source, destination, data, city, try)
	local location = data:match("<location>(.-)</location>")
	if(not location and not try) then
		simplehttp(
			("http://yr.no/stad/%s/%s/%s~%s/varsel.xml"):format(
				urlEncode(city.countryName),
				urlEncode(city.adminName1),
				urlEncode(city.toponymName),
				city.geonameId
			),
			function(data)
				handleObservationOutput(source, destination, seven, data, city, true)
			end
		)
	end

	local name = location:match("<name>([^<]+)</name>"):lower():gsub("^%l", string.upper)

	local tabular = data:match("<observations>(.*)</observations>")
	for stno, sttype, name, distance, lat, lon, source, data in tabular:gmatch([[<weatherstation stno="([^"]+)" sttype="([^"]+)" name="([^"]+)" distance="([^"]+)" lat="([^"]+)" lon="([^"]+)" source="([^"]+)">(.-)</weatherstation]]) do
		local windDirection = handleData('windDirection', data)
		local windSpeed = handleData("windSpeed", data)
		if windSpeed then windSpeed = windSpeed.name else windSpeed = '' end
		local temperature = handleData('temperature', data)
		if windDirection then windDirection = windDirection.name else windDirection = '' end
		ivar2:Msg('privmsg', destination, source, '\002%s\002°C, %s %s (%s)', temperature.value, windDirection, windSpeed, name)
		-- Use the first result
		return
	end
end

local handleOutput = function(source, destination, seven, data, city, try)
	local location = data:match("<location>(.-)</location>")
	if(not location and not try) then
		simplehttp(
			("http://yr.no/stad/%s/%s/%s~%s/varsel.xml"):format(
				urlEncode(city.countryName),
				urlEncode(city.adminName1),
				urlEncode(city.toponymName),
				city.geonameId
			),
			function(data)
				handleOutput(source, destination, seven, data, city, true)
			end
		)
	end

	local name = location:match("<name>([^<]+)</name>"):lower():gsub("^%l", string.upper)
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

		table.insert(out, string.format("\002%s\002 (%s): %s", name, country, formatPeriod(now)))

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

local getPlace = function(input)
	input = trim(input):lower()
	local inputISO = utf2iso:iconv(input)

	local country
	if(input:find(',', 1, true)) then
		input, country = input:match('([^,]+),(.+)')
		country = trim(country):upper()
		inputISO, _ = input:match('([^,]+),(.+)')
	end

	local db = sql.open("cache/places-norway.sql")
	local selectStmt = db:prepare("SELECT name, url FROM places WHERE name = ? OR name = ?")
	selectStmt:bind_values(input, inputISO)

	local iter, vm = selectStmt:nrows()
	local place = iter(vm)
	place.name = trim(place.name)
	place.url = trim(place.url)

	db:close()
	return place
end

local urlBase = "http://api.geonames.org/hierarchyJSON?geonameId=%d&username=haste"
return {
	PRIVMSG = {
		['^!yr(7?) (.+)$'] = function(self, source, destination, seven, input)
			input = trim(input):lower()
			local place = getPlace(input)


			if(place) then
				-- use nynorsk text
				local url = place.url:gsub('/place/', '/stad/')
				simplehttp(
					url,
					function(data)
						handleOutput(source, destination, seven == '7', data)
					end
				)
				return
			end

			local inputISO = utf2iso:iconv(input)

			local country
			if(input:find(',', 1, true)) then
				input, country = input:match('([^,]+),(.+)')
				country = trim(country):upper()
				inputISO, _ = input:match('([^,]+),(.+)')
			end

			local db = sql.open("cache/places.sql")
			local selectStmt
			if(country) then
				selectStmt = db:prepare([[
				SELECT
					geonameid, name,countryCode, population
				FROM places
				WHERE
					(name = ? OR name = ?)
					AND countryCode = ?
				ORDER BY
				population DESC
				]])
				selectStmt:bind_values(input, inputISO, country)
			else
				selectStmt = db:prepare([[
				SELECT
					geonameid, name,countryCode, population
				FROM places
				WHERE
					(name = ? OR name = ?)
				ORDER BY
				population DESC
				]])
				selectStmt:bind_values(input, inputISO)
			end

			local iter, vm = selectStmt:nrows()
			local place = iter(vm)

			db:close()

			if(place) then
				simplehttp(
					urlBase:format(place.geonameid),
					function(data)
						data = json.decode(data)
						local city = data.geonames[#data.geonames]
						if(city.adminName1 == "") then city.adminName1 = "Other" end

						simplehttp(
							("http://yr.no/stad/%s/%s/%s/varsel.xml"):format(
								urlEncode(city.countryName),
								urlEncode(city.adminName1),
								urlEncode(city.toponymName)
							),
							function(data)
								handleOutput(source, destination, seven == '7', data, city)
							end
						)
					end
				)
			else
				ivar2:Msg('privmsg', destination, source, "Does that place even exist?")
			end
		end,
		['^!temp (.+)$'] = function(self, source, destination, input) 
			place = getPlace(input)

			if(place) then
				-- use nynorsk text
				local url = place.url:gsub('/place/', '/stad/')
				simplehttp(
					url,
					function(data)
						handleObservationOutput(source, destination, data)
					end
				)
				return
			end
		end,
	}
}
