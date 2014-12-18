-- ivar2 IRC utilities and more
-- vim: set noexpandtab:

local reset = function(s)
	return '\015'
end
local bold = function(s)
	return string.format("\002%s\002", s)
end
local underline = function(s)
	return string.format("\031%s\031", s)
end
local italic = function(s)
	return string.format("\029%s\029", s)
end
local reverse = function(s)
	return string.format("\018%s\018", s)
end

local rot13 = function(s)
	local byte_a, byte_A = string.byte('a'), string.byte('A')
	return (string.gsub((s or ''), "[%a]",
	function (char)
		local offset = (char < 'a') and byte_A or byte_a
		local b = string.byte(char) - offset -- 0 to 25
		b = ((b + 13) % 26) + offset -- Rotate
		return string.char(b)
	end
	))
end

local color = function(s, color)
	return string.format("\03%02d%s%s", color, s, reset())
end

local urlEncode = function(str)
	return str:gsub(
		'([^%w ])',
		function (c)
			return string.format ("%%%02X", string.byte(c))
		end
	):gsub(' ', '+')
end

local trim = function(s)
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local split = function(str, delim)
  if str == "" or str == nil then
    return { }
  end
  str = str .. delim
  local _accum_0 = { }
  local _len_0 = 1
  for m in str:gmatch("(.-)" .. delim) do
    _accum_0[_len_0] = m
    _len_0 = _len_0 + 1
  end
  return _accum_0
end

local translateWords = function(str, callback, fixCase, nickpat)
	-- Usage: etc.translateWords(s ,callback) the callback can return new word, false to skip, or nil to keep the same word.
	local str = assert(str)
	local callback = assert(callback, "Callback expected")
	local fixCase = fixCase == nil or fixCase == true
	local nickpat = nickpat

	local prev = 1
	local result = ""
	local pat = "()([%w'%-]+)()"
	if nickpat then
	  pat = "()([%w_'%-%{%}%[%]`%^]+)()"
	end
	for wpos, w, wposEnd in str:gmatch(pat) do
	  local wnew = callback(w)
	  if wnew ~= false then
		result = result .. str:sub(prev, wpos - 1)
		if wnew then
		  if fixCase then
			if w == w:lower() then
			elseif w == w:upper() then
			  wnew = wnew:upper()
			elseif w:sub(1, 1) == w:sub(1, 1):upper() then
			  wnew = wnew:sub(1, 1):upper() .. wnew:sub(2)
			end
		  end
		  result = result .. wnew
		else
		  result = result .. w
		end
		if not wnew then
		  wnew = w
		end
	  end
	  prev = wposEnd
	end
	result = result .. str:sub(prev)
	return result
end

local nonickalert = function(nicklist, str)
	-- U+200B, ZERO WIDTH SPACE: "\226\128\139"
	local s = str or ''
	local nl = nicklist -- nicklist
	local zwsp = "\226\128\142" -- LTR

	nl = nl or {}

	local nlkeys = {}
	for nick, t in pairs(nicklist) do
	  nlkeys[nick:lower()] = true
	end

	return translateWords(s, function(x)
		if nlkeys[x:lower()] then
			return x:sub(1, 1) .. zwsp .. x:sub(2)
		end
	end, nil, true)

end

return {
	bold=bold,
	underline=underline,
	italic=italic,
	reverse=reverse,
	color=color,
	reset=reset,
	urlEncode=urlEncode,
	trim=trim,
	split=split,
	rot13=rot13,
	json = require'cjson',
	simplehttp = require'simplehttp',
	white=function(s)
		return color(s, 0)
	end,
	black=function(s)
		return color(s, 1)
	end,
	blue=function(s)
		return color(s, 2)
	end,
	green=function(s)
		return color(s, 3)
	end,
	red=function(s)
		return color(s, 4)
	end,
	maroon=function(s)
		return color(s, 5)
	end,
	purple=function(s)
		return color(s, 6)
	end,
	orange=function(s)
		return color(s, 7)
	end,
	yellow=function(s)
		return color(s, 8)
	end,
	lightgreen=function(s)
		return color(s, 9)
	end,
	teal=function(s)
		return color(s, 10)
	end,
	cyan=function(s)
		return color(s, 11)
	end,
	lightblue=function(s)
		return color(s, 12)
	end,
	fuchsia=function(s)
		return color(s, 13)
	end,
	gray=function(s)
		return color(s, 14)
	end,
	lightgray=function(s)
		return color(s, 15)
	end,
	nonickalert=nonickalert,
	translateWords=translateWords,
}
