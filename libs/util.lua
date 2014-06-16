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

return {
	bold=bold,
	underline=underline,
	italic=italic,
	reverse=reverse,
	color=color,
	reset=reset,
	urlEncode=urlEncode,
	trim=trim,
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
}
