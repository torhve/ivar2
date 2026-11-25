-- Fixed flag days (day/month)
local fixedFlagDays = {
	{ month = 1,  day = 1,  reason = "1. nyttårsdag" },
	{ month = 1,  day = 21, reason = "HKH Prinsesse Ingrid Alexandra (f. 2004)" },
	{ month = 2,  day = 6,  reason = "Samane sin nasjonaldag" },
	{ month = 2,  day = 21, reason = "HM Kong Harald V (f. 1937)" },
	{ month = 5,  day = 1,  reason = "Den internasjonale arbeidardagen" },
	{ month = 5,  day = 8,  reason = "Frigjeringsdagen 1945" },
	{ month = 5,  day = 17, reason = "Grunnlovsdagen" },
	{ month = 6,  day = 7,  reason = "Unionsoppløysinga 1905" },
	{ month = 7,  day = 4,  reason = "HM Dronning Sonja (f. 1937)" },
	{ month = 7,  day = 20, reason = "HKH Kronprins Haakon (f. 1973)" },
	{ month = 7,  day = 29, reason = "Olsokdagen" },
	{ month = 8,  day = 19, reason = "HKH Kronprinsesse Mette-Marit (f. 1973)" },
	{ month = 12, day = 25, reason = "1. juledag" },
}

-- Movable flag days (offset from Easter Sunday)
local movableFlagDays = {
	{ offset = 0,  reason = "1. påskedag" },
	{ offset = 49, reason = "1. pinsedag" },
}

local flagDays = {}

local _date = function(dateTable)
	return os.date('*t', os.time(dateTable))
end

local easterDay = function(year)
	local C = math.floor(year / 100)
	local N = year - 19 * math.floor(year / 19)
	local K = math.floor((C - 17) / 25)
	local I = C - math.floor(C / 4) - math.floor((C - K) / 3) + 19 * N + 15
	I = I - 30 * math.floor(I / 30)
	I = I - math.floor(I / 28) * (1 - math.floor(I / 28) * math.floor(29 / (I + 1)) * math.floor((21 - N) / 11))
	local J = year + math.floor(year / 4) + I + 2 - C + math.floor(C / 4)
	J = J - 7 * math.floor(J / 7)
	local L = I - J
	local month = 3 + math.floor((L + 40) / 44)
	local day = L + 28 - 31 * math.floor(month / 4)
	return _date({ year = year, month = month, day = day, hour = 0 })
end

local addDay = function(date, days)
	local newDate = {}
	for k, v in next, date do
		newDate[k] = v
	end
	newDate.day = date.day + days
	return _date(newDate)
end

local generateFlagDays = function(year)
	for _, fd in ipairs(fixedFlagDays) do
		local date = _date({ year = year, month = fd.month, day = fd.day, hour = 0 })
		table.insert(flagDays, {
			reason = fd.reason,
			date = date,
			timestamp = os.time(date),
		})
	end

	local easter = easterDay(year)
	for _, md in ipairs(movableFlagDays) do
		local date = addDay(easter, md.offset)
		table.insert(flagDays, {
			reason = md.reason,
			date = date,
			timestamp = os.time(date),
		})
	end

	table.sort(flagDays, function(a, b) return a.timestamp < b.timestamp end)
end

local isFlagDay = function(date)
	local timestamp = os.time({ year = date.year, month = date.month, day = date.day, hour = 0 })
	for i = 1, #flagDays do
		if timestamp == flagDays[i].timestamp then
			return flagDays[i]
		end
	end
	return false
end

-- Generate flag days for multiple years
do
	local year = os.date('*t').year
	for i = 0, 3 do
		generateFlagDays(year + i)
	end
end

local timeUntilNextCheck = function()
	local now = _date()
	local day = now.day
	if now.hour >= 8 then
		day = now.day + 1
	end
	return os.time({ year = now.year, month = now.month, day = day, hour = 8 }) - os.time(now)
end

local sendMessage = function(message)
	local channels = ivar2.config.flaggdagerChannels or {}
	for _, channel in ipairs(channels) do
		ivar2:Privmsg(channel, message)
	end
end

local function startTime()
	ivar2:Timer("flaggdager-" .. os.time(), timeUntilNextCheck(), function()
		startTime()

		local today = _date()
		local flagDay = isFlagDay(today)
		if not flagDay then return end

		sendMessage(string.format("I dag er det flaggdag. Hugs å flagga (%s) 🇳🇴", flagDay.reason))
	end)
end

if test_mode then -- luacheck: ignore
	return {
		isFlagDay = isFlagDay,
		timeUntilNextCheck = timeUntilNextCheck,
		addDay = addDay,
		_date = _date,
		easterDay = easterDay,
		flagDays = flagDays,
		fixedFlagDays = fixedFlagDays,
		movableFlagDays = movableFlagDays,
	}
end

startTime()
