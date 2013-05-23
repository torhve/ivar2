local simplehttp = require'simplehttp'
local sql = require'lsqlite3'
local iconv = require'iconv'
local json = require'json'

local utf2iso = iconv.new('iso-8859-15', 'utf-8')

local urlEncode = function(str)
	return str:gsub(
		'([^%w ])',
		function (c)
			return string.format ("%%%02X", string.byte(c))
		end
	):gsub(' ', '+')
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

local formatPeriod = function(period)
	return string.format("%s, %s°C", period.symbol.name, period.temperature.value)
end

local handleData = function(type, line)
	local out = {}
	local data = line:match(string.format("<%s (.-) />", type))

	string.gsub(data, '(%w+)="([^"]+)"', function(a, b)
		out[a] = b
	end)

	return out
end

local handleOutput = function(source, destination, data)
	local location = data:match("<location>(.-)</location>")
	if(not location) then
		return ivar2:Msg('privmsg', destination, source, "haste should probably fix this...")
	end
	local name = location:match("<name>([^<]+)</name>")
	local country = location:match("<country>([^<]+)</country>")

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
		time.pressure = handleData('pressure', data)

		table.insert(periods, time)
	end

	local time = os.date("*t")
	time.day = time.day + 1
	time.hour = 0
	time.min = 0
	time.sec = 0
	local nextDay = os.time(time)
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

	local out = {}
	table.insert(out, string.format("Current weather in %s (%s): %s", name, country, formatPeriod(now)))

	if(later) then
		table.insert(out, string.format("Tonight: %s", formatPeriod(later)))
	end

	if(tomorrow) then
		table.insert(out, string.format("Tomorrow: %s", formatPeriod(tomorrow)))
	end

	ivar2:Msg('privmsg', destination, source, table.concat(out, " - "))
end

local urlBase = "http://api.geonames.org/hierarchyJSON?geonameId=%d&username=haste"
return {
	PRIVMSG = {
		['^!yr (.+)$'] = function(self, source, destination, input)
			input = trim(input)
			local inputISO = utf2iso:iconv(input)

			local db = sql.open("cache/places-norway.sql")
			local selectStmt = db:prepare("SELECT place, url FROM places WHERE place LIKE ? OR place LIKE ?")
			selectStmt:bind_values(input, inputISO)

			local iter, vm = selectStmt:nrows()
			local place = iter(vm)

			db:close()

			if(place) then
				simplehttp(
					place.url,
					function(data)
						handleOutput(source, destination, data)
					end
				)
				return
			end

			local country
			if(input:find(',', 1, true)) then
				input, country = input:match('([^,]+),(.+)')
				country = trim(country)
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
					(name LIKE ? OR name LIKE ?)
				AND countryCode LIKE ?
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
					(name LIKE ? OR name LIKE ?)
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
							("http://yr.no/place/%s/%s/%s/forecast.xml"):format(
								urlEncode(city.countryName),
								urlEncode(city.adminName1),
								urlEncode(city.toponymName)
							),
							function(data)
								handleOutput(source, destination, data)
							end
						)
					end
				)
			else
				ivar2:Msg('privmsg', destination, source, "Does that place even exist?")
			end
		end,
	}
}
