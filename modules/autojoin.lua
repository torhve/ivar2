local join = function(self, channel, data)
	if(type(data) == 'table' and data.password) then
		self:Join(channel, data.password)
	else
		self:Join(channel)
	end
end

return {
	['376'] = {
		function(self)
			if(self.config.channels) then
				for channel, data in next, self.config.channels do
					self:Log('info', string.format('Automatically joining %s.', channel))
					join(self, channel, data)
				end


				local timerName = 'autojoin'
				if(not self.timers) then self.timers = {} end

				if(not self.timers[timerName]) then
					local timer = self.timer.every(60*1000, function()
							for channel, data in next, self.config.channels do
								if(not self.channels[channel]) then
									self:Log('info', string.format('Automatically rejoining %s.', channel))
									join(self, channel, data)
								end
							end
						end
					)

					self.timers[timerName] = timer
				end
			end
		end,
	}
}
