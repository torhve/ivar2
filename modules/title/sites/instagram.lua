local function handleOutput(queue, hash, data, withURL, try)
	data = ivar2.util.json.decode(data)
	local p = data.data
    -- Access denied or other error
    if(not p) then return end
    local o = {}

    if(p.caption and p.caption.from and p.caption.from.username) then
        table.insert(o, ivar2.util.bold(p.caption.from.username))
    end

    if(p.caption and p.caption.text) then
        table.insert(o, p.caption.text)
    end

    if(p.likes and p.likes.count) then
        table.insert(o, string.format('[%s ♥]', p.likes.count))
    end

    local title = table.concat(o, ' ')
	queue:done(title)
end

customHosts['^instagram%.com'] = function(queue, info)
    if(not ivar2.config.instagramClientID) then return end
	if(not info.path) then return end

	local section, hash = info.path:match('^/(p)/([a-zA-Z0-9%-_]+)')
	if(not hash) then return end

	if(section == 'p') then
        local url = ('https://api.instagram.com/v1/media/shortcode/%s?client_id=%s'):format(hash, ivar2.config.instagramClientID)
        ivar2.util.simplehttp(
            url,
            function(data, _, response)
                return handleOutput(queue, hash, data)
            end,
            true,
            DL_LIMIT
        )
        return true
	end
end
