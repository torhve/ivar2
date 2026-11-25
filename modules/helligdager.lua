--[[ Reference:
  Dato              | Navn                  | Bemerkninger                                                               | 2017
  ------------------+-----------------------+----------------------------------------------------------------------------+------------
  1. januar         | første nyttårsdag     |                                                                            | søndag
  1. mai            | første mai            |                                                                            | mandag
  17. mai           | syttende mai          |                                                                            | onsdag
  bevegelig torsdag | skjærtorsdag          | torsdag før første påskedag                                                | 13. april
  bevegelig fredag  | langfredag            | fredag før første påskedag                                                 | 14. april
  bevegelig søndag  | første påskedag       | første søndag etter første fullmåne som inntreffer på eller etter 21. mars | 16. april
  bevegelig mandag  | andre påskedag        | dagen etter første påskedag                                                | 17. april
  bevegelig torsdag | Kristi himmelfartsdag | 39 dager (40. dag) etter påske                                             | 25. mai
  bevegelig søndag  | første pinsedag       | 49 dager (50. dag) etter påske                                             | 4. juni
  bevegelig mandag  | andre pinsedag        | 50 dager (51. dag) etter påske                                             | 5. juni
  25. desember      | første juledag        |                                                                            | mandag
  26. desember      | andre juledag         |                                                                            | tirsdag
]]

local wdayMap = {
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday"
}

local holidays = {}

local createHoliday = function(name, date)
  return {
    name = name,
    date = date,
    timestamp = os.time(date),
  }
end

-- Normalize the date
local _date = function(dateTable)
  return os.date('*t', os.time(dateTable))
end

local addDay = function(date, days)
  local newDate = {}
  for k, v in next, date do
    newDate[k] = v
  end

  newDate.day = date.day + days
  return _date(newDate)
end

local easterDay = function(year)
  local C = math.floor(year / 100);
  local N = year - 19 * math.floor(year / 19);
  local K = math.floor((C - 17) / 25);
  local I = C - math.floor(C / 4) - math.floor((C - K) / 3) + 19 * N + 15;
  I = I - 30 * math.floor((I / 30));
  I = I - math.floor(I / 28) * (1 - math.floor(I / 28) * math.floor(29 / (I + 1)) * math.floor((21 - N) / 11));
  local J = year + math.floor(year / 4) + I + 2 - C + math.floor(C / 4);
  J = J - 7 * math.floor(J / 7);
  local L = I - J;
  local month = 3 + math.floor((L + 40) / 44);
  local day = L + 28 - 31 * math.floor(month / 4);

  return _date({year = year, month = month, day = day, hour = 0})
end

local generateHolidays = function(year)
  local _insert = function(name, date)
    local holiday = createHoliday(name, date)
    table.insert(holidays, holiday)
  end

  year = year or os.date('*t').year

  -- Static
  -- New Year's
  _insert("første nyttårsdag", _date({year = year, month = 1, day = 1, hour = 0}))
  -- Labour Day
  _insert("første mai", _date({year = year, month = 5, day = 1, hour = 0}))
  -- Constitution Day
  _insert("syttende mai", _date({year = year, month = 5, day = 17, hour = 0}))
  -- Christmas Day
  _insert("første juledag", _date({year = year, month = 12, day = 25, hour = 0}))
  -- St Stephen's Day
  _insert("andre juledag", _date({year = year, month = 12, day = 26, hour = 0}))

  -- Movable
  local easter = easterDay(year)
  -- Maundy Thursday
  _insert("skjærtorsdag", addDay(easter, -3))
  -- Good Friday
  _insert("langfredag", addDay(easter, -2))
  -- Easter Sunday
  _insert("første påskedag", easter)
  -- Easter Monday
  _insert("andre påskedag", addDay(easter, 1))
  -- Ascension Day
  _insert("Kristi himmelfartsdag", addDay(easter, 39))
  -- Pentecost
  _insert("første pinsedag", addDay(easter, 49))
  -- Whit Monday
  _insert("andre pinsedag", addDay(easter, 50))

  table.sort(holidays, function(a, b) return a.timestamp < b.timestamp end)
end

local isHoliday = function(date)
  local timestamp = os.time({year = date.year, month = date.month, day = date.day, hour = 0})
  for i=1, #holidays do
    local holiday = holidays[i]
    if timestamp == holiday.timestamp then
      return holiday
    end
  end

  return false
end

local isWeekend = function(date)
  return date.wday == 1 or date.wday == 7
end

