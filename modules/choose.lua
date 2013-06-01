local simplehttp = require'simplehttp'

local patterns = {
	-- X://Y url
	"^(https?://%S+)",
	"%f[%S](https?://%S+)",
	-- 			-- www.X.Y url
	"^(www%.[%w_-%%]+%.%S+)",
	"%f[%S](www%.[%w_-%%]+%.%S+)",
}

local split = function(str, pattern)
	local out = {}
	str:gsub(pattern, function(match)
		table.insert(out, match)
	end)

	return out
end

local reply = {
	'┗(＾0＾)┓))(( ┏(＾0＾)┛',
	'（　´_ゝ`）ﾌｰﾝ',
	'（　°‿‿°）',
	'（　°∀°）',
	' (　´〰`)',
	'○|￣|＿',
	'ಠ_ಠ',
	'（╯°□°）╯︵ ┻━┻',
	'┐(￣ー￣)┌',
	[[/'''\ʕ•ᴥ•ʔ/'''\]],
}

local handleOutput = function(source, destination, choices)
	local hax = {}
	for k, v in pairs(choices) do
		hax[v] = true
	end

	local i = 0
	for k, v in pairs(hax) do
		i = i + 1
	end

	if(#choices <= 1 or i == 1) then
		ivar2:Msg('privmsg', destination, source, reply[math.random(1, #reply)])
	else
		local seed = math.random(1, #choices)
		ivar2:Msg('privmsg', destination, source, '%s: %s', source.nick, choices[seed])
	end
end

return {
	PRIVMSG = {
		['^\.choose (.+)$'] = function(self, source, destination, choices)
			if(choices:match('https?://%S+')) then
				simplehttp(
					choices:match('(https?://%S+)'),

					function(data)
						-- Strip out any HTML.
						data = data:gsub('<%/?[%w:]+.-%/?>', '')
						-- K-Line prevention!
						for _, pattern in ipairs(patterns) do
							data = data:gsub(pattern, '<snip /.')
						end

						local choices = split(data, '[^\n\r]+')
						for i=1, #choices do
							choices[i] = choices[i]:gsub('%s%s+', ' '):sub(1, 300)
							if(#choices[i] == 0) then
								table.remove(choices, i)
							end
						end

						handleOutput(source, destination, choices)
					end,
					true,
					2^16
				)
			else
				handleOutput(source, destination, split(choices, '%s*([^,]+)%s*'))
			end
		end
	}
}
