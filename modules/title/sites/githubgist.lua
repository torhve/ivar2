local simplehttp = require'simplehttp'
local json = require'json'

customHosts['gist%.github%.com'] = function(queue, info)
	local query = info.query
	local path = info.path
	local fragment = info.fragment
	local gid

	local pattern = '/%a+/(%w+)'
	if(path and path:match(pattern)) then
		gid = path:match(pattern)
	end

	if(gid) then
		simplehttp(
			('https://api.github.com/gists/%s'):format(gid),

			function(data)
				local info = json.decode(data)
				local name = info.user
				if name == json.util.null then
					name = 'Anonymous'
				else
					name = info.user.login
				end
				local files = ''
				for file,_ in pairs(info.files) do
					files = files..file..' '
				end

				local time = info.updated_at

				queue:done(table.concat(string.format('\002@%s\002 %s %s', name, time, files))
			end
		)

		return true
	end
end
