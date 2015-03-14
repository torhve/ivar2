local date = require'date'
local os = require'os'
local ndp = require'ndp' -- http://code.matthewwild.co.uk/ndp/

local handleWhen = function(self, source, destination, when)
	local time = ndp.when(when)
	local now = os.time()
	local pretty = os.date('%c', time)
	local duration = date.relativeTimeShort(now, time)
	if time and duration then
		return '\002%s\002 -- %s', duration, pretty
	end
end

return {
	PRIVMSG = {
		['^%pwhen (.*)$'] = function(self, source, destination, when)
			say(handleWhen(self, source, destination, when))
		end,
	},
}
