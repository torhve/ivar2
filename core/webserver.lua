-- vim: set noexpandtab:
local httpserver = require'handler.http.server'
local ev = require'ev'
local nixio = require'nixio'
local lconsole = require'logging.console'
local log = lconsole()
local loop = ev.Loop.default

-- Keep this amount in mem before handler has to read from tmpfile
local BODY_BUFFER_SIZE = 2^17

local server

local webserver = {}

local handlers = {
	['/favicon.ico'] = function(req, res)
		-- return 404 Not found error
		res:set_status(404)
		res:send()
	end,
}

local on_response_sent = function(res)
	if res.filename then
		log:info('webserver> on_response_sent: deleting tmp file: %s', res.filename)
		nixio.fs.unlink(res.filename)
	end
end

local on_error = function(req, res, err)
	log:info('webserver> error: req %s, res %s, err %s', req, res, err)
end

-- Will be called for every chunk
local on_data = function(req, res, data)
	if data then
		-- Save the chunks into a temp file
		if not req.fd then
			local filename = os.tmpname()
			req.filename = filename
			-- Save filename in request so it can be cleaned up in on_response_sent
			res.filename = filename
			-- Append mode, owner only
			req.fd = nixio.open(filename, 'a', 0400)
		end
		req.fd:write(data)
		if not req.body then
			req.body = data
		else
			if #req.body < BODY_BUFFER_SIZE then
				req.body = req.body .. data
			end
		end
	end
end

local on_finish = function(req, handler)
	-- If file upload has been in progress, close the tmpfile
	if req.fd then
		req.fd:sync()
		req.fd:close()
	end
	-- Check size of tmpfile, if it's small, read into memory
	return handler
end

local on_request = function(cur_server, req, res)
	local found
	for pattern, handler in pairs(handlers) do
		if req.url:match(pattern) then
			log:info('webserver> request for pattern :%s', pattern)
			found = true
			req.on_finished = on_finish(req, handler)
			req.on_data = on_data
			req.on_error = on_error
			-- Stream incoming data
			req.stream_response = true
			res.on_response_sent = on_response_sent
			break
		end
	end
	if not found then
		log:info('webserver> returning 404 for request: %s', req.url)
		req.on_finished = function(cur_req, cur_res)
			cur_res:set_status(404)
			cur_res:send()
		end
	end
end

webserver.start = function(host, port)
	if not (host and port) then
		return
	end
	log:info('webserver> starting webserver: %s:%s', host, port)
	server = httpserver.new(loop, {
		name = "ivar2-HTTPServer/0.0.1",
		on_request = on_request,
		--on_error = on_error,
		request_head_timeout = 15.0,
		request_body_timeout = 60.0, -- for file upload I guess
		write_timeout = 15.0,
		keep_alive_timeout = 15.0,
		max_keep_alive_requests = 10,
	})
	server:listen_uri("tcp://"..host..":"..tostring(port).."/")
end

webserver.stop = function()
	if(not server) then return end

	log:info('webserver> stopping webserver.')
	server.acceptors[1]:close()
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
