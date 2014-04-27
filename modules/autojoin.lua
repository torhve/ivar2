require'logging.console'
local log = logging.console()

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
					log:info(string.format('Automatically joining %s.', channel))
					join(self, channel, data)
				end


				local timerName = 'autojoin'
				if(not self.timers) then self.timers = {} end

				if(not self.timers[timerName]) then
					local timer = ev.Timer.new(
						function(loop, timer, revents)
							for channel, data in next, self.config.channels do
								if(not self.channels[channel]) then
									log:info(string.format('Automatically rejoining %s.', channel))
									join(self, channel, data)
								end
							end
						end,
						60,
						60
					)

					self.timers[timerName] = timer
					timer:start(self.Loop)
				end
			end
		end,
	}
}
