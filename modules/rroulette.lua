local ev = require'ev'

local rr = ivar2.persist

if(not ivar2.timers) then ivar2.timers = {} end

local getBullet = function(n)
	return n % 10
end

local getChamber = function(n)
	return (n - getBullet(n)) / 10 % 10
end

return {
	PRIVMSG = {
		['^%prr$'] = function(self, source, destination)
			local nick = source.nick

			if(not rr['rr:'..destination]) then
				rr['rr:'..destination] = 60 + math.random(1,6)
			end

			local bullet = getBullet(rr['rr:'..destination])
			local chamber = getChamber(rr['rr:'..destination])

			local deathKey = destination .. ':' .. nick .. ':deaths'
			local attemptKey = destination .. ':' .. nick .. ':attempts'

			local deaths = rr['rr:'..deathKey] or 0
			local attempts = (rr['rr:'..attemptKey] or 0) + 1
			local seed = math.random(1, chamber)

			if(seed == bullet) then
				bullet = math.random(1, 6)
				chamber = 6
				deaths = deaths + 1
				self:Kick(destination, nick, 'BANG!')
				say('BANG! %s died a gruesome death.', source.nick)
			else
				chamber = chamber - 1
				if(bullet > chamber) then
					bullet = chamber
				end

				local src = 'Russian Roulette:' .. destination
				if(self.timers[src]) then
					self.timers[src]:again(self.Loop, 15 * 60)
				else
					local timer = ev.Timer.new(
						function(loop, timer, revents)
							local n = rr['rr:'..destination]
							rr['rr:'..destination] = 60 + math.random(1,6)
						end,
						15 * 60
					)
					self.timers[src] = timer
					timer:start(self.Loop)
				end

				say('Click. %d/6', chamber)
			end

			rr['rr:'..destination] = (chamber * 10) + bullet
			rr['rr:'..deathKey] = deaths
			rr['rr:'..attemptKey] = attempts
		end,

		['^%prrstat$'] = function(self, source, destination)
			local nicks = {}
			for n,t in pairs(self.channels[destination].nicks) do
				nicks[n] = destination..':'..n
			end

			local tmp = {}
			for nick, key in next, nicks do
				if(not tmp[nick]) then tmp[nick] = {} end
				type = 'attempts'
				res = tonumber(rr['rr:'..key..':'..type])
				if not res then res = 0 end
				tmp[nick][type] = res
				type = 'deaths'
				res = tonumber(rr['rr:'..key..':'..type])
				if not res then res = 0 end
				tmp[nick][type] = res
			end

			local stats = {}
			for nick, data in next, tmp do
				if data.deaths > 0 or data.attempts > 0 then
					local deathRatio = data.deaths / data.attempts
					table.insert(stats, {nick = nick, deaths = data.deaths, attempts = data.attempts, ratio = deathRatio})
				end
			end
			table.sort(stats, function(a,b) return a.ratio < b.ratio end)

			local out = {}
			for i=1, #stats do
				table.insert(out, string.format('%s (%.1f%%)', stats[i].nick, (1 - stats[i].ratio) * 100))
			end

			say('Survival rate: %s', ivar2.util.nonickalert(self.channels[destination].nicks, table.concat(out, ', ')))
		end,
	}
}
