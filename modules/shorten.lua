local handler = function(self, source, destination, input)
	self.x0(input, function(url)
		self:Msg('privmsg', destination, source, '%s: %s', source.nick, url)
	end)
end

return {
	PRIVMSG = {
		['^%pshorten (.+)$'] = handler,
		['^%px0 (.+)$'] = handler,
	},
}
