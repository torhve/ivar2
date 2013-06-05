local simplehttp = require'simplehttp'
local json = require'json'

customHosts['github%.com'] = function(queue, info)
	local query = info.query
	local path = info.path
	local fragment = info.fragment
    local repo

	local pattern = '/(%w+/[%w-.]+)'
	if(path and path:match(pattern)) then
	    repo = path:match(pattern)
	end

	if repo then
		simplehttp(
			('https://api.github.com/repos/%s'):format(repo),

			function(data)
				local info = json.decode(data)
				local name = info.name
                local owner = info.owner.login
                local description = info.description

                local watchers = info.watchers_count
                local forks = info.forks_count
                local lang = info.language
                if watchers == json.util.null then watchers = 0 end
                if forks == json.util.null then forks = 0 end
                if lang == json.util.null then lang = 'Unknown' end

				local out = {}
                table.insert(out, string.format('\002@%s/%s\002 %s Lang: %s %s watchers %s followers', owner, name, description, lang, watchers, forks))

				queue:done(table.concat(out, ' '))
			end
		)

		return true
	end
end
