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

local urlEncode = function(str)
	return str:gsub(
		'([^%w ])',
		function (c)
			return string.format ("%%%02X", string.byte(c))
		end
	):gsub(' ', '+')
end

local parseData = function(source, destination, data)
	data = utify8(data)
	data = json.decode(data)

	if(data and not data.error) then
		local out = {}
		data = data[1]

		if(data.title) then
			table.insert(out, string.format("\002%s\002", data.title))
		end

		if(data.year) then
			table.insert(out, string.format("(%d) -", data.year))
		end

		if(data.runtime and data.rated and data.type) then
			table.insert(out, string.format("%s/%s/%s,", data.rated, data.type, data.runtime[1]))
		end

		if(data.rating) then
			table.insert(out, string.format("%s rating", data.rating))
		end

		if(data.genres) then
			table.insert(out, string.format("/ %s", table.concat(data.genres, ', ')))
		end

		if(data.plot_simple) then
			table.insert(out, string.format("- %s", data.plot_simple))
		end

		if(data.imdb_id) then
			table.insert(out, string.format("| http://imdb.com/title/%s", data.imdb_id))
		end

		say(table.concat(out, ' '))
	else
		say('(%d) %s', data.code, data.error)
	end
end

local urlFormat = 'http://imdbapi.org/?q=%s'
local handler = function(self, source, destination, input)
	local search = urlEncode(input)

	simplehttp(
		urlFormat:format(search),
		function(data)
			parseData(source, destination, data)
		end
	)
end

return {
	PRIVMSG = {
		['^.imdb (.+)$'] = handler,
	},
}
