local util = require'util'
local simplehttp = util.simplehttp
local json = util.json
local urlEncode = util.urlEncode

local parseData = function(source, destination, data)
	data = json.decode(data)

	if(data and not data.Error) then
		local out = {}

		if(data.Title) then
			table.insert(out, string.format("\002%s\002", data.Title))
		end

		if(data.Year) then
			table.insert(out, string.format("(%d) -", data.Year))
		end

		if(data.Runtime and data.Rated and data.Type) then
			table.insert(out, string.format("%s/%s/%s,", data.Rated, data.Type, data.Runtime))
		end

		if(data.imdbRating) then
			table.insert(out, string.format("%s rating", data.imdbRating))
		end

		if(data.Genre) then
			table.insert(out, string.format("/ %s", data.Genre))
		end

		if(data.Plot) then
			table.insert(out, string.format("- %s", data.Plot))
		end

		if(data.imdbID) then
			table.insert(out, string.format("| http://imdb.com/title/%s", data.imdbID))
		end

		say(table.concat(out, ' '))
	else
		say('(%d) %s', data.code, data.error)
	end
end

local urlFormat = 'http://omdbapi.com/?t=%s'
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
		['^%pimdb (.+)$'] = handler,
	},
}
