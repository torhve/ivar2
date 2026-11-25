package.path = table.concat({
	'libs/?.lua',
	'libs/?/init.lua',
	'spec/?.lua',
	'',
}, ';') .. package.path

package.cpath = table.concat({
	'libs/?.so',
	'',
}, ';') .. package.cpath

local busted = require 'busted'
local describe = busted.describe
local it = busted.it
local before_each = busted.before_each

local function loadModule(controlledDate)
	controlledDate = controlledDate or os.date('*t')
	local controlledTs = os.time(controlledDate)
	local loader = loadfile('modules/flaggdager.lua')
	local env = { ivar2 = {}, test_mode = true }
	setmetatable(env, { __index = _G })
	env.os = {}
	setmetatable(env.os, { __index = os })
	env.os.time = function(dt)
		if dt == nil then return controlledTs end
		return os.time(dt)
	end
	env.os.date = function(format, date)
		if format == '*t' and date == nil then return controlledDate end
		return os.date(format, date)
	end
	setfenv(loader, env)
	return loader()
end

local function makeDate(y, m, d, hour, wday)
	local ts = os.time{ year = y, month = m, day = d, hour = hour or 8 }
	local real = os.date('*t', ts)
	return {
		year = y, month = m, day = d,
		hour = hour or 8, min = 0, sec = 0,
		wday = wday or real.wday,
		yday = real.yday, isdst = false,
	}
end

describe("flaggdager module", function()
	local mod

	before_each(function()
		mod = loadModule()
	end)

	describe("isFlagDay", function()
		it("should identify 1. nyttårsdag (1. jan)", function()
			local result = mod.isFlagDay({ year = 2026, month = 1, day = 1, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('1. nyttårsdag', result.reason)
		end)

		it("should identify HKH Prinsesse Ingrid Alexandra (21. jan)", function()
			local result = mod.isFlagDay({ year = 2026, month = 1, day = 21, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('HKH Prinsesse Ingrid Alexandra (f. 2004)', result.reason)
		end)

		it("should identify Samane sin nasjonaldag (6. feb)", function()
			local result = mod.isFlagDay({ year = 2026, month = 2, day = 6, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('Samane sin nasjonaldag', result.reason)
		end)

		it("should identify HM Kong Harald V (21. feb)", function()
			local result = mod.isFlagDay({ year = 2026, month = 2, day = 21, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('HM Kong Harald V (f. 1937)', result.reason)
		end)

		it("should identify 1. påskedag (5. apr 2026, movable)", function()
			local result = mod.isFlagDay({ year = 2026, month = 4, day = 5, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('1. påskedag', result.reason)
		end)

		it("should identify Den internasjonale arbeidardagen (1. mai)", function()
			local result = mod.isFlagDay({ year = 2026, month = 5, day = 1, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('Den internasjonale arbeidardagen', result.reason)
		end)

		it("should identify Frigjeringsdagen 1945 (8. mai)", function()
			local result = mod.isFlagDay({ year = 2026, month = 5, day = 8, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('Frigjeringsdagen 1945', result.reason)
		end)

		it("should identify Grunnlovsdagen (17. mai)", function()
			local result = mod.isFlagDay({ year = 2026, month = 5, day = 17, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('Grunnlovsdagen', result.reason)
		end)

		it("should identify 1. pinsedag (24. mai 2026, movable)", function()
			local result = mod.isFlagDay({ year = 2026, month = 5, day = 24, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('1. pinsedag', result.reason)
		end)

		it("should identify Unionsoppløysinga 1905 (7. jun)", function()
			local result = mod.isFlagDay({ year = 2026, month = 6, day = 7, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('Unionsoppløysinga 1905', result.reason)
		end)

		it("should identify HM Dronning Sonja (4. jul)", function()
			local result = mod.isFlagDay({ year = 2026, month = 7, day = 4, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('HM Dronning Sonja (f. 1937)', result.reason)
		end)

		it("should identify HKH Kronprins Haakon (20. jul)", function()
			local result = mod.isFlagDay({ year = 2026, month = 7, day = 20, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('HKH Kronprins Haakon (f. 1973)', result.reason)
		end)

		it("should identify Olsokdagen (29. jul)", function()
			local result = mod.isFlagDay({ year = 2026, month = 7, day = 29, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('Olsokdagen', result.reason)
		end)

		it("should identify HKH Kronprinsesse Mette-Marit (19. aug)", function()
			local result = mod.isFlagDay({ year = 2026, month = 8, day = 19, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('HKH Kronprinsesse Mette-Marit (f. 1973)', result.reason)
		end)

		it("should identify 1. juledag (25. des)", function()
			local result = mod.isFlagDay({ year = 2026, month = 12, day = 25, hour = 0 })
			assert.is_true(type(result) == 'table')
			assert.are_equal('1. juledag', result.reason)
		end)

		it("should return false for a non-flag day (15. mars)", function()
			local result = mod.isFlagDay({ year = 2026, month = 3, day = 15, hour = 0 })
			assert.is_false(result)
		end)
	end)

	describe("easterDay", function()
		it("should return 5 Apr 2026 for Easter 2026", function()
			local easter = mod.easterDay(2026)
			assert.are_equal(2026, easter.year)
			assert.are_equal(4, easter.month)
			assert.are_equal(5, easter.day)
		end)

		it("should return 20 Apr 2025 for Easter 2025", function()
			local easter = mod.easterDay(2025)
			assert.are_equal(2025, easter.year)
			assert.are_equal(4, easter.month)
			assert.are_equal(20, easter.day)
		end)
	end)

	describe("addDay", function()
		it("should handle month boundary crossing", function()
			local jan31 = { year = 2026, month = 1, day = 31, hour = 0 }
			local result = mod.addDay(jan31, 1)
			assert.are_equal(2, result.month)
			assert.are_equal(1, result.day)
		end)
	end)

	describe("timeUntilNextCheck", function()
		it("should return a positive number", function()
			local seconds = mod.timeUntilNextCheck()
			assert.is_true(seconds > 0)
		end)

		it("should return less than 25 hours", function()
			local seconds = mod.timeUntilNextCheck()
			assert.is_true(seconds < 25 * 3600)
		end)
	end)

	describe("flagDays table", function()
		it("should have entries for multiple years", function()
			assert.is_true(#mod.flagDays > 0)
			assert.is_true(#mod.flagDays >= 60)
		end)

		it("should be sorted by timestamp", function()
			for i = 2, #mod.flagDays do
				assert.is_true(mod.flagDays[i].timestamp >= mod.flagDays[i - 1].timestamp)
			end
		end)
	end)

	describe("shouldAnnounce (integration)", function()
		it("should return false for a non-flag day", function()
			local mod2 = loadModule(makeDate(2026, 3, 15, 8, 1))
			assert.is_false(mod2.isFlagDay({ year = 2026, month = 3, day = 15, hour = 0 }))
		end)
	end)
end)
