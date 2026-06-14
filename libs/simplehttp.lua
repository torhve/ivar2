local httpclient = require'http.request'
local monotime = require "cqueues".monotime
local uri_parse = require'uriparse'
local idn = require'idn'
local zlib = require'zlib'
local lconsole = require'logging.console'
local log = lconsole()

-- Change to DEBUG if you want to see full URL fetch log
--log:setLevel('INFO')
log:setLevel('DEBUG')

local function simplehttp(url, callback, unused, limit)
	local req_timeout = 500

	local uri
	if(type(url) == "table") then
		uri = url.url or url[1]
	else
		uri = url
	end

	-- Don't include fragments in the request.
	uri = uri:gsub('#.*$', '')
	-- Trim whitespace
	uri = uri:gsub('%s+$', '')
	uri = uri:gsub('^%s+', '')

	-- IDN hack for now, until http/uriparse supports it
	uri = uri:gsub('://(.-)%.', function(match)
		if match:sub(1,1) ~= '[' then
			match = idn.encode(match)
		end
		return '://'..match..'.'
	end, 1)

	log:debug('simplehttp> request <%s>', uri)

	local uri_t = uri_parse(uri)
	local client = httpclient.new_from_uri(uri_t)

	-- Allow override of client HTTP version
	if url.version then
		client.version = url.version
	end

	if(type(url) == "table") then
		if(url.headers) then
			for k, v in next, url.headers do
				if not client.version or client.version and client.version >= 2 then
					-- HTTP2 needs lowercase
					k = string.lower(k)
				end
				-- Overwrite any existing
				client.headers:upsert(k, v)
			end
		end

		if(url.method) then
			client.headers:upsert(":method", url.method)
		end

		if(url.data) then
			client:set_body(url.data)
		end

		if(url.timeout) then
			client.timeout = url.timeout
		end
	end

	-- Allow client to overide request timeout, note that this isn't super precise because we reuse the same timeout for reading headers and such
	if client.timeout then
		req_timeout = client.timeout
	end

	local data
	local status_code
	local headers, stream

	local before = monotime()
	local ok
	ok, headers, stream = pcall(client.go, client, req_timeout)
	local after = monotime()

	if not ok then
		log:error('simplehttp> request <%s>, exception: %s. After %s', uri, headers, (after-before))
		return nil, headers
	end

	if not headers then
		log:error('simplehttp> request %s, error :%s. After %s', uri, stream, (after-before))
		return nil, stream
	end
	status_code = headers:get(':status')
	-- H2 might not be number
	status_code = tonumber(status_code, 10) or status_code

	local simple_headers = {}
	for k,v in headers:each() do
		-- Will overwrite duplicate headers.
		simple_headers[k] = v
	end

	if stream then
		ok, data = pcall(function()
			local body
			if(limit) then
				body = stream:get_body_chars(limit, req_timeout)
			else
				body = stream:get_body_as_string(req_timeout)
			end
			-- Stream shutdown lets luahttp reuse I'm told
			stream:shutdown()
			return body
		end)
		if not ok then
			log:error('simplehttp> request <%s>, body read exception: %s', uri, data)
			pcall(stream.shutdown, stream)
			return nil, data
		end
		if simple_headers['content-encoding'] == 'gzip' then
			local inflate = zlib.inflate()
			ok, data = pcall(inflate, data)
			if not ok then
				log:error('simplehttp> request <%s>, decompression error: %s', uri, data)
				return nil, data
			end
		end
	end

	local elapsed = monotime() - before
	log:debug('simplehttp> response <%s> status=%d time=%.3fs', uri, status_code, elapsed)

	local conn_version = stream and stream.connection and stream.connection.version
	local response = {
		headers = simple_headers,
		version = conn_version,
		status_code = status_code -- for compability with old simplehttp API
	}
	-- Old style callback
	if callback then
		callback(data, uri, response)
	end
	-- New style.
	return data, uri, response
end

return simplehttp
