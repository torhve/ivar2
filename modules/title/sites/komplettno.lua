local simplehttp = require'simplehttp'

local trim = function(s)
	if(not s) then return end
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

customHosts['komplett%.no'] = function(queue, info)
	local query = info.query
	if(query and query:match('sku=%d+')) then
		simplehttp(
			info.url,

			function(data, url, response)
				local out = {}
				local ins = function(fmt, ...)
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

				local name = data:match('<h1 id="ki_h_maktx" itemprop="name">([^<]+)</h1>')
				local desc = data:match('<h2 class="name2" itemprop="description">([^<]+)</h2>')
				local price = data:match('<strong class="price">([^<]+)</strong>')
				local storage = data:match('<div class="availability">Lagerstatus:(.-)</div>')

				ins('\002%s\002: ', name)
				ins('%s', desc)
				if(price) then
					ins(', \002%s\002 ', trim(price))
				end
				if(storage) then
					ins('(%s)', trim(storage:gsub('<%/?[%w:]+.-%/?>', '')):sub(1, -2))
				end

				queue:done(table.concat(out, ''))
			end
		)

		return true
	end
end
