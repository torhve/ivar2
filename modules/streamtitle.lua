local connection = require'handler.connection'
local uri = require'handler.uri'

local datalen = 0
local tcp_client_mt = {
    handle_connected = function(self)
        self.sock:send('GET ' .. self.path .. ' HTTP/1.1\nHost: ' .. self.host .. '\nAccept-Encoding: identity\nUser-Agent: WinampMPEG/5.52\nIcy-Metadata: 1\n\n')
    end,
}
tcp_client_mt.__index = tcp_client_mt
-- new tcp client
local function new_tcp_client(url, cb)
    local info = uri.parse(url, nil, true)
    tcp_client_mt.handle_data = cb
    tcp_client_mt.path = info.path
    tcp_client_mt.host = info.host
    local self = setmetatable({}, tcp_client_mt)
    self.sock = connection.tcp(ivar2.Loop, self, info.host, info.port)
    return self
end

return {
    PRIVMSG = {
        ['^%pstreamtitle (.+)$'] = function(ivar, source, destination, url)
            local resdata = ""
            local client = new_tcp_client(url, function (self, data) 
                datalen = datalen + #data
                resdata = resdata .. data
                if datalen > 65535 then
                    local res = resdata:match("StreamTitle='(.-)'")
                    datalen = 0
                    ivar:Msg('privmsg', destination, source, 'Now playing ♫ \002%s\002', res)
                    self.sock:close()
                end
            end)
        end,
    },
}
