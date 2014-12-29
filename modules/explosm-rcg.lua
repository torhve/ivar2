local util = require'util'
local simplehttp = util.simplehttp

return {
	PRIVMSG = {
		['^%prcg%s*$'] = function(self, source, destination)
			simplehttp(
				"http://explosm.net/rcg",
				function(data)
					local comic = data:match('<meta property="og:url" content="([^"]+)">')
					reply(comic)
				end
			)
		end,
	},
}
