local util = require'util'
local json = util.json
local simplehttp = util.simplehttp
local trim = util.trim

local titleHandler = function(queue, info)
	-- local query = info.query
	local path = info.path
	local fragment = info.fragment

	local tid
	local pattern = '/profile/.*/post/'
	if(fragment and fragment:match(pattern)) then
		tid = fragment:match(pattern)
	elseif(path and path:match(pattern)) then
		tid = path:match(pattern)
	end

	if not tid then
		return false
	end


	local url = info.url
  -- https://bsky.app/profile/seamas.bsky.social/post/3lbkxaazxlb2f
  --https://public.api.bsky.app/xrpc/app.bsky.feed.getPostThread?uri=at://seamas.bsky.social/app.bsky.feed.post/3lbkxaazxlb2f

	url = url:gsub('https://bsky.app/profile/', 'at://'):gsub('post', 'app.bsky.feed.post')

	local data = simplehttp("https://public.api.bsky.app/xrpc/app.bsky.feed.getPostThread?uri="..url)

	local jsdata = json.decode(data)


		local thread = jsdata.thread
	local post = thread.post

	local author_name = post.author.displayName
	local title = post.record.text

	local reposts = post.repostCount
	local quotes = post.quoteCount
	local likes = post.likeCount

	-- replace newline with single space
	title = title:gsub('\n', ' ')
	-- remove repeating whitespace
	title = trim(title:gsub('%s%s+', ' '))
	queue:done(("[ %s ] [ %s ] [ %s ] <"):format(reposts, quotes, likes)..author_name.."> "..title)
end

-- luacheck: ignore
customHosts['bsky.app'] = titleHandler
--customHosts[''] = titleHandler


