local colorize = function(score)
    if tonumber(score) > 50 then
        return ivar2.util.red(string.format("%s%%", score))
    else
        return ivar2.util.green(string.format("%s%%", score))
    end
end

local parseData = function(source, destination, data, search)
	data = ivar2.util.json.decode(data)

	local found
	for i=1, #data.movies do
		local title = data.movies[i].title:lower()
		-- ha! ha! ha!
		if(title == search) then
			found = i
			break
		end
	end

	if(not found and not data.movies[1]) then
		return "Not even Rotten Tomatoes would rate that movie."
	end

	local movie = data.movies[found] or data.movies[1]
	local out = {}
	local ins = function(fmt, ...)
		for i=1, select('#', ...) do
			local val = select(i, ...)
			if(type(val) == 'nil' or val == -1) then
				return
			end
		end

		table.insert(
			out,
			string.format(fmt, ...)
		)
	end

	ins(
		"%s (%d)",
		ivar2.util.bold(movie['title']), movie['year'], movie['mpaa_rating'], movie['runtime']
	)

	if(movie['runtime'] ~= "") then
		ins("%s/%d min", movie['mpaa_rating'], movie['runtime'])
	else
		ins("%s", movie['mpaa_rating'])
	end

	ins("- Critics: %s", colorize(movie['ratings']['critics_score']))
	ins("(%s)", movie['ratings']['critics_rating'])

	ins("- Audience: %s", colorize(movie['ratings']['audience_score']))
	ins("(%s)", movie['ratings']['audience_rating'])

	ins("- %s", movie['critics_consensus'])

	return table.concat(out, " ")
end

local urlFormat = 'http://api.rottentomatoes.com/api/public/v1.0/movies.json?page_limit=5&apikey=%s&q=%s'
local handler = function(self, source, destination, input)
	local search = ivar2.util.urlEncode(ivar2.util.trim(input))

	ivar2.util.simplehttp(
		urlFormat:format(self.config.rottenTomatoesAPIKey, search),
		function(data)
			say(parseData(source, destination, data, input:lower()))
		end
	)
end

return {
	PRIVMSG = {
		['^%prt (.+)$'] = handler,
		['^%protten (.+)$'] = handler,
	},
}
