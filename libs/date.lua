local _M = {
	durations = {},
	strings = {},
}

do
	function _M.relativeSeconds(diff, T, L)
		local out

		for i=1, #T do
			local div = T[i]
			local n = math.modf(diff / div)
			if(n > 0) then
				out = string.format(
				'%s%d%s ',
				out or '', n, L[(n ~= 1 and i * 2) or (i * 2) - 1])
				diff = diff % div
			end
		end

		if(out) then
			return out:sub(1, -2)
		end
	end
end

do
	_M.durations.long = {
		12 * 30 * 24 * 60 * 60, -- year
		30 * 24 * 60 * 60, --month
		7 * 24 * 60 * 60, --week
		24 * 60 * 60, -- day
		60 * 60, -- hour
		60, -- minute
		1, -- second
	}

	_M.strings.long = {
		'years', 'year',
		'months', 'month',
		'weeks', 'week',
		'days', 'day',
		'hours', 'hour',
		'minutes', 'minute',
		'seconds', 'second',
	}

	function _M.relativeTime(t1,t2, T, L)
		t1, t2 = tonumber(t1), tonumber(t2)
		if(not t1) then return end
		if(not t2) then t2 = os.time() end
		if(t2 > t1) then t2, t1 = t1, t2 end

		-- Fallbacks
		T = T or _M.time.long
		L = L or _M.strings.long

		local diff = t1 - t2
		return _M.relativeSeconds(diff, T, L)
	end
end

do
	_M.durations.short = {
		7 * 24 * 60 * 60, --week
		24 * 60 * 60, -- day
		60 * 60, -- hour
		60, -- minute
		1, -- second
	}

	_M.strings.short = {
		'w', 'w', -- weeks, week
		'd', 'd', -- days, day
		'h', 'h', -- hours, hour
		'm', 'm', -- minutes, minute
		's', 's', -- seconds, second
	}

	function _M.relativeTimeShort(t1, t2)
		return _M.relativeTime(t1, t2, _M.durations.short, _M.strings.short)
	end
end

do
	local durations = {
		12 * 30 * 24 * 60 * 60, -- year
		30 * 24 * 60 * 60, --month
		7 * 24 * 60 * 60, --week
		24 * 60 * 60, -- day
	}

	local strings = {
		'y', 'm', 'w', 'd'
	}

	function _M.relativeDuration(diff, T, T)
		local out = ''
		T = T or durations
		L = L or strings

		for i=1, #T do
			local div = T[i]
			local n = math.modf(diff / div)
			if(n > 0) then
				out = string.format(
					'%s%d%s ',
					out,
					n,
					L[i]
				)
				diff = diff % div
			end
		end

		if(diff >= 3600) then
			out = string.format(
				'%s%d:%02d:%02d',
				out,
				math.floor(diff / 3600),
				math.floor((diff % 3600) / 60),
				diff % 60
			)
		else
			out = string.format(
				'%s%d:%02d',
				out,
				math.floor(diff / 60),
				math.floor(diff % 60)
			)
		end

		return out
	end
end

return _M
