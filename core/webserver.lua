-- vim: set noexpandtab:
local server = require'http.server'
local new_headers = require "http.headers".new
local lconsole = require'logging.console'
local lfs = require'lfs'
local ivar2 = ...
local log = lconsole()

-- Keep this amount in mem before handler has to read from tmpfile
local BODY_BUFFER_SIZE = 2^17

local timeout = 30

local runningserver

local webserver = {}

local respond = function(stream, res, body, code, headers)
	-- don't try to write to idle stream
	if stream.state == 'idle' then
		return
	end
	if not code then code = '200' end
	if not body then body = '' end
	if not headers then headers = {} end
	for k, v in pairs(headers) do
		res:upsert(k, v)
	end
	res:upsert(":status", tostring(code))
	stream:write_headers(res, false, timeout)
	stream:write_body_from_string(body, timeout)
end

local handlerNotFound = function(stream, res)
	respond(stream, res, 'Nyet. I am four oh four', 404)
end

local handlers = {
	['/favicon.ico'] = handlerNotFound
}

webserver.on_stream = function(myserver, stream)
	local ok, err = pcall(function()
		local headers = stream:get_headers(30)
		stream.headers = {}
		local path = '/'
		--print('tls', stream:checktls())
		local _, peer = stream:peername()
		--print('local', stream:localname())
		local res = new_headers()
		if headers then
			for k, v in headers:each() do
				if k == ':path' then
					path = v
					stream.url = v -- for compability
				elseif k == ':method' then
					stream.method = v -- compability
				end
				stream.headers[k] = v
			end
		end
		-- Check if X-Real-IP is set, and blindly trust it
		if stream.headers['x-real-ip'] then
			peer = stream.headers['x-real-ip']
		end
		-- TODO: check content length and decide if needed
		local filename
		-- Save body into a temp file
		if stream.method == 'POST' then
			filename = os.tmpname()
			stream.filename = filename
			local writer = io.open(filename, 'w')
			stream:save_body_to_file(writer, 60*10)
			writer:flush()
			writer:close()
			--- TODO os.execute chmod?
			local size = lfs.attributes(filename).size
			if size < BODY_BUFFER_SIZE then
				local fd = io.open(filename, 'r')
				stream.body = fd:read('*a')
				fd:close()
			end
		end
		local found
		if headers then
			log:info('webserver> "%s %s HTTP/%g" "%s" "%s" "%s"\n',
				headers:get(":method") or "",
				headers:get(":path") or "",
				stream.connection.version,
				peer,
				headers:get("referer") or "-",
				headers:get("user-agent") or "-"
			)
		end

		for pattern, handler in pairs(handlers) do
			if path:match(pattern) then
				log:debug('webserver> serving handler :%s', pattern)
				found = true
				local ok, body, code, response_headers = pcall(handler, ivar2, stream, res)
				if not ok then
					log:error('webserver> error for URL pattern: %s: %s', pattern, body)
				else
					-- Handlers can also write to stream directly, so check for body
					if body and stream.state ~= 'closed' then -- check if not closed
						respond(stream, res, body, code, response_headers)
					end
					-- Assume handler has already sent response.
				end
				break
			end
		end
		if not found then
			log:info('webserver> returning 404 for request: %s', path)
			handlerNotFound(stream, res)
		end
		if filename then
			log:debug('webserver> deleting tmp file: %s', filename)
			os.remove(filename)
		end
		stream:shutdown()
	end)
	if not ok then
		log:error('webserver> error: req %s, err %s', stream, err)
	end
end

webserver.start = function(host, port, cq)
	if not (host and port) then
		return
	end
	log:info('webserver> starting webserver: %s:%s', host, port)
	runningserver = server.listen{
		host = host,
		port = port,
		onstream = webserver.on_stream,
		cq = cq,
		onerror = function(myserver, context, op, err, errno)
			if op == "onstream" and err == 32 then return end
			local msg = op .. " on " .. tostring(context) .. " failed"
			if err then
				msg = msg .. ": " .. tostring(err)
			end
			log:error('webserver> %s', msg)
		end;
	}
	return runningserver
end

webserver.stop = function()
	if(not runningserver) then return end

	log:info('webserver> stopping webserver.')
	runningserver:close()
end

webserver.regUrl = function(pattern, handler)
	log:info('webserver> registering new handler for URL pattern: %s', pattern)
	handlers[pattern] = handler
end

webserver.unRegUrl = function(pattern)
	log:info('webserver> unregistering handler for URL pattern: %s', pattern)
	handlers[pattern] = nil
end

return webserver
