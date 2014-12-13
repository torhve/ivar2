local ev = require'ev'
local util = require'util'
local simplehttp = util.simplehttp
local json = util.json

local apiurl = 'http://www.tollpost.no/XMLServer/rest/trackandtrace/%s'

local duration = 60

if(not ivar2.timers) then ivar2.timers = {} end
-- Abuse the ivar2 global to store out ephemeral event data until we can get some persistant storage
if(not ivar2.shipmentEvents) then ivar2.shipmentEvents = {} end

local split = function(str, pattern)
	local out = {}

	str:gsub(pattern, function(match)
		table.insert(out, match)
	end)

	return out
end

local function titlecase(str)
    local buf = {}
    for word in string.gfind(str, "%S+") do          
        local first, rest = string.sub(word, 1, 1), string.sub(word, 2)
        table.insert(buf, string.upper(first) .. string.lower(rest))
    end    
    return table.concat(buf, " ")
end


local eventHandler = function(event)
	if not event then return nil end
	local out = {}
	local date = event.eventTime:sub(1,10)
	local time = event.eventTime:sub(12)
	table.insert(out, date)
	table.insert(out, time)
	table.insert(out, event.eventDescription)
    local location = event.location
	if location then
		local city = location['displayName']
		if city and city ~= '' then city = '('..titlecase(city)..')' end
		table.insert(out, city)
	end
	return table.concat(out, ' ')
end

local shipmentTrack = function(self, source, destination, pid, alias)
	local nick = source.nick

	local id = pid .. nick
	local runningTimer = self.timers[id]
	if(runningTimer) then
		-- cancel existing timer
	    self:Notice(nick, "Canceling existing tracking for alias %s.", alias)
		self.shipmentEvents[id] = -1
		runningTimer:stop(ivar2.Loop)
	end

	-- Store the eventcount in the ivar2 global
	-- if the eventcount increases it means new events on the shipment happened.
	local eventCount = self.shipmentEvents[id] 
	if not eventCount then 
		self.shipmentEvents[id] = -1
	end

	local timer = ev.Timer.new(
		function(loop, timer, revents)
			simplehttp(string.format(apiurl, pid), function(data) 
				local info = json.decode(data)
				local root = info['TrackingInformationResponse']
				local cs = root['shipments']
				if not cs[1] then 
					if self.shipmentEvents[id] == -1 then 
						say('%s: Found nothing for shipment %s', nick, pid)
					end
					self.shipmentEvents[id] = 0
					return
				else 
					cs = cs[1] 
				end
				local out = {}
				local items = cs['items'][1]
				local status = string.format('\002%s\002', titlecase(items['status']))
				local events = items['events']
				local newEventCount = #events

				print('id:',id,'new:',newEventCount,'old:',self.shipmentEvents[id])
				if newEventCount < self.shipmentEvents[id] then 
					-- We can never go backwards
					return
				end
				if newEventCount > self.shipmentEvents[id] then
					table.insert(out, string.format('Status: %s', status))
				end
				for i=self.shipmentEvents[id]+1,newEventCount do
					print('loop:',i)
					local event = events[i]
					table.insert(out, eventHandler(event))
					-- Cancel event here somehow?
				end
				if #out > 0 then
					say('%s: \002%s\002 %s', nick, alias, table.concat(out, ', '))
				end
				self.shipmentEvents[id] = newEventCount
			end)
		end,
		1,
		duration
	)

	self.timers[id] = timer
	timer:start(ivar2.Loop)
end

local shipmentLocate = function(self, source, destination, pid)
	local nick = source.nick
	simplehttp(string.format(apiurl, pid), function(data) 
		local info = json.decode(data)
		local root = info['TrackingInformationResponse']
		local cs = root['shipments']
		if not cs[1] then 
			say('%s: Found nothing for shipment %s', nick, pid)
			return
		else 
			cs = cs[1] 
		end
		local out = {}
		local items = cs['items'][1]
		local status = string.format('\002%s\002', titlecase(items['status']))
		table.insert(out, string.format('Status: %s', status))
		for i, event in pairs(items['events']) do
			table.insert(out, eventHandler(event))
		end
		say('%s: %s', nick, table.concat(out, ', '))
	end)
end

local shipmentHelp = function(self, source, destination)
	return say('For lookup: !mypack pakkeid. For tracking: !mypack pakkeid alias')
end

return {
	PRIVMSG = {
		['^%pmypack (%d+) (.*)$'] = shipmentTrack,
		['^%pmypack (%d+)$'] = shipmentLocate,
		['^%pmypack$'] = shipmentHelp,
	},
}
