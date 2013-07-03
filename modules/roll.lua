local ltrim = function(r, s)
	if(not s) then
		s, r = r, "%s+"
	end
	return (string.gsub(s, "^" .. r, ""))
end

return {
	PRIVMSG = {
		['^%proll (.+)$'] = function(self, source, destination, input)
			local a,b = input:match('([-%d]+)%s*([-%d]*)')
			a, b = tonumber(a), tonumber(b)

			local seed
			if(a and b and a < b) then
				seed = math.random(a, b)
			elseif(a and a > 1) then
				seed = math.random(1, a)
			else
				seed = 'I will suffocate you with a pillow in your sleep!'
			end

			self:Msg('privmsg', destination, source, '%s: %s', source.nick, seed)
		end,
	},
}
