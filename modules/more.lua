return {
	PRIVMSG = {
		['^%pmore$'] = function(self, source, destination, module)
			local more = self.more[destination]
			if more then
				say(more)
			end
		end,
		['^%pmore%?$'] = function(self, source, destination, module)
			local more = self.more[destination]
			if more then
				say('There are %s more bytes.', #more)
			else
				say('There is no more!')
			end
		end,
	},
}
