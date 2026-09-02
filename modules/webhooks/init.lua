local util = require 'util'
local lfs = require 'lfs'

local function unescape(str)
    local hex_to_char = function(x)
        return string.char(tonumber(x, 16))
    end
    -- Replace + with space first (form encoding), then decode percent-escapes
    return str:gsub('+', ' '):gsub('%%(%x%x)', hex_to_char)
end

local function parse_form_encoded(body)
    local result = {}
    for pair in body:gmatch('([^&]+)') do
        local k, v = pair:match('([^=]+)=(.*)')
        if k and v then
            local decoded_v = unescape(v)
            -- Normalize: empty strings to nil, bool strings, numeric strings
            if decoded_v == '' then
                result[unescape(k)] = nil
            elseif decoded_v == 'True' then
                result[unescape(k)] = true
            elseif decoded_v == 'False' then
                result[unescape(k)] = false
            else
                local num = tonumber(decoded_v)
                result[unescape(k)] = num or decoded_v
            end
        end
    end
    return result
end

-- Load per-system formatters from modules/webhooks/systems/*.lua
-- Each file returns a function (data -> message|nil); filename is the system name.
local handlers = {}
do
    local _PROXY = setmetatable({
        ivar2 = ivar2,
        util = util,
    }, { __index = _G })

    local path = 'modules/webhooks/systems/'
    for fn in lfs.dir(path) do
        if fn:match('%.lua$') then
            local name = fn:sub(1, -5)
            local f, err = loadfile(path .. fn)
            if f then
                setfenv(f, _PROXY)
                local ok, handler = pcall(f)
                if ok and type(handler) == 'function' then
                    handlers[name] = handler
                    ivar2:Log('info', 'webhooks> loaded system: %s', name)
                else
                    ivar2:Log('error', 'webhooks> failed to load system %s: %s', name, handler)
                end
            else
                ivar2:Log('error', 'webhooks> unable to load %s: %s', fn, err)
            end
        end
    end
end

ivar2.webserver.regUrl('/webhooks/([^/]+)/(.+)$', function(self, req, res)
    local path = req.url
    local system, destination = path:match('/webhooks/([^/]+)/(.+)$')

    if not system or not destination then
        res:append(':status', '404')
        req:write_headers(res, false, 30)
        req:write_body_from_string('bad URL', 30)
        return
    end

    destination = unescape(destination)

    local secret = req.headers['x-webhook-secret']
    local confsecret = ivar2.config.webhookSecrets and ivar2.config.webhookSecrets[system]

    if confsecret then
        if not secret or secret ~= confsecret then
            ivar2:Log('error', 'webhooks> %s webhook with invalid/missing secret from %s', system,
                req.headers['x-real-ip'] or 'unknown')
            res:append(':status', '403')
            res:append('Content-Type', 'text/plain')
            req:write_headers(res, false, 30)
            req:write_body_from_string('invalid secret', 30)
            return
        end
    end

    local handler = handlers[system]
    if not handler then
        ivar2:Log('error', 'webhooks> unknown system: %s', system)
        res:append(':status', '404')
        res:append('Content-Type', 'text/plain')
        req:write_headers(res, false, 30)
        req:write_body_from_string('unknown system', 30)
        return
    end

    -- Get body from buffer or temp file
    local body = req.body
    if not body and req.filename then
        local fd = io.open(req.filename, 'r')
        if fd then
            body = fd:read('*a')
            fd:close()
        end
    end

    if not body or body == '' then
        ivar2:Log('error', 'webhooks> empty body for system: %s', system)
        res:append(':status', '400')
        res:append('Content-Type', 'text/plain')
        req:write_headers(res, false, 30)
        req:write_body_from_string('empty body', 30)
        return
    end

    -- Detect content type and parse accordingly
    local data
    local ctype = (req.headers['content-type'] or ''):lower()
    if ctype:find('application/json') then
        data = util.json.decode(body)
    else
        -- Dispatcharr sends form-encoded by default when no template is set
        data = parse_form_encoded(body)
    end

    local message = handler(data)

    if message then
        ivar2:Msg('privmsg', destination, nil, message)
    end

    res:append(':status', '200')
    res:append('Content-Type', 'text/plain')
    req:write_headers(res, false, 30)
    req:write_body_from_string('ok', 30)
end)

return { handlers = handlers, parse_form_encoded = parse_form_encoded }
