local util = require'util'
local simplehttp = util.simplehttp
local urlEncode = util.urlEncode
local html2unicode = require'html'

local decode = function(str)
	-- Output tends to have double spaces.
	str = str:gsub('%s+', ' ')
	-- Convert the WA unicode escaping into HTML.
	str = str:gsub('\\:([0-9a-z][0-9a-z][0-9a-z][0-9a-z])', '&#x%1;')
	return (html2unicode(str))
end

-- Soon, expat.
local parseXML = function(xml)
	local results = {}
	for args, pod in xml:gmatch('<pod([^>]+)>(.-)</pod>') do
		local title = args:match("title='([^']+)'")
		local id = args:match("id='Input'")
		if(not id) then
			local sub = {}
			for args, subpod in pod:gmatch('<subpod([^>]+)>(.-)</subpod>') do
				local plain = subpod:match('<plaintext>(.-)</plaintext>')
				if(plain and #plain > 0) then
					table.insert(sub, decode(plain))
				end
			end

			if(#sub > 0) then
				table.insert(results, string.format('\002%s\002: %s', decode(title), table.concat(sub, '; ')))
			end
		end
	end

	return results
end

local APIBase = 'http://api.wolframalpha.com/v2/query?input=%s&format=plaintext&appid=' .. ivar2.config.wolframalphaAPIKey
return {
	PRIVMSG = {
		['^%pwa (.+)$'] = function(self, source, destination, input)
			simplehttp(
				APIBase:format(urlEncode(input)),

				function(data)
					local results = parseXML(data)
					local out = self:LimitOutput(destination, results, 2)

					if(#out > 0) then
						say(table.concat(out, ' '))
					else
						say('%s: That made no sense at all.', source.nick)
					end
				end
			)
		end,
	},
}
