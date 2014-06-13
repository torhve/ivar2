return {
	PRIVMSG = {
		['^!sc2m (%d+%.?%d*) (%d+%.?%d*)$'] = function(self, source, destination, a, b)
			say('%s: %s', source.nick, ((a + 1)*10)^(1 + math.log10(b + 1)))
		end
	}
}
