local util = require'util'
local json = util.json
local simplehttp = util.simplehttp
local html2unicode = require'html'
local trim = util.trim

local titleHandler = function(queue, info)
	-- local query = info.query
	local path = info.path
	local fragment = info.fragment
	local tid

	local pattern = '/status[es]*/(%d+)'
	if(fragment and fragment:match(pattern)) then
		tid = fragment:match(pattern)
	elseif(path and path:match(pattern)) then
		tid = path:match(pattern)
	end

	if not tid then
		return false
	end


  local url = info.url

  local data = simplehttp("https://publish.twitter.com/oembed?url="..url)

  local jsdata = json.decode(data)

  local author_name = jsdata.author_name
  local html = jsdata.html

  local title = html:match('<blockquote class=".+"><p lang=".-" dir=".-">(.*)</p>')
  title = title:gsub('<.->', ''):gsub('  ', ' ')

  title = html2unicode(title)
  -- replace newline with single space
  title = title:gsub('\n', ' ')
  -- remove repeating whitespace
  title = trim(title:gsub('%s%s+', ' '))
  queue:done("<"..author_name.."> "..title)
end

-- luacheck: ignore
customHosts['twitter%.com'] = titleHandler
customHosts['x%.com'] = titleHandler


