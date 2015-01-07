local date = require'date'
local ev = require'ev'
local notes = ivar2.persist

local handleOutput = function(self, source, destination)
	-- Only accept notes on channels.
	if(destination:sub(1,1) ~= '#') then return end

	local nick = source.nick
	local key = 'notes:' .. destination .. ':' .. nick:lower()
	local nick_notes = notes[key]
	if(not nick_notes) then return end
	local numNotes = tonumber(#nick_notes)
	if(not numNotes or numNotes == 0) then return end

	for i = 1, numNotes do
		local note = nick_notes[i]
		local time = tonumber(note.time)
		local from = note.from

		say("%s: %s left a note %s ago: %s", nick, from, date.relativeTimeShort(time), note.message)
	end

	notes[key] = {}

	local globalNumNotes = tonumber(notes['global:' .. nick:lower()])
	if(globalNumNotes) then
		notes['global:' .. nick:lower()] = globalNumNotes - numNotes
	end
end

return {
	NICK = {
		function(self, source, nick)
			if(not notes['global:' .. nick:lower()]) then return end
			-- source still contains the old nick.
			source.nick = nick
			handleOutput(self, source, channel)
		end,
	},

	JOIN = {
		-- Check if we have notes for the person who joined the channel.
		function(self, source, destination)
			return handleOutput(self, source, destination)
		end,
	},

	PRIVMSG = {
		-- Check if we have notes for the person who sent the message.
		handleOutput,

		['^%pnote (%S+)%s+(.+)$'] = function(self, source, destination, recipient, message)
			-- Only accept notes on channels.
			if(destination:sub(1,1) ~= '#') then return end

			local globalNumNotes = tonumber(notes['global:' .. recipient:lower()]) or 0
			if(globalNumNotes >= 5) then
				say("I'm sorry, Dave. I'm afraid I can't do that. Too many notes.")
			else
				self:Notice(source.nick, "%s will be notified!", recipient)
			end

			local key = 'notes:' .. destination .. ':' .. recipient:lower()
			local nick_notes = notes[key] or {}

			local note = {
				message = message,
				time = os.time(),
				from = source.nick,
			}
			table.insert(nick_notes, note)
			notes[key] = nick_notes

			notes['global:' .. recipient:lower()] = globalNumNotes + 1
		end
	}
}
