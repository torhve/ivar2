local handler = function(self, source, destination, input)
	local shorten = self.shorten or self.x0
	shorten(input, function(url)
		self:Msg('privmsg', destination, source, '%s: %s', source.nick, url)
	end)
end

return {
	PRIVMSG = {
		['^%pshorten (.+)$'] = handler,
		['^%px0 (.+)$'] = handler,
	},
}
