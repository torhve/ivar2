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

	-- Allow client to overide request timeout, note that this isn't super precise because we reuse the same timeout for reading headers and such
	if client.timeout then
		req_timeout = client.timeout
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
	end

	local data
	local status_code

	local before = monotime()
	local headers, stream = client:go(req_timeout)
	local after = monotime()

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
		if(limit) then
			data = stream:get_body_chars(limit, req_timeout)
		else
			data = stream:get_body_as_string(req_timeout)
		end
		-- Stream shutdown lets luahttp reuse I'm told
		stream:shutdown()
		if simple_headers['content-encoding'] == 'gzip' then
			data = zlib.inflate()(data)
		end
	end

	local response = {
		headers = simple_headers,
		version = stream.connection.version,
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
