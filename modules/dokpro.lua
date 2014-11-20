local htmlparser = require'htmlparser'

local trim = function(s)
	if not s then return nil end
	return s:match('^()%s*$') and '' or s:match('^%s*(.*%S)')
end

local parseData = function(data)
	if(data:match('ordboksdatabasene')) then
		return nil, 'Service down. :('
	end

	-- This page is a typical example of someone using XHTML+CSS+JS, while still
	-- coding like they used to back in 1998.
	data = data:gsub('\r', ''):match('<div id="kolonne_enkel"[^>]+>(.-)<div id="slutt">'):gsub('&nbsp;', '')

	local words = {}
	local lookup = data:match('>([^<]+)</a>')
	data = data:match('(<span class="oppslagsord b".->.-)</td>')

	if(data) then
		local doc = htmlparser.parsestr(data)
		local word = doc[1][1]
		-- Workaround for mis matched word (partial match)
		if type(word) == type({}) then
			word = doc[1][1][1]
		end
		local entry = { 
			lookup = {},
			meaning = {},
			examples = {},
		}
		local text = {}
		-- Here be dragons. This is why we can't have nice things
		for _, w in pairs(doc) do
			if _ ~= '_tag' then 
				if type(w) == type("") then
					table.insert(text, w)
				elseif type(w) == type({}) then
					if w['_attr'] and w['_attr'].class == 'oppsgramordklasse' then
						table.insert(text, ivar2.util.italic(w[1]))
					-- Extract definitions
					elseif w['_attr'] ~= nil and w['_attr']['class'] == 'utvidet' then
						for _, t in pairs(w) do
							if type(t) == type("") and t ~= "span" then
								table.insert(text, t)
							elseif type(w) == type({}) then
								if t['_attr'] ~= nil and t['_attr']['class'] == 'tydingC kompakt' then
									for _, f in pairs(t) do
										if type(f) == type("") and f ~= 'span' then
											table.insert(text, f)
										elseif type(f[1]) == type("") and trim(f[1]) ~= "" then
											table.insert(text, string.format("[%s]", ivar2.util.bold(f[1])))
										end
									end
								end
							end
						end
					elseif type(w[1]) == type("") then
						if w[1] ~= word then
							table.insert(text, w[1])
						end
					end
				end
			end
		end
		entry.meaning = trim(table.concat(text))
		table.insert(entry.lookup, word)
		table.insert(words, entry)
	end

	return words
end

local handleInput = function(self, source, destination, word, ordbok)
	if not ordbok then ordbok = 'bokmaal' end
	local query = ivar2.util.urlEncode(word)
	ivar2.util.simplehttp(
		"http://www.nob-ordbok.uio.no/perl/ordbok.cgi?ordbok="..ordbok.."&"..ordbok.."=+&OPP=" .. query,

		function(data)
			local words, err = parseData(data)
			local out = {}
			if(words) then
				local n =  #word + 23
				for i=1, #words do
					local word = words[i]
					local lookup = table.concat(word.lookup, ', ')
					local definition = word.meaning
					if(word.examples[1]) then
						if(definition and #definition < 35) then
							definition = definition .. ' ' .. word.examples[1]
						else
							definition = word.examples[1]
						end
					end

					if(definition) then
						local message = string.format('\002[%s]\002: %s', lookup, definition)

						n = n + #message
						table.insert(out, message)
					end
				end
			end

			if(#out > 0) then
				self:Msg('privmsg', destination, source, '%s', table.concat(out, ', '))
			else
				self:Msg('privmsg', destination, source, '%s: %s', source.nick, err or 'Du suger, prøv igjen.')
			end
		end
	)
end

return {
	PRIVMSG = {
		['^%pdokpro (.+)$'] = handleInput,
		['^%pordbok (.+)$'] = handleInput,
		['^%pbokmål (.+)$'] = handleInput,
		['^%pnynorsk (.+)$'] = function(self, source, destination, word) 
			handleInput(self, source, destination, word, 'nynorsk')
		end
	},
}
