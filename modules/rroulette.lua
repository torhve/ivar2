local ev = require'ev'
require'tokyocabinet'
local rr = tokyocabinet.hdbnew()

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
			rr:open('cache/rr', rr.OWRITER + rr.OCREAT)
			local nick = source.nick

			if(not rr[destination]) then
				rr[destination] = 60 + math.random(1,6)
			end

			local bullet = getBullet(rr[destination])
			local chamber = getChamber(rr[destination])

			local deathKey = destination .. ':' .. nick .. ':deaths'
			local attemptKey = destination .. ':' .. nick .. ':attempts'

			local deaths = rr[deathKey] or 0
			local attempts = (rr[attemptKey] or 0) + 1
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
					self.timers[src]:again(ivar2.Loop, 15 * 60)
				else
					local timer = ev.Timer.new(
						function(loop, timer, revents)
							rr:open('cache/rr', rr.OWRITER + rr.OCREAT)

							local n = rr[destination]
							rr[destination] = 60 + math.random(1,6)
							rr:close()
						end,
						15 * 60
					)
					self.timers[src] = timer
					timer:start(ivar2.Loop)
				end

				say('Click. %d/6', chamber)
			end

			rr[destination] = (chamber * 10) + bullet
			rr[deathKey] = deaths
			rr[attemptKey] = attempts

			rr:close()
		end,

		['^!rrstat'] = function(self, source, destination)
			rr:open('cache/rr')
			local nicks = rr:fwmkeys(destination .. ':')

			local tmp = {}
			for _, key in next, nicks do
				local nick, type = key:match(':([^:]+):(%w+)')
				if(not tmp[nick]) then tmp[nick] = {} end
				tmp[nick][type] = tonumber(rr[key])
			end
			rr:close()

			local stats = {}
			for nick, data in next, tmp do
				local deathRatio = data.deaths / data.attempts
				table.insert(stats, {nick = nick, deaths = data.deaths, attempts = data.attempts, ratio = deathRatio})
			end
			table.sort(stats, function(a,b) return a.ratio < b.ratio end)

			local out = {}
			for i=1, math.min(#stats, 5) do
				table.insert(out, string.format('%s (%.1f%%)', stats[i].nick, (1 - stats[i].ratio) * 100))
			end

			say('Survival rate: %s', table.concat(out, ', '))
		end,
	}
}
