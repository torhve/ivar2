-- Google Search over the AJAX API.
--
-- Expects a valid google API key in the config table.
--
-- Example:
-- config = {
--     ...
--     googleAPIKey = 'valid key here',
--     ...
-- }

local util = require'util'
local x0 = require'x0'
local simplehttp = util.simplehttp
local json = util.json
local urlEncode = util.urlEncode
local html2unicode = require'html'

local outFormat = '\002%s\002 <%s>'
local parseData = function(say, source, destination, data)
	data = json.decode(data)

	if(data and data.responseStatus == 200) then
		local arr = {}
		local n = 0
		for i=1,3 do
			local match = data.responseData.results[i]
			if(not match) then break end

			local title = html2unicode(match.titleNoFormatting)
			local url = match.unescapedUrl
			if(#url >= 75) then
				n = n + 1
				x0.lookup(url, function(short)
					n = n - 1
					arr[i] = outFormat:format(title, short or url)

					if(n == 0) then
						say(table.concat(arr, ' || '))
					end
				end)
			else
				arr[i] = outFormat:format(title, url)
			end
		end

		if(n == 0) then
			if(#arr > 0) then
				say(table.concat(arr, ' || '))
			else
				say('jack shit found :-(.')
			end
		end
	end
end

local url = 'http://www.google.com/uds/GwebSearch?context=0&hl=en&key=%s&v=1.0&q=%s&rsz=small'
local handler = function(self, source, destination, input)
	local search = urlEncode(input)

	simplehttp(
		url:format(self.config.googleAPIKey, search),
		function(data)
			parseData(say, source, destination, data)
		end
	)
end

return {
	PRIVMSG = {
		['^%pg (.+)$'] = handler,
		['^%pgoogle (.+)$'] = handler,
	},
}
