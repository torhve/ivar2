return {
	PRIVMSG = {
		['^%psc2m (%d+%.?%d*) (%d+%.?%d*)$'] = function(self, source, destination, a, b)
			self:Msg('privmsg', destination, source, '%s: %s', source.nick, ((a + 1)*10)^(1 + math.log10(b + 1)))
		end
	}
}
