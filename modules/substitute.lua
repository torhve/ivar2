local db = {}

local toLuaPattern = function(str)
	return str:gsub('%%', '%%%%'):gsub('\\([%l%u%d^$()%%.%[%]*+%-?])', '%%%1'):gsub('\\/', '/')
end

local handleMessage = function(nick, destination, msg, update)
	if(db[nick] and db[nick][destination]) then
		local matchPoint = msg:match('()[^\\]/')

		-- Someone failed and only wrote: s/match
		if(not matchPoint) then return end

		local match = msg:sub(1, matchPoint)

		local replacePoint = msg:match('()[^\\]/', matchPoint + 1)
		local replace = msg:sub(matchPoint + 2, replacePoint)

		local flags = 1
		if(replacePoint) then
			local flagPoint = msg:match('()[^\\]/', replacePoint + 1)
			local flag = msg:sub(replacePoint + 2, flagPoint)
			if(flag:lower() == 'g') then
				flags = #db[nick][destination]
			end
		end

		-- We have to use pcall to avoid errors about invalid capture pattern and
		-- invalid capture index.
		local success, out = pcall(
			string.gsub,
			db[nick][destination],
			toLuaPattern(match),
			toLuaPattern(replace),
			flags
		)

		if(success and out ~= db[nick][destination]) then
			if(update) then
				db[nick][destination] = out
			end

			return out
		end
	end
end

return {
	PRIVMSG = {
		['^s/(.+)$'] = function(self, source, destination, message)
			local out = handleMessage(source.nick, destination, message, true)
			if(out) then
				self:Msg('privmsg', destination, source, '%s meant: %s', source.nick, out)
			end
		end,

		['^<([^>]+)>s/(.+)$'] = function(self, source, destination, target, message)
			local out = handleMessage(target, destination, message)
			if(out) then
				self:Msg('privmsg', destination, source, '%s thought %s meant: %s', source.nick, target, out)
			end
		end,

		function(self, source, destination, argument)
			-- Don't validate input here, people fail to often and try again.
			if(argument:match('^<[^>]+>s/') or argument:sub(1, 2) == 's/') then return end

			if(argument:sub(1,1) == '\001' and argument:sub(-1) == '\001') then
				argument = argument:sub(9, -2)
			end

			local nick = source.nick
			if(not db[nick]) then db[nick] = {} end
			db[nick][destination] = argument
		end,
	}
}
