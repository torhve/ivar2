-- Port of: http://ermahgerd.jmillerdesign.com/#!/translate
local split = function(str, pattern)
	local out = {}
	str:gsub(pattern, function(match)
		table.insert(out, match)
	end)

	return out
end

local specificWords = {
	["AWESOME"] = "ERSUM",
	["BANANA"] = "BERNERNER",
	["BAYOU"] = "BERU",
	["FAVORITE"] = "FRAVRIT",
	["FAVOURITE"] = "FRAVRIT",
	["GOOSEBUMPS"] = "GERSBERMS",
	["LONG"] = "LERNG",
	["MY"] = "MAH",
	["THE"] = "DA",
	["THEY"] = "DEY",
	["WE'RE"] = "WER",
	["YOU"] = "U",
	["YOU'RE"] = "YER",
}

local replaces = {
	-- Reduce duplicate letters
	"(.)(%1)", "%1",
	-- Reduce adjacent vowels to one
	"[AEIOUY]+[AEIOUY]+", "E",
	-- DOWN -> DERN
	"OW", "ER",
	-- PANCAKES -> PERNERKS
	"AKES", "ERKS",
	-- The mean and potatoes: replace vowels with ER
	"[AEIOUY]+", "ER",
	-- OH -> ER
	"ERH", "ER",
	-- MY -> MAH
	"MER", "MAH",
	-- FALLING -> FERLIN
	"ERNG", "IN",
	-- POOPED -> PERPERD -> PERPED
	"ERPERD", "ERPED",
	-- MEME -> MAHM -> MERM
	"MAHM", "MERM",
	-- Reduce duplicate letters
	"(.)(%1)", "%1",
}

local translate = function(word)
	if #word == 1 then
		return word
	end

	if specificWords[word] then
		return specificWords[word]
	end

	local orgWord = word
	if #orgWord > 2 then
		word = word:gsub("[AEIOU]+$", '')
	end

	for i=1, #replaces, 2 do
		local find, replace = replaces[i], replaces[i+1]
		word = word:gsub(find, replace)
	end

	-- Keep Y as first character
	-- YES -> ERS -> YERS
	if orgWord:sub(1,1) == "Y" then
		word = "Y" .. word
	end

	-- YELLOW -> YERLER -> YERLO
	if orgWord:sub(-3) == "LOW" and word:sub(-3) == "LER" then
		word = word:sub(1, word:len() - 3) .. "LO"
	end

	return word
end

local handle = function(self, source, destination, text)
	text = text:upper()
	local words = split(text, "[^%s]+")
	local translated = {}

	for i=1, #words do
		local prefix = words[i]:match("^%W+") or ""
		local suffix = words[i]:match("%W+$") or ""
		local word = words[i]:sub(#prefix + 1, #words[i]-#suffix)

		if(word ~= "") then
			table.insert(translated, prefix .. translate(word) .. suffix)
		else
			table.insert(translated, words[i])
		end
	end

	self:Msg("privmsg", destination, source, table.concat(translated, " "))
end

return {
	PRIVMSG = {
		['^%perm (.+)$'] = handle,
		['^%permahgerd (.+)$'] = handle,
	}
}
