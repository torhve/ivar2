local simplehttp = require'simplehttp'

local urlEncode = function(str)
	return str:gsub(
		'([^%w ])',
		function (c)
			return string.format ("%%%02X", string.byte(c))
		end
	):gsub(' ', '+')
end

local blacklistedShelves = {
	['series'] = true,
	['to-read'] = true,
	['favourites'] = true,
	['favorites'] = true,
}

local lookup = function(self, source, destination, id)
	simplehttp(
		string.format(
			"https://www.goodreads.com/book/show/%s?format=xml&key=%s",
			id,
			self.config.goodreadsAPIKey
		),

		function(data)
			if(data:find("Could not find this book.", 1, true)) then
				return self:Msg('privmsg', destination, sourcee, "Found no book with that id.")
			end

			local id = data:match("<id>([^>]+)</id>")
			local avgRating = data:match("<average_rating>([^>]+)</average_rating>")
			local work = data:match("<work>(.*)</work>")
			local day = work:match("<original_publication_day[^>]+>([^<]+)</original_publication_day>")
			local month = work:match("<original_publication_month[^>]+>([^<]+)</original_publication_month>")
			local year = work:match("<original_publication_year[^>]+>([^<]+)</original_publication_year>")
			local title = work:match("original_title>([^<]+)</original_title>")

			local date = {}
			if(day) then
				table.insert(date, string.format("%02d", day))
			end
			if(month) then
				table.insert(date, string.format("%02d", month))
			end
			if(year) then
				table.insert(date, year)
			end
			date = table.concat(date, "/")

			local authors = {}
			for author in data:match("<authors>(.-)</authors>"):gmatch("<author>(.-)</author>") do
				local name = author:match("<name>([^<]+)</name>")
				table.insert(authors, name)
			end

			local genres = {}
			for shelf in data:match("<popular_shelves>(.-)</popular_shelves>"):gmatch('<shelf name="([^"]+)"') do
				if(not blacklistedShelves[shelf]) then
					table.insert(genres, shelf)
				end
			end

			local out = {}
			if(title) then
				table.insert(out, string.format("\002%s\002", title))
			end
			if(#authors > 0) then
				table.insert(out, string.format("by %s", table.concat(authors, ", ")))
			end
			if(date) then
				table.insert(out, string.format("(%s)", date))
			end
			if(avgRating) then
				table.insert(out, string.format("\002Rating:\002 %s", avgRating))
			end
			if(#genres > 0) then
				table.insert(out, string.format("// %s", table.concat(genres, ", ")))
			end
			if(id) then
				table.insert(out, string.format("| https://www.goodreads.com/book/show/%s", id))
			end

			self:Msg('privmsg', destination, source, table.concat(out, " "))
		end,
		true,
		2^16
	)
end

local search = function(self, source, destination, title)
	simplehttp(
		string.format(
			"https://www.goodreads.com/search.xml?key=%s&q=%s",
			self.config.goodreadsAPIKey,
			urlEncode(title)
		),

		function(data)
			local books = {}
			for work in data:gmatch("<work>(.-)</work>") do
				local book = work:match("<best_book[^>]+>(.*)</best_book>")
				local id = book:match("<id[^>]+>([^<]+)</id>")
				local title = book:match("<title>([^<]+)</title>"):gsub(" %(.*, #%d+%)$", "")
				local author = book:match("<name>([^<]+)</name>"):gsub('(%u)%S* %l*%s*', '%1. ')

				table.insert(books, {
					id = id,
					title = title,
					author = author,
				})
			end

			local out = {}
			for i=1, #books do
				local book = books[i]
				table.insert(out, string.format("\002[%s]\002 %s by %s", book.id, book.title, book.author))
			end

			self:Msg(
				'privmsg', destination, source,
				table.concat(self:LimitOutput(destination, out, 1), ' ')
			)

			return books
		end,
		true,
		2^16
	)
end

return {
	PRIVMSG = {
		['%pgr (.*)$'] = function(self, source, destination, input)
			if(tonumber(input)) then
				lookup(self, source, destination, input)
			else
				search(self, source, destination,input)
			end
		end,
	},
}
