local verifyOwner = function(src)
	for _, mask in next, ivar2.config.owners do
		if(src.mask:match(mask)) then
			return true
		end
	end
end

return {
	PRIVMSG = {
		['madd>%s*(%S+)$'] = function(self, source, destination, module)
			if(not verifyOwner(source)) then return end

			self:LoadModule(module)

			self:Msg('privmsg', destination, source, "Loaded module: %s", module)
		end,

		['mdel>%s*(%S+)$'] = function(self, source, destination, module)
			if(not verifyOwner(source)) then return end

			self:DisableModule(module)

			self:Msg('privmsg', destination, source, "Disable module: %s", module)
		end,

		['irc> (%S+) (.+)$'] = function(self, source, destination, command, argument)
			if(not verifyOwner(source)) then return end

			command = command:lower()
			if(command == "join") then
				local chan, pass = argument:match('^(%S+) ?(%S*)')
				if(pass == '') then pass = nil end
				self:Join(chan, pass)
			elseif(command == "part") then
				self:Part(argument)
			elseif(command == "nick") then
				self:Nick(argument)
			elseif(command == "mode") then
				local destination, mode = argument:match('^(%S+) (.+)$')
				self:Mode(destination, mode)
			elseif(command == "topic") then
				local chan, topic = argument:match('^(%S+) (.+)$')
				self:Topic(chan, topic)
			elseif(command == "kick") then
				local chan, user, comment = argument:match('^(%S+) (%S+) ?(.*)$')
				self:Kick(chan, user, comment)
			end
		end,

		['reload>'] = function(self, source, destination)
			if(not verifyOwner(source)) then return end

			self:Msg('privmsg', destination, source, "Triggered reload.")
			self:Reload()
		end,

		['timers> (%S+) ?(.*)$'] = function(self, source, destination, command, argument )
			if(not verifyOwner(source)) then return end

			command = command:lower()
			if(command == "list") then
				for id,_ in pairs(self.timers) do
					self:Msg('privmsg', destination, source, "Id: %s", id)
				end
			elseif command == "stop" then
				self.timers[argument]:stop(self.Loop)
				self.timers[argument] = nil
				self:Msg('privmsg', destination, source, 'OK')
			end
		end,
	},
}
