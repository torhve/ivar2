return {
	PRIVMSG = {
		['^%pmore$'] = function(self, source, destination, module)
			local more = self.more[destination]
			if more then
				self:Msg('privmsg', destination, source, more)
			end
		end,
		['^%pmore%?$'] = function(self, source, destination, module)
			local more = self.more[destination]
			if more then
				self:Msg('privmsg', destination, source, 'There are %s more bytes.', #more)
			else
				self:Msg('privmsg', destination, source, 'There is no more!')
			end
		end,
	},
}
