local util = require'util'
local simplehttp = util.simplehttp
local json = util.json

customHosts['^github%.com'] = function(queue, info)
    local query = info.query
    local path = info.path
    local fragment = info.fragment
    local repo

    local pattern = '^/([%w-.]+/[%w-.]+)/?$'
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
                local issues = info.open_issues_count
                if watchers == json.null then watchers = 0 end
                if forks == json.null then forks = 0 end
                if lang == json.null then lang = 'Unknown' end
                if issues == json.null then issues = 0 end

                queue:done(string.format('\002@%s/%s\002 %s, Lang: \002%s\002, \002%s\002 watchers, \002%s\002 forks, \002%s\002 open issues', owner, name, description, lang, watchers, forks, issues))
            end
        )

        return true
    end
end
