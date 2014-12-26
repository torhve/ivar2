-- vim: set noexpandtab:
local idn = require'idn'
--local uv = require 'uv'
local http = require 'uv.http'
-- uv doesn't know about IDN or non-ASCII.
local uri = require'socket.url'
--local uri = require 'uv.url'
require'logging.console'

local log = logging.console()

local toIDN = function(url)
    print('beofre', url)
  
	local info = uri.parse(url)
	info.host = idn.encode(info.host)

	if(info.port) then
		info.host = info.host .. ':' .. info.port
	end

	local query = ''
	if(info.query) then
		query = "?" .. info.query
	end

	return string.format(
		'%s://%s%s%s%s',

		info.scheme,
		info.userinfo or '',
		info.host,
		info.path or '',
		query
	)
end

local function simplehttp(url, cb, stream, limit, visited)
	local visited = visited or {}
	if(type(url) == "table") then
		url.body = url.data
	else
		url = {url=url}
	end

	-- Add support for IDNs.
	url.url = toIDN(url.url)

	-- Prevent infinite loops!
	if(visited[url.url]) then return end
	visited[url.url] = true

	log:debug(string.format('Fetching URL: %s', url.url))

	local response = http.request(url)
	if(response.status == 301 or response.status == 302) then
		local location = response.headers.Location
		if(location:sub(1, 4) ~= 'http') then
			local info = uri.parse(url)
			location = string.format('%s://%s%s', info.scheme, info.host, location)
		end

		if(url.headers) then
			location = {
				url = location,
				headers = url.headers
			}
		end
		return simplehttp(location, cb, stream, limit, visited)
	end

	-- If give a callback, call it, else return the data
	if(cb) then
		return cb(response.body, url, response)
	else
		return response.body, url, response
	end
	
end

return simplehttp
