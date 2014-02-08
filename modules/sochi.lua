local simplehttp = require'simplehttp'

local handler = function(self, source, destination, input)
	simplehttp("http://www.sochi2014.com/en/medal-standings", function(data)
		local standings = data:match('<div class="standings">(.-)</table>'):match("<tbody>(.*)</tbody>")
		local entries = {}
		for entry in standings:gmatch("<tr>(.-)</tr>") do
			entry = entry:gsub("[\r\n]+", "")
			for rank, country, gold, silver, bronze, total in entry:gmatch(("<td[^>]*>(.-)</td>"):rep(6)) do
				if(total ~= "0") then
					country = country:gsub('<%/?[%w:]+.-%/?>', '')
					table.insert(entries, string.format("\002%s. %s:\002 %sg %ss %sb (%s)", rank, country, gold, silver, bronze, total))
				end
			end
		end

		self:Msg(
			'privmsg', destination, source,
			table.concat(self:LimitOutput(destination, entries, 1), ' ')
		)
	end)
end

return {
	PRIVMSG = {
		['^%pol%s*$'] = handler,
		['^%powg%s*$'] = handler,
		['^%psochi%s*$'] = handler,
	},
}
