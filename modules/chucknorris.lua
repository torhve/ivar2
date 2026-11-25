-- Util lib contains lots of helpful stuff for modules, like HTTP, JSON,
-- IRC formatting, some utf8-helpers, etc.
local util = require'util'
local http = util.simplehttp
local json = util.json

-- Define function that will be ran when triggered by user input
local handler = function(self, source, destination, input)
	-- self is ivar2 object, with all its methods
	-- source is table, containing sender info, like source.nick
	-- destination is string with target of the message, i.e. the channel the message was sent to
	-- input is optional Lua pattern capture match

	-- Fetch HTTP content and JSON decode it. No error handling needed here
	-- unless you want to inform the user of errors with HTTP or JSON etc.
	-- All module functions are called with pcall (protected call) to prevent
	-- crashes. Errors will result in error lines in the log.
	-- you want to
	local result = json.decode((http'http://api.icndb.com/jokes/random'))

	-- Send the reply back to the destination where it came from using ivar2
	-- Privmsg function. You could also use say() or reply() available in this
	-- function environment as helpers
	self:Privmsg(destination, result.value.joke)
end

-- Modules returns a table with events, and Lua pattern with a corresponding
-- function that will be called when the event text matches the pattern.
return {
	-- PRIVMSG means incoming IRC message, from channel or query
	PRIVMSG = {
		['!chuck'] = handler,
	},
}
