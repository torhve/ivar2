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
				local name = data:match('<meta itemprop="name" content="([^"]+)" />')
				local desc = data:match('<h3 class="oneliner">(.-)</h3>')
				local price = data:match('<meta itemprop="price" content="([^"]+)" />')
				local priceOriginal = data:match('<span class="price original">([^<]+)</span>')
				local storage = data:match('<li class="h4">Lagerstatus: (.-)</li>')

				ins(out, '\002%s\002: ', clean(name))
				ins(out, '%s', clean(desc))
				ins(out, ', \002%s\002 ', clean(price))

				local extra = {}
				if(priceOriginal) then
					local price = clean(price:gsub('%s*', '')):sub(1, -4)
					local real = clean(priceOriginal:gsub('%s*', '')):sub(1, -4)
					ins(extra, '%d%% off', 100 - (price / real) * 100)
				end

				if(storage) then
					local message = storage:match("data%-original%-title='([^']+)'")
					local stock = storage:match("<span class='small'>([^>]+)</span>")

					if(stock) then
						ins(extra, '%s', stock)
					else
						ins(extra, '%s', message:gsub('%s+', ' '))
					end
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
