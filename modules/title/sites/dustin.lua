local simplehttp = require'simplehttp'
local html2unicode = require'html'

local trim = function(s)
	if(not s) then return end
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local clean = function(s)
	if(not s) then return end
	return trim(html2unicode(s))
end

local handler = function(queue, info)
	local path = info.path
	if(path and path:match('/product/%d+')) then
		simplehttp(
			info.url,

			function(data, url, response)
				local ins = function(out, fmt, ...)
					for i=1, select('#', ...) do
						local val = select(i, ...)
						if(type(val) == 'nil' or val == -1) then
							return
						end
					end

					table.insert(
						out,
						string.format(fmt, ...)
					)
				end

				local out = {}
				local name = data:match('<span itemprop="name">([^<]+)</span>')
				local desc = data:match('<span itemprop="description">([^<]+)</span>')
				local price, off = data:match('<span.-itemprop="price">([^<]+)</span>.-class="pdPriceWithout"[^>]*>([^<]*)</span>')
				local storage = data:match('<div style="padding%-top: 9px; margin%-left: 5px; float:left;">(.-)</b>')

				ins(out, '\002%s\002: ', clean(name))
				ins(out, '%s', clean(desc))
				ins(out, ', \002%s\002 ', clean(price))

				local extra = {}
				if(#off > 0) then
					local price = clean(price):gsub("\194\160", ""):sub(1, -4)
					local real = clean(off):gsub("\194\160", ""):sub(1, -4)
					ins(extra, '%d off', 100 - (price / real) * 100)
				end

				if(storage) then
					storage = clean(storage:gsub('<%/?[%w:]+.-%/?>', ''))
					ins(extra, '%s', storage:gsub("[!.]$", ""))
				end

				if(#extra > 0) then
					ins(out, '(%s)', table.concat(extra, ', '))
				end

				queue:done(table.concat(out, ''))
			end
		)

		return true
	end
end

customHosts['dustin%.no'] = handler
customHosts['dustinhome%.no'] = handler
