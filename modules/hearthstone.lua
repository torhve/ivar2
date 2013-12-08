local simplehttp = require'simplehttp'

local cache = {}
local trim = function(s)
	return s:match('^%s*(.-)%s*$')
end

local pattern = ('<td[^>]*>([^\n]+)\n[^<]+'):rep(10)
local parseData = function(data)
	local tmp = {}
	local tbody = data:match('<tbody>(.*)</tbody>')
	for row in tbody:gmatch('<tr[^>]+>.-</tr>') do
		for _, name, class, rarity, kind, race, mana, attack, life, desc in row:gmatch(pattern) do
			-- Strip HTML:
			name = name:gsub('<%/?[%w:]+.-%/?>', '')
			class = class:match('alt="([^"]+)"') or class

			tmp[name:lower()] = {
				name = name,
				class = class,
				rarity = rarity:sub(1, -6),
				type = kind:sub(1, -6),
				race = race ~= "" and race:sub(1, -6) or nil,
				mana = mana ~= "" and mana:sub(1, -6) or nil,
				attack = attack ~= "" and attack:sub(1, -6) or nil,
				life = life ~= "" and attack:sub(1, -6) or nil,
				desc = desc ~= "" and desc:sub(1, -6) or nil,
			}
		end
	end

	if(next(tmp)) then
		cache = tmp
	end
end

local formatOutput = function(card)
	local out = {}

	card = cache[card]
	table.insert(out, card.name)
	table.insert(out, card.class)
	table.insert(out, card.rarity)
	table.insert(out, card.type)

	if(card.mana) then
		table.insert(out, string.format('Cost: %s', card.mana))
	end

	if(card.attack) then
		table.insert(out, string.format('Attack: %s', card.mana))
	end

	if(card.life) then
		table.insert(out, string.format('HP: %s', card.mana))
	end

	if(card.desc) then
		table.insert(out, card.desc)
	end

	return table.concat(out, ' / ')
end

local checkCache = function(card)
	local out
	if(cache[card]) then
		out = formatOutput(card)
	end

	if(not out) then
		local matches = {}
		for name, data in next, cache do
			if(name:find(card, 1, true)) then
				table.insert(matches, data.name)
			end
		end

		if(#matches == 1) then
			out = formatOutput(matches[1]:lower())
		elseif(#matches > 1) then
			local n = 13 + 7
			out = {}
			local msgLimit = (512 - 16 - 65 - 10) - #ivar2.config.nick - 30
			for i=1, #matches do
				local name = matches[i]
				n = n + #name + 2
				if(n < msgLimit) then
					table.insert(out, string.format('%s', name))
				end
			end

			out = 'Found: ' .. table.concat(out, ', ')
		end
	end

	return out
end

return {
	PRIVMSG = {
		['^!hs (.+)$'] = function(self, source, destination, card)
			card = trim(card:lower())

			local out = checkCache(card)
			if(out) then
				self:Msg('privmsg', destination, source, 'Hearthstone: %s', out)
				return
			end

			simplehttp('http://hearthstonecardlist.com/', function(data)
				-- Update cache.
				parseData(data)

				local out = checkCache(card)
				if(out) then
					self:Msg('privmsg', destination, source, 'Hearthstone: %s', out)
				else
					self:Msg('privmsg', destination, source, 'Hearthstone: No matching card found.')
				end
			end)
		end,
	},
}
