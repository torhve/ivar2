local response = {
	-- Positive
	"It is certain",
	"It is decidedly so",
	"Without a doubt",
	"Yes definitely",
	"You may rely on it",
	"As I see it, yes",
	"Most likely",
	"Outlook good",
	"Yes",
	"Signs point to yes",

	-- Neutral
	"Reply hazy try again",
	"Ask again later",
	"Better not tell you now",
	"Cannot predict now",
	"Concentrate and ask again",

	-- Negative
	"Don't count on it",
	"My reply is no",
	"My sources say no",
	"Outlook not so good",
	"Very doubtful",
}
return {
	PRIVMSG = {
		['^%p8ball$'] = function(self, source, destination)
			local seed = math.random(1, #response)
			self:Msg('privmsg', destination, source, "%s: %s", source.nick, response[seed])
		end,
	},
}
