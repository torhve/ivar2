local util = require'util'
local simplehttp = util.simplehttp
local json = util.json

local apiurl = 'http://sporing.bring.no/sporing.json?q=%s&%s'

local duration = 60

-- Abuse the ivar2 global to store out ephemeral event data until we can get some persistant storage
if(not ivar2.shipmentEvents) then ivar2.shipmentEvents = {} end

local split = function(str, pattern)
	local out = {}

	str:gsub(pattern, function(match)
		table.insert(out, match)
	end)

	return out
end


local getCacheBust = function()
	return math.floor(os.time() / 60)
end

local eventHandler = function(event)
	if not event then return nil end
	local city = event.city
	if city ~= '' then city = ' ('..city..')' end
	return string.format('%s %s %s%s', event.displayDate, event.displayTime, event.description, city)
end

local shipmentTrack = function(self, source, destination, message)
	local nick = source.nick
	local comps = split(message, '%S+')
	-- Couldn't figure out what the user wanted.
	if #comps < 2 then
		return say('Usage: !sporing pakkeid alias')
	end

	local pid = comps[1]
	local alias = comps[2]

	local id = pid .. nick

	-- Store the eventcount in the ivar2 global
	-- if the eventcount increases it means new events on the shipment happened.
	local eventCount = self.shipmentEvents[id]
	if not eventCount then
		self.shipmentEvents[id] = -1
	end

	local shipmentPoller = function()
		simplehttp(string.format(apiurl, pid, getCacheBust()), function(data)
			local info = json.decode(data)
			local cs = info.consignmentSet
			if not cs[1] then return else cs = cs[1] end
			local err = cs['error']
			if err then
				print('err', err, err['message'])
				local errmsg = err['message']
				if self.shipmentEvents[id] == -1 then
					say('%s: \002%s\002 %s', nick, alias, errmsg)
				end
				return
				-- self.shipmentEvents[id] = 0
			end
			local ps = cs['packageSet'][1]
			local eventset = ps['eventSet']
			local newEventCount = #eventset
			local out = {}
			print('id:',id,'new:',newEventCount,'old:',self.shipmentEvents[id])
			if newEventCount < self.shipmentEvents[id]
				then newEventCount = self.shipmentEvents[id]
			end
			-- start at the oldest event and go forward in time to index reaches 0
			for i=#eventset-self.shipmentEvents[id]-1,0,-1 do
				print('loop:',i)
				local event = eventset[i]
				if event then
					table.insert(out, eventHandler(event))
					local status = event.status
					-- Cancel event if package is delivered
					if status == 'DELIVERED' then
						self.timers[id]:stop(ivar2.Loop)
						--self.timers[id] = nil
					end
				end
			end
			if #out > 0 then
				say('%s: \002%s\002 %s', nick, alias, table.concat(out, ', '))
			end
			self.shipmentEvents[id] = newEventCount
		end)
	end
	self:Timer(id, duration, duration, shipmentPoller)
	shipmentPoller()
end

local shipmentLocate = function(self, source, destination, pid)
	local nick = source.nick
	simplehttp(string.format(apiurl, pid, getCacheBust()), function(data)
		local info = json.decode(data)
		local cs = info.consignmentSet
		if not cs[1] then return else cs = cs[1] end
		local err = cs['error']
		if err then
			local errmsg = err['message']
			say('%s: %s', nick, errmsg)
			return
		end
		local out = {}
		local ps = cs['packageSet'][1]
		for i,event in pairs(ps['eventSet']) do
			table.insert(out, eventHandler(event))
		end
		say('%s: %s', nick, table.concat(out, ', '))
	end)
end

local shipmentHelp = function(self, source, destination)
	return say('For lookup: !pakke pakkeid. For tracking: !sporing pakkeid alias')
end

return {
	PRIVMSG = {
		['^%psporing (.*)$'] = shipmentTrack,
		['^%pspor (.*)$'] = shipmentTrack,
		['^%ppakke (.*)$'] = shipmentLocate,
		['^%psporing$'] = shipmentHelp,
		['^%ppakke$'] = shipmentHelp,
	},
}
