local simplehttp = require'simplehttp'
local html2unicode = require'html'
local date = require'date'

local urlEncode = function(str)
	return str:gsub(
		'([^%w ])',
		function (c)
			return string.format ("%%%02X", string.byte(c))
		end
	):gsub(' ', '+')
end

local monthName = {
	Jan = '01',
	Feb = '02',
	Mar = '03',
	Apr = '04',
	May = '05',
	Jun = '06',
	Jul = '07',
	Aug = '08',
	Sep = '09',
	Oct = '10',
	Nov = '11',
	Dec = '12'
}

local handleDate = function(str)
	if(str ~= '') then
		local month, day, year = str:match('([^/]+)/([^/]+)/([^/]+)')
		if(month and day and year) then
			return string.format('%s.%s.%s', day, monthName[month], year:sub(-2))
		end

		local month, year = str:match('([^/]+)/([^/]+)')
		if(month and year) then
			return string.format('%s.%s.%s', '??', monthName[month], year:sub(-2))
		end

		return str
	else
		return '?'
	end
end

local handleGenres = function(str)
	local genres = {}
	str:gsub(' | ', '|'):gsub('[^|]+', function(g) table.insert(genres, g) end)
	return table.concat(genres, ', ')
end

local handleEpisode = function(str, raw)
	local num, name, date = str:match('([^%^]+)%^([^%^]+)%^([^%^]+)')

	if(raw) then
		return num, name, date
	else
		return string.format('%s %s', num, handleDate(date))
	end
end

local getTimeOffset = function(timestamp)
	local utc = os.date('!*t', timestamp)
	local loc = os.date('*t', timestamp)
	loc.isdst = false

	return os.difftime(os.time(loc), os.time(utc))
end

local handleAirtime = function(timestamp)
	timestamp = timestamp + getTimeOffset(timestamp)
	local relTime = date.relativeTimeShort(timestamp)
	if(relTime) then
		return relTime
	end

	return 'In the future!'
end

local handleData = function(str)
	local data = {}

	for line in str:gmatch('[^\n]+') do
		local key, value = line:match('([^@]+)@(.*)')
		data[key] = value
	end

	return data
end

local out = function(data)
	local output = string.format('%s', html2unicode(data['Show Name']))

	if(data['Started'] and data['Ended']) then
		output = output .. string.format(' (%s till %s)', handleDate(data['Started']), handleDate(data['Ended']))
	end

	if(data['Status']) then
		output = output .. ' ' .. data['Status']
	end

	if(data['Genres']) then
		output = output .. ' // ' .. handleGenres(data['Genres'])
	end

	if(data['Latest Episode']) then
		output = output .. ' | Latest: ' .. handleEpisode(data['Latest Episode'])
	end

	if(data['Next Episode']) then
		output = output .. ' | Next: ' .. handleEpisode(data['Next Episode'])

		if(data['RFC3339']) then
			output = output .. ' (ETA: ' .. handleAirtime(data['GMT+0 NODST']) .. ')'
		end
	end

	if(data['Show URL']) then
		output = output .. ' | ' .. data['Show URL']
	end

	return output
end

local handle = function(self, source, destination, input)
	simplehttp(
		('http://services.tvrage.com/tools/quickinfo.php?show=%s'):format(urlEncode(input)),
		function(data)
			if(data:sub(1, 15) == 'No Show Results') then
				self:Msg('privmsg', destination, source, '%s: %s', source.nick, 'Invalid show? :(')
			else
				local output = out(handleData(data))
				if(output) then
					self:Msg('privmsg', destination, source, output)
				end
			end
		end
	)
end

return {
	PRIVMSG = {
		['^.tv (.+)$'] = handle,
		['^.tvr (.+)$'] = handle,
		['^.tvrage (.+)'] = handle,
	},
}
