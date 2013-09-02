-- ndp - Natural Date Parser library for Lua
-- Copyright (C) 2009 Matthew Wild <mwild1@gmail.com>
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

module(..., package.seeall);

require "luarocks.require"
require "lpeg"

-- Add case-insensitive string matching to Lpeg
function lpeg.Pi(s)
	local patt = lpeg.P(true);
	for c in s:gmatch(".") do
		patt = patt * (lpeg.P(c:lower()) + lpeg.P(c:upper()));
	end
	return patt;
end

function lpeg.one_of(list)
	local patt = lpeg.P(false);
	for _, match in ipairs(list) do
		patt = patt + lpeg.Pi(match);
	end
	return patt;
end

local wordsep = lpeg.S" ";

local ordinal = lpeg.P{ lpeg.C(lpeg.R("09")^-2) * (lpeg.Pi("st") + lpeg.Pi("nd") + lpeg.Pi("rd") + lpeg.Pi("th")) + 1 * lpeg.V(1) };
local number = lpeg.R "09"^1

local day_name = lpeg.one_of {'monday',   'tuesday', 'wednesday',
                              'thursday', 'friday',  'saturday', 'sunday'}

local month_name = lpeg.one_of {'january', 'february', 'march', 'april', 'may', 'june', 
                                     'july', 'august', 'september', 'october', 'november', 'december' }

local year = lpeg.R("09") * lpeg.R("09") * lpeg.R("09") * lpeg.R("09");

local unit_of_time = lpeg.one_of { 'second', 'minute', 'hour', 'day', 'week', 'month', 'year' }

local time_of_day = lpeg.one_of { 'morning', 'noon', 'afternoon', 'evening', 'night', 'midnight' }
local time_of_days = { morning = 09, noon = 12, afternoon = 13, evening = 17, night = 21, midnight = 00 }

local quantity;
local quantities = { 
		["a"]        = 1;
		["an"]       = 1;
		
		["a couple of"] = 2;
		
		["a few"]    = 3;
		["several"]  = 3;
	};

-- Create 'quantity' to match any of the quantities we know
do
	local quantity_list = {};
	for k in pairs(quantities) do
		quantity_list[#quantity_list+1] = k;
	end
	table.sort(quantity_list, function (a,b) return #a>#b; end);
	quantity = number + lpeg.one_of(quantity_list);
end

seconds_in_a = { second = 1 }
seconds_in_a.minute  = seconds_in_a.second *  60;
seconds_in_a.hour    = seconds_in_a.minute *  60;
seconds_in_a.day     = seconds_in_a.hour   *  24;
seconds_in_a.week    = seconds_in_a.day    *   7;
seconds_in_a.month   = seconds_in_a.week   *   4;
seconds_in_a.year    = seconds_in_a.day    * 365;

local function get_time_part(time, part)
	return os.date("*t", time)[part];
end

local function adjust_time(time, part, value)
	local split_time = os.date("*t", time);
	
	split_time[part] = value;
	
	return os.time(split_time);
end

local function find_next_day_by_name(time, day_name)
	day_name = day_name:lower():gsub("^.", string.upper); -- Normalize
	
	for i=1,8 do
		time = time + seconds_in_a.day;
		if os.date("%A", time) == day_name then
			return time;
		end
	end
	return;
end

local function find_next_month_by_name(time, month_name)
	month_name = month_name:lower():gsub("^.", string.upper); -- Normalize
	
	local split_time = os.date("*t", time);
	for i=1,13 do
		split_time.month = split_time.month + 1;
		if split_time.month == 13 then split_time.month = 1; end
		
		time = os.time(split_time);
		if os.date("%B", time) == month_name then
			return time;
		end
	end
	
	return;
end

local function advance_months(time, n)
	local split_time = os.date("*t", time);
	split_time.month = ((split_time.month-1)+n)%12+1;
	split_time.year = split_time.year + math.floor(n/12);
	return os.time(split_time);
end

local function advance_years(time, n)
	local split_time = os.date("*t", time);
	split_time.year = split_time.year + n;
	return os.time(split_time);
end

function when(str, relative_to)
	local time = relative_to or os.time();
	local P, Pi = lpeg.P, lpeg.Pi;
	
	local patterns = 
	{ 
		{ Pi"today" };
		{ Pi"tomorrow" /
			function ()
				time = time + seconds_in_a.day;
			end };
		{ (lpeg.one_of{"a ", "the "}+true) * Pi"day after" /
			function ()
				time = time + seconds_in_a.day;
			end };
		{ Pi"next week" /
			function ()
				time = time + seconds_in_a.week;
			end };
		{ Pi"next month" /
			function ()
				time = advance_months(time, 1);
			end };
		{ Pi"next year" /
			function ()
				time = advance_years(time, 1);
			end };
		{ year /
			function (year)
				time = adjust_time(time, "year", tonumber(year));
			end };
		{ (Pi"in " + true) * month_name /
			function (month_name)
				time = find_next_month_by_name(time, month_name:match("%S+$"));
			end };
		{ (Pi"on " + true) * day_name /
			function (day_name)
				time = find_next_day_by_name(time, day_name:match("%S+$"));
			end };
		{ (Pi"in " + true) * ( quantity * P" " * unit_of_time ) * (P"s"^-1) /
			function (number_and_unit)
				local number, unit = number_and_unit:gsub("^in ", ""):match("^(.+)%s+(.-)s?$");
				
				number = quantities[number] or tonumber(number);
				
				if unit == "month" then
					time = advance_months(time, number);
				elseif unit == "year" then
					time = advance_years(time, number);
				else
					time = time + seconds_in_a[unit] * number;
				end
			end };
		{ (lpeg.one_of{"this ", "in the ", "at "} + true)* time_of_day /
			function (time_of_day)
					time_of_day = time_of_day:match("%S+$");

					if time_of_day == "morning" and get_time_part(time, "hour") > time_of_days.morning then
						time = time + seconds_in_a.day; -- Morning has passed, so next morning
					end

					time = adjust_time(time, "hour", time_of_days[time_of_day]);
					if time_of_day == "noon" or time_of_day == "midnight" then
						time = adjust_time(time, "min", 00);
					else
						time = adjust_time(time, "min", 30);
					end
			end };
	}
	
	local ret, min_pos, max_pos;
	local function check_min_pos(start) start = start - 1; if not min_pos or start < min_pos then min_pos = start; end end;
	for _, pattern in pairs(patterns) do
		ret = lpeg.match(lpeg.P{ lpeg.Cp()*pattern[1] + 1 * (1-wordsep)^0 * wordsep * lpeg.V(1) }/check_min_pos, str);
		if ret then
			if not max_pos or ret > max_pos then max_pos = ret; end
			--print("Matches ".._.." until "..ret);
		end
	end
	
	return time, min_pos, max_pos;
end

