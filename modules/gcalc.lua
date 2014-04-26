local simplehttp = require'simplehttp'
local html2unicode = require'html'

local urlEncode = function(str)
	return str:gsub(
		'([^%w ])',
		function (c)
			return string.format ("%%%02X", string.byte(c))
		end
	):gsub(' ', '+')
end

local parseData = function(source, destination, data)
	local ans = data:match('<h2 class="r".->(.-)</h2>')
	if(ans) then
		ans = ans:gsub('<sup>(.-)</sup>', '^%1'):gsub('<[^>]+> ?', ''):gsub('%s+', ' ')
		ivar2:Msg('privmsg', destination, source, '%s: %s', source.nick, html2unicode(ans))
	else
		ivar2:Msg('privmsg', destination, source, '%s: %s', source.nick, 'Do you want some air with that fail?')
	end
end

local handle = function(self, source, destination, input)
	local search = urlEncode(input)

	simplehttp(
		('http://www.google.com/search?q=%s'):format(search),
		function(data)
			parseData(source, destination, data)
		end
	)
end

return {
	PRIVMSG = {
		['^%pgcalc (.+)$'] = handle,
		['^%pcalc (.+)$'] = handle,
		['^%pgalc (.+)$'] = handle,
	},
}
