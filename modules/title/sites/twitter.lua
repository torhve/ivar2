local util = require'util'
local json = util.json
local simplehttp = util.simplehttp
local html2unicode = require'html'
local trim = util.trim

local titleHandler = function(queue, info)
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
  if(not data or data == '') then
    return false
  end

  local ok, jsdata = pcall(json.decode, data)
  if(not ok or type(jsdata) ~= 'table') then
    return false
  end

  local author_name = jsdata.author_name or ''
  local html = jsdata.html
  if(not html) then
    return false
  end

  local title = html:match('<blockquote class=".+"><p lang=".-" dir=".-">(.*)</p>')
  if(not title) then
    return false
  end
  title = title:gsub('<.->', ''):gsub('  ', ' ')

  title = html2unicode(title)
  -- replace newline with single space
  title = title:gsub('\n', ' ')
  -- remove repeating whitespace
  title = trim(title:gsub('%s%s+', ' '))
  queue:done("<"..author_name.."> "..title)
  return true
end

-- luacheck: ignore
customHosts['twitter%.com'] = titleHandler
customHosts['x%.com'] = titleHandler


