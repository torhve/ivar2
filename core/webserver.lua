local util = require'util'
local httpserver = require'handler.http.server'
local ev = require'ev'
require'logging.console'
local log = logging.console()
local loop = ev.Loop.default

local server = nil

local webserver = {}

local handlers = {
    ['/favicon.ico'] = function(req, res)
        -- return 404 Not found error
        res:set_status(404)
        res:send()
        return
    end,
}

local on_response_sent = function(res)
end

local on_data = function(req, res, data)
    -- Save the body into the request
    req.body = data or ''
end

local on_request = function(server, req, res)
    local found = false
    for pattern, handler in pairs(handlers) do
        if req.url:match(pattern) then
            log:info('webserver> request for pattern :%s', pattern)
            found = true
            req.on_finished = handler
            req.on_data = on_data
            break
        end
    end
    if not found then
        log:info('webserver> returning 404 for request: %s', req.url)
        req.on_finished = function(req, res)
            res:set_status(404)
            res:send()
            return
        end
    end
  res.on_response_sent = on_response_sent
end

webserver.start = function(host, port)
    if not (host and port) then
        return
    end
    log:info('webserver> starting webserver: %s:%s', host, port)
    server = httpserver.new(loop, {
        name = "ivar2-HTTPServer/0.0.1",
        on_request = on_request,
        request_head_timeout = 15.0,
        request_body_timeout = 15.0,
        write_timeout = 15.0,
        keep_alive_timeout = 15.0,
        max_keep_alive_requests = 10,
    })
    server:listen_uri("tcp://"..host..":"..tostring(port).."/")
end

webserver.stop = function()
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
