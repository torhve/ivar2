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
    local loader = loadfile('modules/helligdager.lua')
    local env = { ivar2 = {}, test_mode = true }
    setmetatable(env, { __index = _G })
    env.os = {}
    setmetatable(env.os, { __index = os })
    env.os.time = function(dt)
        if dt == nil then
            return controlledTs
        end
        return os.time(dt)
    end
    env.os.date = function(format, date)
        if format == '*t' and date == nil then
            return controlledDate
        end
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

describe("helligdager module", function()
    local mod

    before_each(function()
        mod = loadModule()
    end)

    describe("isHoliday", function()
        it("should identify Christmas as a holiday", function()
            local christmas = { year = 2026, month = 12, day = 25, hour = 0 }
            local result = mod.isHoliday(christmas)
            assert.is_true(type(result) == 'table')
            assert.are_equal('første juledag', result.name)
        end)

        it("should return false for a non-holiday date", function()
            local random = { year = 2026, month = 6, day = 10, hour = 0 }
            local result = mod.isHoliday(random)
            assert.is_false(result)
        end)
    end)

    describe("isWeekend", function()
        it("should identify Saturday as weekend", function()
            local saturday = { wday = 7 }
            assert.is_true(mod.isWeekend(saturday))
        end)

        it("should identify Sunday as weekend", function()
            local sunday = { wday = 1 }
            assert.is_true(mod.isWeekend(sunday))
        end)

        it("should identify weekday as not weekend", function()
            local weekday = { wday = 3 }
            assert.is_false(mod.isWeekend(weekday))
        end)
    end)

    describe("getNextHoliday", function()
        it("should return a future holiday", function()
            local now = os.date('*t')
            local result = mod.getNextHoliday(now)
            assert.is_true(type(result) == 'table')
            assert.is_true(result.timestamp > os.time(now))
        end)
    end)

    describe("getConsecutiveHolidays", function()
        it("should return consecutive holidays for Christmas period", function()
            local dec24 = { year = 2026, month = 12, day = 24, hour = 0 }
            local consecutive = mod.getConsecutiveHolidays(dec24)
            assert.is_true(#consecutive >= 2)
        end)

        it("should return empty table when no future holidays exist", function()
            local farFuture = { year = 2030, month = 12, day = 31, hour = 0 }
            local consecutive = mod.getConsecutiveHolidays(farFuture)
            assert.are_equal(0, #consecutive)
        end)
    end)

    describe("timeUntilNextCheck", function()
        it("should return a positive number (regression test)", function()
            local seconds = mod.timeUntilNextCheck()
            assert.is_true(seconds > 0, string.format(
                "Expected positive interval, got %d. This indicates the _date() bug.", seconds))
        end)

        it("should return reasonable interval (less than 25 hours)", function()
            local seconds = mod.timeUntilNextCheck()
            assert.is_true(seconds < 25 * 3600, string.format(
                "Expected interval < 25 hours, got %d seconds", seconds))
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

    describe("holidays table", function()
        it("should have entries for multiple years", function()
            assert.is_true(#mod.holidays > 0, "holidays table should not be empty")
            assert.is_true(#mod.holidays >= 44, string.format(
                "Expected at least 44 holidays (11 per year x 4 years), got %d", #mod.holidays))
        end)
    end)
end)

describe("shouldAnnounce", function()
    local function setup(date)
        return loadModule(date)
    end

    it("should return false on New Year's Day (today is holiday)", function()
        assert.is_false(setup(makeDate(2026, 1, 1, 8, 5)).shouldAnnounce())
    end)

    it("should return true on Apr 1 (day before skjærtorsdag)", function()
        assert.is_true(setup(makeDate(2026, 4, 1, 8, 3)).shouldAnnounce())
    end)

    it("should return false on Apr 2 (today is skjærtorsdag)", function()
        assert.is_false(setup(makeDate(2026, 4, 2, 8, 5)).shouldAnnounce())
    end)

    it("should return false on Apr 3 (today is langfredag)", function()
        assert.is_false(setup(makeDate(2026, 4, 3, 8, 6)).shouldAnnounce())
    end)

    it("should return false on Apr 4 (Saturday, weekend)", function()
        assert.is_false(setup(makeDate(2026, 4, 4, 8, 7)).shouldAnnounce())
    end)

    it("should return false on Apr 6 (today is andre påskedag)", function()
        assert.is_false(setup(makeDate(2026, 4, 6, 8, 2)).shouldAnnounce())
    end)

    it("should return true on Apr 30 (day before 1. mai)", function()
        assert.is_true(setup(makeDate(2026, 4, 30, 8, 5)).shouldAnnounce())
    end)

    it("should return true on May 13 (day before himmelfart)", function()
        assert.is_true(setup(makeDate(2026, 5, 13, 8, 4)).shouldAnnounce())
    end)

    it("should return true on May 15 (day before 17.mai weekend period)", function()
        assert.is_true(setup(makeDate(2026, 5, 15, 8, 6)).shouldAnnounce())
    end)

    it("should return false on May 16 (Saturday, weekend)", function()
        assert.is_false(setup(makeDate(2026, 5, 16, 8, 7)).shouldAnnounce())
    end)

    it("should return true on Dec 24 (day before Christmas)", function()
        assert.is_true(setup(makeDate(2026, 12, 24, 8, 5)).shouldAnnounce())
    end)

    it("should return false on Dec 25 (today is Christmas)", function()
        assert.is_false(setup(makeDate(2026, 12, 25, 8, 6)).shouldAnnounce())
    end)

    it("should return false on Dec 26 (today is St Stephen's Day)", function()
        assert.is_false(setup(makeDate(2026, 12, 26, 8, 7)).shouldAnnounce())
    end)

    it("should return false on random weekday with no upcoming holiday", function()
        assert.is_false(setup(makeDate(2026, 6, 10, 8, 3)).shouldAnnounce())
    end)
end)