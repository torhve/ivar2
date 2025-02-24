local util = require'util'
local simplehttp = util.simplehttp
local json = util.json

local generateTitle = function(post)
	if not post or post.error then return end

	local out = {}

	if type(post.subreddit) == "string" and post.subreddit ~= '' then
		table.insert(out, '[' .. tostring(post.subreddit) .. ']')
	end

	if post.title then
		table.insert(out, post.title)
	end

	local tags = {}

	if post.ups and post.downs then
		table.insert(tags, string.format("+%d/-%d", post.ups, post.downs))
	end

	if post.over_18 then
		table.insert(tags, 'NSFW')
	end

	if post.gallery_data and post.gallery_data.items then
		table.insert(tags, string.format("Gallery (%d images)", #post.gallery_data.items))
	end

	table.insert(out, string.format("[%s]", table.concat(tags, ", ")))

	return table.concat(out, " ")
end

customHosts['reddit%.com'] = function(queue, info)

	if not info.path then return end

	local postId = info.path:match('/gallery/([a-zA-Z0-9]+)')
	if not postId then return end

	local url = 'https://www.reddit.com/comments/' .. postId .. '.json'
	local data = simplehttp(url)
	if not data then return end

	local decoded = json.decode(data)
	if decoded and decoded[1] and decoded[1].data and decoded[1].data.children then
		local post = decoded[1].data.children[1].data
		queue:done(generateTitle(post))
		return true
	end
end
