local trim = function(s)
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local meh = ivar2.config.spam.meh
local caseinsensitive = ivar2.config.spam.caseInsensitive
local wordlist = ivar2.config.spam.wordlist

local caseTable
local case = function(str)
	local out
	local i = 0
	local n = #caseTable + 1
	for char in str:gmatch"([%z\1-\127\194-\244][\128-\191]*)" do
		out = (out or '') .. caseTable[i % n](char)

		i = i + 1
	end
	return out
end

local buildCaseTable = function(msg)
	caseTable = {}
	local i = 0
	for char in msg:gmatch"([%z\1-\127\194-\244][\128-\191]*)" do
		if(string.byte(char) >= 97 or string.byte(char) == 32) then
			caseTable[i] = string.lower
		else
			caseTable[i] = string.upper
		end

		i = i + 1
	end
end

local send = function(destination, source, reply, fuck)
	if(type(reply) == 'table') then
		math.randomseed(os.time())
		math.random(); math.random(); math.random()

		if(fuck) then
			say(case(reply[math.random(1, #reply)]))
		else
			say(reply[math.random(1, #reply)])
		end

	else
		if(fuck) then
			say(case(reply))
		else
			say(reply)
		end
	end
end

return {
	PRIVMSG = {
		function(self, source, destination, message)
			message = trim(message)
			message = message:gsub('<.->%s+', '')
			if(wordlist) then
				for pattern, reply in pairs(wordlist) do
					if(message:match(pattern)) then
						buildCaseTable(message)
						-- found a match, let's tail call our way out!
						return send(destination, source, reply)
					end
				end
			end

			local tmp = message:lower()
			if(caseinsensitive) then
				for pattern, reply in next, caseinsensitive do
					if(tmp:match(pattern)) then
						-- found a match, let's tail call our way out!
						return send(destination, source, reply)
					end
				end
			end

			if(meh) then
				for pattern, reply in next, meh do
					if(tmp:match(pattern)) then
						buildCaseTable(message)
						-- found a match, let's tail call our way out!
						return send(destination, source, reply, true)
					end
				end
			end
		end,
	}
}
