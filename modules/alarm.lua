-- vim: set noexpandtab:
local dateFormat = '%Y-%m-%d %X %Z'

local timeMatches = {
	{
		'(%d+)[:.](%d%d)[:.]?(%d?%d?)', function(h, m, s)
			-- Seconds will always return a match.
			if(s == '') then s = 0 end

			local now = os.time()
			local date = os.date'*t'

			local ntime = date.hour * 60 * 60 + date.min * 60 + date.sec
			local atime = h * 60 * 60 + m * 60 + s

			-- Set the correct time of day.
			date.hour = h
			date.min = m
			date.sec = s

			-- If the alarm is right now or in the past, bump it to the next day.
			if(ntime >= atime) then
				date.day = date.day + 1
			end

			return os.time(date) - now
		end
	},
	{'^(%d+)w$', function(w) return w * 60 * 60 * 24 * 7 end},
	{'^(%d+)d$', function(d) return d * 60 * 60 * 24 end},
	{'^(%d+)[ht]$', function(h) return h * 60 * 60 end},
	{'^(%d+)m$', function(m) return m * 60 end},
	{'^(%d+)[^%p%w]*$', function(m) return m * 60 end, true},
	{'^(%d+)s$', function(s) return s end},
}

local parseTime = function(input)
	local duration = 0

	local offset
	for i=1, #input do
		local found
		local str = input[i]
		for j=1, #timeMatches do
			local pattern, func, skipIfFound = unpack(timeMatches[j])
			local a1, a2, a3 = str:match(pattern)
			if(a1 and not (skipIfFound and duration > 0)) then
				found = true
				duration = duration + func(a1, a2, a3)
			end
		end

		if(not found) then break end
		offset = i + 1
	end

	if(duration ~= 0) then
		return duration, table.concat(input, ' ', offset)
	end
end

local alarm = function(self, source, destination, message)
	local duration
	duration, message = parseTime(ivar2.util.split(message, ' '))
	-- Couldn't figure out what the user wanted.
	if(not duration) then
		reply('Example: !alarm 5m drink a glass of water')
		return
	end

	-- 60 days or more?
	local nick = source.nick
	if(duration >= (60 * 60 * 24 * 60) or duration == 0) then
		return say("%s: :'(", nick)
	end

	local id = 'Alarm: ' .. nick .. ':' .. message:gsub('%W', '')
	local runningTimer = self.timers[id]
	if(runningTimer) then
		-- Send a notification if we are overriding an old timer.
		if(runningTimer.utimestamp > os.time()) then
			if(runningTimer.message) then
				self:Msg(
					'privmsg',
					destination,
					source,
					'%s: Previously active timer set to trigger at %s with message "%s" has been removed.',
					nick,
					os.date(dateFormat, runningTimer.utimestamp),
					runningTimer.message
				)
			else
				self:Msg(
					'privmsg',
					destination,
					source,
					'%s: Previously active timer set to trigger at %s has been removed.',
					nick,
					os.date(dateFormat, runningTimer.utimestamp)
				)
			end
		end
	end

	local timer = self:Timer(id, duration, function(loop, timer, revents)
		if(#message == 0) then message = 'Timer finished.' end
		self:Msg('privmsg', destination, source, nick .. ': %s', message or 'Timer finished.')
	end)

	if(#message > 0) then timer.message = message end
	timer.utimestamp = os.time() + duration

	reply("I'll poke you at %s.", os.date(dateFormat, timer.utimestamp))

end

return {
	PRIVMSG = {
		['^%palarm (.*)$'] = alarm,
		['^%ptimer (.*)$'] = alarm,
	},
}
