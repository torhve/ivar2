local x0 = require'x0'

local handler = function(self, source, destination, input)
	x0.lookup(input, function(url)
		self:Msg('privmsg', destination, source, '%s: %s', source.nick, url)
	end)
end

return {
	PRIVMSG = {
		['^%pshorten (.+)$'] = handler,
		['^%px0 (.+)$'] = handler,
	},
}