local getNextHoliday = function(date)
  local timestamp = os.time(date)
  for i=1, #holidays do
    local holiday = holidays[i]
    if timestamp < holiday.timestamp then
      return holiday
    end
  end
end

local getConsecutiveHolidays = function(date)
  date = date or os.date('*t')

  local consecutiveHolidays = {}
  local nextHoliday = getNextHoliday(date)
  if not nextHoliday then return {} end

  -- Blargh. Inject the weekend if we have to.
  if (nextHoliday.date.wday == 2) then
    local saturday = addDay(nextHoliday.date, -2)
    table.insert(consecutiveHolidays, createHoliday("helg", saturday))
    local sunday = addDay(nextHoliday.date, -1)
    table.insert(consecutiveHolidays, createHoliday("helg", sunday))
  elseif (nextHoliday.date.wday == 1) then
    local saturday = addDay(nextHoliday.date, -1)
    table.insert(consecutiveHolidays, createHoliday("helg", saturday))
  end

  table.insert(consecutiveHolidays, nextHoliday)

  local nextDate = nextHoliday.date
  repeat
    nextDate = addDay(nextDate, 1)

    local holiday = isHoliday(nextDate)
    local weekend = isWeekend(nextDate)
    if (holiday) then
      table.insert(consecutiveHolidays, holiday)
    elseif(weekend) then
      table.insert(consecutiveHolidays, createHoliday("helg", nextDate))
    end
  until not (holiday or weekend)

  return consecutiveHolidays
end

-- Generate holidays for a couple of years
do
  local year = os.date("*t").year
  for i=0, 3 do
    generateHolidays(year+i)
  end
end

local shouldAnnounce = function()
  local date = _date()

  if (isHoliday(date) or isWeekend(date)) then
    return false
  end

  local consecutiveHolidays = getConsecutiveHolidays(date)
  local tomorrow = addDay(date, 1)
  local tomorrowTs = os.time({year = tomorrow.year, month = tomorrow.month, day = tomorrow.day, hour = 0})
  if (consecutiveHolidays[1].timestamp == tomorrowTs) then
    return true
  end

  return false
end

-- Calculate seconds until the next 08:00 daily check.
-- If it's already past 08:00, target tomorrow at 08:00.
local timeUntilNextCheck = function()
  local now = _date()

  local day = now.day
  if (now.hour >= 8) then
    day = now.day + 1
  end

  return os.time({year = now.year, month = now.month, day = day, hour = 8}) - os.time(now)
end

local formatHolidays = function(holidays)
  local out = {}
  for i=1, #holidays do
    local holiday = holidays[i]
    table.insert(out, string.format("%s is %s", wdayMap[holiday.date.wday], ivar2.util.bold(holiday.name)))
  end

  return table.concat(out, ", ")
end

local sendMessage = function(message)
  local channels = ivar2.config.helligdagerChannels or {}
  for _, channel in next, channels do
    ivar2:Privmsg(channel, message)
  end
end

-- Set up a recurring daily timer that fires at 08:00.
-- Each time it fires, it reschedules itself for the next day,
-- then calls shouldAnnounce() to decide whether to send a holiday
-- announcement. Announcements are only sent on the day before a
-- holiday, and only on weekdays (not weekends).
local function startTime()
  ivar2:Timer("helligdager-" .. os.time(), timeUntilNextCheck(), function()
    startTime()

    if (not shouldAnnounce()) then return end

    local consecutiveHolidays = getConsecutiveHolidays(_date())
    local holidays = {}
    local holidayNames = {}
    local weekends = 0
    for i=1, #consecutiveHolidays do
      local holiday = consecutiveHolidays[i]
      if (isWeekend(holiday.date)) then
        weekends = weekends + 1
      end

      if (holiday.name ~= "helg") then
        table.insert(holidays, holiday)
        table.insert(holidayNames, holiday.name)
      end
    end

    local allInWeekend = weekends == #consecutiveHolidays
    if (allInWeekend) then return end

    if(#consecutiveHolidays == 1) then
      sendMessage(string.format("%s! Enjoy your day off", formatHolidays(holidays)))
    else
      sendMessage(string.format("%s! Enjoy your extra long weekend", formatHolidays(holidays)))
    end
  end)
end

if test_mode then -- luacheck: ignore
  return {
    shouldAnnounce = shouldAnnounce,
    timeUntilNextCheck = timeUntilNextCheck,
    getConsecutiveHolidays = getConsecutiveHolidays,
    getNextHoliday = getNextHoliday,
    isHoliday = isHoliday,
    isWeekend = isWeekend,
    addDay = addDay,
    _date = _date,
    holidays = holidays,
  }
end

startTime()
