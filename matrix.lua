-- ivar2 matrix module
-- vim: set expandtab:

package.path = table.concat({
	'libs/?.lua',
	'libs/?/init.lua',

	'',
}, ';') .. package.path

package.cpath = table.concat({
	'libs/?.so',

	'',
}, ';') .. package.cpath

local configFile, reload = ...

-- Check if we have moonscript available
local moonstatus, moonscript = pcall(require, 'moonscript')
moonscript = moonstatus and moonscript


local event = require 'event'
local util = require 'util'
local lconsole = require'logging.console'
local lfs = require 'lfs'
local cqueues = require'cqueues'
--local signal = require'cqueues.signal'
local queue = cqueues.new()
local json = util.json

local module_envs = setmetatable({}, { __mode = 'k' })

local polling_interval = 30

local log = lconsole()
math.randomseed(os.time())

local ivar2

local safeFormat = function(format, ...)
    if(select('#', ...) > 0) then
        local success, message = pcall(string.format, format, ...)
        if(success) then
            return message
        end
    else
        return format
    end
end

local tableHasValue = function(table, value)
    if(type(table) ~= 'table') then return end

    for _, v in next, table do
        if(v == value) then return true end
    end
end

local urllib = {}
urllib.quote = function(str)
    if not str then return '' end
    if type(str) == 'number' then return str end
    return str:gsub(
    '([^%w ])',
    function (c)
        return string.format ("%%%02X", string.byte(c))
    end
    ):gsub(' ', '+')
end
urllib.urlencode = function(tbl)
    local out = {}
    for k, v in pairs(tbl) do
        table.insert(out, urllib.quote(k)..'='..urllib.quote(v))
    end
    return table.concat(out, '&')
end
urllib.html_escape = function(s)
    return (string.gsub(s, "[}{\">/<'&]", {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
        ["/"] = "&#47;"
    }))
end

local function byte_to_tag(s, byte, open_tag, close_tag)
    if s:match(byte) then
        local inside = false
        local open_tags = 0
        local htmlbody = s:gsub(byte, function(c)
            if inside then
                inside = false
                return close_tag
            end
            inside = true
            open_tags = open_tags + 1
            return open_tag
        end)
        local _, count = htmlbody:gsub(close_tag, '')
        -- Ensure we close tags
        if count < open_tags then
            htmlbody = htmlbody .. close_tag
        end
        return htmlbody
    end
    return s
end

local function irc_formatting_to_html(s)
    s = urllib.html_escape(s)
    -- TODO, support foreground and background?
    local ct = {'white','black','blue','green','red','maroon','purple',
        'orange','yellow','lightgreen','teal','cyan', 'lightblue',
        'fuchsia', 'gray', 'lightgray'}

    s = byte_to_tag(s, '\02', '<em>', '</em>')
    s = byte_to_tag(s, '\029', '<i>', '</i>')
    s = byte_to_tag(s, '\031', '<u>', '</u>')
    -- First do full color strings with reset.
    -- Iterate backwards to catch long colors before short
    for i=#ct,1,-1 do
        s = s:gsub(
            '\0030?'..tostring(i-1)..'(.-)\003',
            '<font color="'..ct[i]..'">%1</font>')
    end

    -- Then replace unmatch colors
    -- Iterate backwards to catch long colors before short
    for i=#ct,1,-1 do
        local c = ct[i]
        s = byte_to_tag(s, '\0030?'..tostring(i-1),
            '<font color="'..c..'">', '</font>')
    end
    return s
end

local MatrixServer = {}
MatrixServer.__index = MatrixServer
local Room = {}
Room.__index = Room

MatrixServer.create = function()
    local server = {}
    setmetatable(server, MatrixServer)
    server.nick = nil
    server.connecting = false
    server.polling = false
    server.connected = false
    server.rooms = {}
    server.out = {}
    -- hardcoded value, could maybe parse homeserver URI?
    server.network = 'matrix'
    -- Store user presences here since they are not local to the rooms
    server.presence = {}
    server.end_token = 'END'

    server.ignores = {}
    server.event = event
    server.channels = {}
    server.more = {}
    server.timers = {}
    server.cancelled_timers = {}
    server.events = {}
    server.util = util

    return server
end

function MatrixServer:Log(level, ...)
    local message = safeFormat(...)
    if(message) then
        log[level](log, message)
    end
end

function MatrixServer:http(url, post, command)
    local homeserver_url = self.config.uri
    homeserver_url = homeserver_url .. "_matrix/client/r0"
    url = homeserver_url .. url
    local method = 'GET'
    if post.postfields then
        method = 'POST'
    end
    if post.customrequest then
        method = post.customrequest
    end
    local data = {
        url = url,
        method = method,
        data = post.postfields,
    }

    local res, r_url, response = util.simplehttp(data)
    if not res then
        -- error being logged by simplehttp
        return
    end
    return self:http_cb(command, res, r_url, response)
end

function MatrixServer:http_cb(command, data, url, response)
    if response.status_code ~= 200 or not data then
        self:Log('error', 'http_cb, command: %s, status: %s, data: %s', command, response.status_code, data)
        return
    end

    -- Protected call in case of JSON errors
    local success, js = pcall(json.decode, data)
    if not success then
        self:Log('error', 'http_cb, command: %s, error: %s, during json load of: %s', command, js, data)
        -- reset polling if error during events
        if command:find'/sync' then
            self.polling = false
            -- Wait a bit so it's not super spammy
            self:Timer('_errpoll', 30, 0, function()
                self:poll()
            end)
        end
        return
    end
    if js['errcode'] then
        if command:find'login' then
            print(('matrix: Error code during login: %s'):format(
                js['errcode']))
        else
            print(js.errcode)
            print(js['error'])
        end
        return
    end
    -- Get correct handler
    if command:find('login') then
        for k, v in pairs(js) do
            self[k] = v
        end
        self.connected = true
        self:initial_sync()
    elseif command:find'/sync' or command:find'/initialsync' then
        self.polling = false
        local backlog = false
        local initial = false

        self.end_token = js.next_batch

        if command:find'/initialsync' then
            initial = true
            backlog = true
        end

        -- Start with setting the global presence variable on the server
        -- so when the nicks get added to the room they can get added to
        -- the correct nicklist group according to if they have presence
        -- or not
        for _, e in ipairs(js.presence.events) do
            self:UpdatePresence(e)
        end
        for membership, rooms in pairs(js['rooms']) do
            -- If we left the room, simply ignore it
            if membership ~= 'leave' then
                for identifier, room in pairs(rooms) do
                    -- Monkey patch it to look like v1 object
                    room.room_id = identifier
                    local myroom
                    if initial then
                        myroom = self:addRoom(room)
                    else
                        myroom = self.rooms[identifier]
                        -- Chunk for non-existing room
                        if not myroom then
                            myroom = self:addRoom(room)
                            if not membership == 'invite' then
                                print('Event for unknown room')
                            end
                        end
                    end
                    -- Parse states before messages so we can add nicks and stuff
                    -- before messages start appearing
                    local states = room.state
                    if states then
                        local chunks = room.state.events or {}
                        for _, chunk in ipairs(chunks) do
                            myroom:ParseChunk(chunk, backlog, 'states')
                        end
                    end
                    local timeline = room.timeline
                    if timeline then
                        -- Save the prev_batch on the initial message so we
                        -- know for later when we picked up the sync
                        if initial then
                            myroom.prev_batch = timeline.prev_batch
                        end
                        local chunks = timeline.events or {}
                        for _, chunk in ipairs(chunks) do
                            myroom:ParseChunk(chunk, backlog, 'messages')
                        end
                    end
                    local ephemeral = room.ephemeral
                    -- Ignore Ephemeral Events during initial sync
                    if not initial and ephemeral then
                        local chunks = ephemeral.events or {}
                        for _, chunk in ipairs(chunks) do
                            myroom:ParseChunk(chunk, backlog, 'states')
                        end
                    end
                    if backlog then
                        -- All the state should be done. Try to get a good name for the room now.
                        myroom:SetName(myroom.identifier)
                    end
                end
            end
        end
        -- Now we have created rooms and can go over the rooms and update
        -- the presence for each nick
        for _, e in pairs(js.presence.events) do
            self:UpdatePresence(e)
        end

        -- We have our backlog, lets start listening for new events
        if initial then
            -- Timer used in cased of errors to restart the polling cycle
            -- During normal operation the polling should re-invoke itself
            self.polltimer = self:Timer('_poll', polling_interval+1, polling_interval+1, function()
                self:pollcheck()
            end)
            self:LoadModules()
            -- Auto join configured channels
            for channel, _ in next, self.config.channels do
                -- Check for :, can only join rooms with :
                if not self.channels[channel] and channel:match':' then
                    local found = false
                    for id, room in pairs(self.rooms) do
                        if channel == id or
                           channel == room.shortname or
                           channel == room.fullname or
                           channel == room.canonical_alias or
                           channel == room.name then
                           found = true
                           break
                       end
                    end
                    if not found then
                        self:Join(channel)
                    end
                end
            end
        end
        self:poll()
    -- luacheck: ignore
    elseif command:find'/join/' then
        -- Don't do anything
    elseif command:find'leave' then
        -- We store room_id in data
        local room_id = data
        self:delRoom(room_id)
    elseif command:find'upload' then
        return js.content_uri
    elseif command:find'/typing/' then
        -- either it errs or it is empty
    elseif command:find'/state/' then
        -- either it errs or it is empty
    elseif command:find'/send/' then
        -- XXX Errorhandling
    elseif command:find'createRoom' then
        local room_id = js.room_id
        -- We get join events, so we don't have to do anything
    elseif command:find'/publicRooms' then
        print 'Public rooms:'
        print '\tName\tUsers\tTopic\tAliases'
        for _, r in pairs(js.chunk) do
            local name = ''
            if r.name ~= json.null then
                name = r.name
            end
            print(('%s %s %s %s')
                :format(
                    name,
                    r.num_joined_members,
                    r.topic,
                    table.concat(r.aliases, ', ')))
        end
    elseif command:find'/invite' then
        local room_id = js.room_id
    end
end

function MatrixServer:UpdatePresence(c)
    local user_id = c.sender or c.content.user_id
    self.presence[user_id] = c.content.presence
    for id, room in pairs(self.rooms) do
        room:UpdatePresence(c.sender, c.content.presence)
    end
end


function MatrixServer:_getPost(post)
    local extra = {
        accept_encoding= 'application/json',
        postfields = json.encode(post)
    }
    return extra
end

function MatrixServer:findRoom(fullname)
    for id, room in pairs(self.rooms) do
        if room.fullname == fullname then
            return room
        elseif room.name == fullname then
            return room
         -- because of IRC heritage
        elseif room.name:lower() == fullname:lower() then
            return room
        end
    end
end

function MatrixServer:connect(config)
    self.config = config
    if not self.connecting then
        self.connecting = true
        print('matrix: Connecting to homeserver URL: '..  config.uri)
        local post = {
            ["type"] = "m.login.password",
            ["user"] = config.nick,
            ["password"] = config.password
        }

        if(not self.persist) then
            -- Load persist library using config
            self.persist = require(config.persistbackend or 'sqlpersist')({
                path = config.kvsqlpath or 'cache/keyvaluestore.sqlite3',
                verbose = false,
                namespace = 'ivar2',
                clear = false
            })
        end

        if(not self.webserver) then
            self.webserver = assert(loadfile('core/webserver.lua'))(self)
            local cqueue = cqueues.running()
            cqueue:wrap(function()
                pcall(function()
                    self.webserver.start(self.config.webserverhost, self.config.webserverport, cqueue)
                end)
            end)
        end

        if(not self.x0) then
            self.x0 = assert(loadfile('core/x0.lua'))(self)
        end

        self:http('/login', self:_getPost(post), ('login'))

        self.nick = config.nick
    end
end

function MatrixServer:initial_sync()
    local data = urllib.urlencode({
        access_token = self.access_token,
        timeout = 1000*60*5,
        full_state = 'true',
        filter = json.encode({ -- timeline filter
            room = {
                timeline = {
                    limit = 0, -- dont want backlog
                }
            },
            presence = {
                not_types = {'*'}, -- dont want presence
            },
        })
    })
    self:http('/sync?'..data, {}, ('/initialsync'))
end

function MatrixServer:getMessages(room_id)
    local data = urllib.urlencode({
        access_token= self.access_token,
        dir = 'b',
        from = 'END',
        limit = 0, -- nobacklog
    })
    self:http(('/rooms/%s/messages?%s')
        :format(urllib.quote(room_id), data), {}, 'messages')
end

function MatrixServer:Join(room)
    if not self.connected then
        --XXX'''
        return
    end

    self:Log('info', 'Joining room %s', room)
    self:http('/join/' .. urllib.quote(room)..'?access_token='..self.access_token,
        {customrequest = 'POST'}, '/join/')
end

function MatrixServer:part(room)
    if not self.connected then
        --XXX'''
        return
    end

    local id = urllib.quote(room.identifier)
    local data = urllib.urlencode({
        access_token= self.access_token,
    })
    -- TODO: close buffer, delete data, etc
    self:http(('/rooms/%s/leave?%s'):format(id, data), {postfields= "{}"},
        '/leave')
end

function MatrixServer:Timer(id, interval, repeat_interval, callback)
    -- Check if invoked with repeat interval or not
    if not callback then
        callback = repeat_interval
        repeat_interval = nil
    end
    -- Construct callback
    local callbackHandler = function(cb)
        return function(...)
            local success, message = pcall(cb, ...)
            if(not success) then
                self:Log('error', 'Error during timer callback %s: %s.', id, message)
            end
            -- Delete expired timer
            if(not repeat_interval and self.timers[id]) then
                self.timers[id] = nil
            end
        end
    end
    local func = callbackHandler(callback)
    -- Check for existing
    if self.timers[id] then
        -- Only allow one timer per id
        -- Cancel any running
        self:Log('info', 'Cancelling existing timer: %s', id)
        self.timers[id]:stop()
    end
    local is_cancelled = function()
        for i, t in ipairs(self.cancelled_timers) do
            if t.id == id then
                table.remove(self.cancelled_timers, i)
                return true
            end
        end
    end
    local timer = {
        id = id,
        cancelled = false,
        stop = function(timer)
            self.timers[id].cancelled = true
            table.insert(self.cancelled_timers, self.timers[id])
            self.timers[id] = nil
        end,
        run = function()
            cqueues.sleep(interval)
            if is_cancelled() then return end
            func()
            if repeat_interval then
                while true do
                    cqueues.sleep(repeat_interval)
                    if is_cancelled() then return end
                    func()
                end
            end
        end
    }
    local controller = cqueues.running()
    timer.controller = controller:wrap(timer.run)
    self.timers[id] = timer
    return timer
end

function MatrixServer:pollcheck()
    -- Restarts the polling sequence in case it errored out somewhere
    if ((os.time() - self.polltime) > (polling_interval)) then
        self:Log('info', 'Resetting polling status!')
        self.polling = false
        -- Wait a bit so it's not super spammy
        self:Timer('_errpoll', 30, 0, function()
            self:poll()
        end)
    end
end

function MatrixServer:poll()
    if (self.connected == false or self.polling) then
        return
    end
    --self:Log('info', 'Polling for events with end token: %s', self.end_token)
    self.polling = true
    self.polltime = os.time()
    local data = urllib.urlencode({
        access_token = self.access_token,
        timeout = 1000*polling_interval,
        full_state = 'false',
        since = self.end_token
    })
    self:http('/sync?'..data, {}, ('/sync'))
end

function MatrixServer:addRoom(room)
    local myroom = Room.create(room, self)
    self.rooms[room['room_id']] = myroom
    local name = myroom.name
    if(not self.channels[name]) then
        self:Log('info', 'Adding room <%s>', name)
        self.channels[name] = {
            nicks = {},
            modes = {},
        }
    end
    return myroom
end

function MatrixServer:delRoom(room_id)
    for id, room in pairs(self.rooms) do
        if id == room_id then
            print('\tLeaving room '..room.name..':'..room.server)
            room:destroy()
            self.rooms[id] = nil
            break
        end
    end
end

function MatrixServer:_msg(room_id, body, msgtype, url, info)
    if not msgtype then
        msgtype = 'm.notice'
    end

    if not self.out[room_id] then
        self.out[room_id] = {}
    end
    table.insert(self.out[room_id], {msgtype, body, url, info})
    self:send()
end

function MatrixServer:Privmsg(destination, ...)
    local room = self:findRoom(destination)
    local body = safeFormat(...)
    self:SimpleDispatch('PRIVMSG_OUT', body, {nick=self.config.nick}, destination)
    self:_msg(room.identifier, body)
end

function MatrixServer:Msg(msgtype, destination, source, ...)
    local room = self:findRoom(destination)
    if(room) then
       local body = safeFormat(...)

        self:SimpleDispatch('PRIVMSG_OUT', body, {nick=self.config.nick}, destination)
        self:_msg(room.identifier, body)
    end
end

function MatrixServer:Say(destination, source, ...)
    local room = self:findRoom(destination)
    local body = safeFormat(...)
    self:SimpleDispatch('PRIVMSG_OUT', body, {nick=self.config.nick}, destination)
    self:_msg(room.identifier, body)
end

function MatrixServer:Reply(destination, source, format, ...)
    return self:Msg('privmsg', destination, source, source.nick..': '..format, ...)
end

function MatrixServer:send()
    -- Iterate rooms
    for id, msgs in pairs(self.out) do
        -- Clear message
        self.out[id] = nil
        local body = {}
        local htmlbody = {}
        local msgtype
        local url
        local info

        local ishtml = false


        for _, msg in ipairs(msgs) do
            -- last msgtype will override any other for simplicity's sake
            msgtype = msg[1]
            local html = irc_formatting_to_html(msg[2])
            if html ~= msg[2] then
                ishtml = true
            end
            table.insert(htmlbody, html )
            table.insert(body, msg[2] )
            if msg[3] then -- Primarily image upload
                url = msg[3]
            end
            if msg[4] then -- Image upload info possibly more in the future?
                info = msg[4]
            end
        end
        body = table.concat(body, '\n')

        local data = {
            accept_encoding = 'application/json',
            postfields= {
                msgtype = msgtype,
                body = body,
                url = url,
                info = info,
            }
        }

        if ishtml then
            htmlbody = table.concat(htmlbody, '\n')
            data.postfields.body = util.stripformatting(body)
            data.postfields.format = 'org.matrix.custom.html'
            data.postfields.formatted_body = htmlbody
        end


        data.postfields = json.encode(data.postfields)


        self:http(('/rooms/%s/send/m.room.message?access_token=%s')
            :format(
              urllib.quote(id),
              urllib.quote(self.access_token)
            ),
              data,
              '/send/'
            )
    end
end

function MatrixServer:emote(room_id, body)
    self:_msg(room_id, body, 'm.emote')
end

function MatrixServer:state(room_id, key, data)
    self:http(('/rooms/%s/state/%s?access_token=%s')
        :format(urllib.quote(room_id),
          urllib.quote(key),
          urllib.quote(self.access_token)),
        {customrequest = 'PUT',
         accept_encoding = 'application/json',
         postfields= json.encode(data),
        }, '/state/')
end

function MatrixServer:set_membership(room_id, userid, data)
    self:http(('/rooms/%s/state/m.room.member/%s?access_token=%s')
        :format(urllib.quote(room_id),
          urllib.quote(userid),
          urllib.quote(self.access_token)),
        {customrequest = 'PUT',
         accept_encoding = 'application/json',
         postfields= json.encode(data),
        }, 'state')
end

function MatrixServer:Kick(destination, userid, reason)
    local room = self:findRoom(destination)
    if not room then
        self:Log('WARNING', 'Room %s not found during kick', destination)
        return
    end
    local data = {
        membership = 'leave',
        reason = 'Kicked by '..self.user_id
    }
    self:set_membership(room.identifier, userid, data)
end

function MatrixServer:Upload(destination, remoteurl, message)
    local room = self:findRoom(destination)
    local filedata, _, res = util.simplehttp(remoteurl)
    local content_type = res.headers['content-type']

    local homeserver_url = self.config.uri
    homeserver_url = homeserver_url .. "_matrix/media/r0"
    local url = homeserver_url .. ('/upload?access_token=%s')
        :format( urllib.quote(self.access_token))
    local data = {
        url = url,
        method = 'POST',
        data = filedata,
        headers = {
            ['Content-Type'] = content_type,
           -- ['Content-Length'] = tostring(#filedata),
        },
    }
    local js, r_url, response = util.simplehttp(data)
    if not res then
        -- error being logged by simplehttp
        return
    end
    local content_uri = self:http_cb('upload', js, r_url, response)
    if not content_uri then return end
    local body = message or 'image.'..content_type:match('/(.-)$')
    local msgtype = 'm.image'
    local info = {
        -- TODO, width, height, size
        size = #filedata,
        mimetype = content_type,
    }
    self:_msg(room.identifier, body, msgtype, content_uri, info)
end

function MatrixServer:CreateRoom(public, alias, invites)
    local data = {}
    if alias then
        data.room_alias_name = alias
    end
    if public then
        data.visibility = 'public'
    else
        data.visibility = 'private'
    end
    if invites then
        data.invite = invites
    end
    self:http(('/createRoom?access_token=%s')
        :format(urllib.quote(self.access_token)),
        {customrequest = 'POST',
         accept_encoding = 'application/json',
         postfields= json.encode(data),
        }, '/createRoom')
end

function MatrixServer:ListRooms()
    self:http(('/publicRooms?access_token=%s')
        :format(urllib.quote(self.access_token)),
        {
            accept_encoding = 'application/json',
        }, '/publicRooms')
end

function MatrixServer:invite(room_id, user_id)
    local data = {
        user_id = user_id
    }
    self:http(('/rooms/%s/invite?access_token=%s')
        :format(urllib.quote(room_id),
          urllib.quote(self.access_token)),
        {customrequest = 'POST',
         accept_encoding = 'application/json',
         postfields= json.encode(data),
        }, 'invite')
end

function MatrixServer:Nick(displayname)
    local data = {
        displayname = displayname,
    }
    self:http(('/profile/%s/displayname?access_token=%s')
        :format(
          urllib.quote(self.user_id),
          urllib.quote(self.access_token)),
        {customrequest = 'PUT',
         accept_encoding = 'application/json',
         postfields= json.encode(data),
        }, 'profile')
end

function MatrixServer:Events()
    return self.events
end

function MatrixServer:LoadModule(moduleName)
    local moduleFile
    local moduleError
    local endings = {'.lua', '/init.lua', '.moon', '/init.moon'}

    for _, ending in ipairs(endings) do
        local fileName = 'modules/' .. moduleName .. ending
        -- Check if file exist and is readable before we try to loadfile it
        local access = lfs.attributes(fileName)
        if(access) then
            if(fileName:match('.lua')) then
                moduleFile, moduleError = loadfile(fileName)
            elseif(fileName:match('.moon') and moonscript) then
                moduleFile, moduleError = moonscript.loadfile(fileName)
            end
            if(not moduleFile) then
                -- If multiple file matches exist and the first match has an error we still
                -- return here.
                return self:Log('error', 'Unable to load module %s: %s.', moduleName, moduleError)
            end
            break
        end
    end
    if(not moduleFile) then
        moduleError = 'File not found'
        return self:Log('error', 'Unable to load module %s: %s.', moduleName, moduleError)
    end

    local env = {
        ivar2 = self,
        package = package,
    }
    setmetatable(env, {__index = _G })
    setfenv(moduleFile, env)

    local success, message = pcall(moduleFile, self)
    if(not success) then
        self:Log('error', 'Unable to execute module %s: %s.', moduleName, message)
    else
        self:EnableModule(moduleName, message)
    end
end

function MatrixServer:IsIgnored(destination, source)
    if(not destination) then return false end
    if(not source) then return false end
    if(self.ignores[source]) then return true end

    local channel = self.config.channels[destination]
    if(type(channel) == 'table') then
        if tableHasValue(channel.ignoredNicks, source.nick) then
            return true
        end
    end
    if(type(channel) == 'table') then
        if tableHasValue(channel.ignoredNicks, source.mask) then
            return true
        end
    end
end

function MatrixServer:EnableModule(moduleName, moduleTable)
    self:Log('info', 'Loading module %s.', moduleName)
	-- Some modules don't return handlers, for example webservermodules,
	-- or pure timermodules, etc.
	if type(moduleTable) ~= 'table' then
		return
	end

    for command, handlers in next, moduleTable do
        if(not self.events[command]) then self.events[command] = {} end
        self.events[command][moduleName] = handlers
    end
end

function MatrixServer:DisableModule(moduleName)
    if(moduleName == 'core') then return end
    for command, modules in next, self.events do
        if(modules[moduleName]) then
            self:Log('info', 'Disabling module: %s', moduleName)
            modules[moduleName] = nil
            event:ClearModule(moduleName)
        end
    end
end

function MatrixServer:LoadModules()
    if(self.config.modules) then
        for _, moduleName in next, self.config.modules do
            self:LoadModule(moduleName)
        end
    end
end

function MatrixServer:SimpleDispatch(command, argument, source, destination)
    self:Log('debug', '%s %s %s %s', command, argument, source, destination)
	-- Function that dispatches commands in the events table without
	-- splitting arguments and setting up function environment
    local events = self.events
	if(not events[command]) then return end

    for moduleName, moduleTable in next, events[command] do
        if(not self:IsModuleDisabled(moduleName, destination)) then
            for pattern, callback in next, moduleTable do
                local success, message
                if(type(pattern) == 'number' and source) then
                    success, message = pcall(callback, self, source, destination, argument)
                else
                    local channelPattern = self:ChannelCommandPattern(pattern, moduleName, destination)
                    if(argument:match(channelPattern)) then
                        success, message = pcall(callback, self, source, destination, argument)
                    end
                end
                if(not success and message) then
                    self:Log('error', 'Unable to execute handler %s from %s: %s', pattern, moduleName, message)
                end
            end
        end
    end
end

function MatrixServer:DispatchCommand(command, argument, source, destination)
    self:Log('info', '%s %s <%s> %s', command, destination, source.mask, argument)
    if self:IsIgnored(destination, source) then
        return
    end
    local events = self.events
    if(not events[command]) then return end

    for moduleName, moduleTable in next, events[command] do
        if(not self:IsModuleDisabled(moduleName, destination)) then
            for pattern, callback in next, moduleTable do
                local success, message
                if(type(pattern) == 'number' and not source) then
                    success, message = pcall(callback, self, argument)
                elseif(type(pattern) == 'number' and source) then
                    success, message = self:ModuleCall(callback, source, destination, false, argument)
                else
                    local channelPattern = self:ChannelCommandPattern(pattern, moduleName, destination)
                    -- Check command for filters, aka | operator
                    -- Ex: !joke|!translate en no|!gay
                    local cutarg, remainder = self:CommandSplitter(argument)

                    if(cutarg:match(channelPattern)) then
                        if(remainder) then
                            self:Log('debug', 'Splitting command: %s into %s and %s', command, cutarg, remainder)
                        end

                        success, message = self:ModuleCall(callback, source, destination, remainder, cutarg:match(channelPattern))
                    end
                end

                if(not success and message) then
                    self:Log('error', 'Unable to execute handler %s from %s: %s', pattern, moduleName, message)
                end
            end
        end
    end
end

function MatrixServer:CommandSplitter(command)
    local first, remainder

    local pipeStart, pipeEnd = command:match('()%s*|%s*()')
    if(pipeStart and pipeEnd) then
        first = command:sub(0,pipeStart-1)
        remainder = command:sub(pipeEnd)
    else
        first = command
    end

    return first, remainder
end

function MatrixServer:ModuleCall(func, source, destination, remainder, ...)
    -- Create a per-call environment so that concurrent async operations
    -- (e.g., simplehttp) cannot overwrite each other's say/reply closures.
    -- The original module env is remembered once (weak table) and each call
    -- gets a fresh env that indexes into it via __index.
    local origEnv = module_envs[func]
    if not origEnv then
        origEnv = getfenv(func)
        module_envs[func] = origEnv
    end
    local env = setmetatable({}, { __index = origEnv })
    env.say = function(str, ...)
        local output = safeFormat(str, ...)
        if(not remainder) then
            self:Say(destination, source, output)
        else
            local command
            command, remainder = self:CommandSplitter(remainder)
            local newline = command .. " " .. output
            if(remainder) then
                newline = newline .. "|" .. remainder
            end

            self:DispatchCommand('PRIVMSG', newline, source, destination)
        end
    end
    env.reply = function(str, ...)
        self:Reply(destination, source, str, ...)
    end
    setfenv(func, env)
    return pcall(func, self, source, destination, ...)
end

function MatrixServer:IsModuleDisabled(moduleName, destination)
    local channel = self.config.channels[destination]

    if(type(channel) == 'table') then
        return tableHasValue(channel.disabledModules, moduleName)
    end
end

function MatrixServer:ChannelCommandPattern(pattern, moduleName, destination)
    local default = '%%p'
    -- First check for a global pattern
    local npattern = self.config.commandPattern or default
    -- If a channel specific pattern exist, use it instead of the default ^%p
    local channel = self.config.channels[destination]

    if(type(channel) == 'table') then
        npattern = channel.commandPattern or npattern

        -- Check for module override
        if(type(channel.modulePatterns) == 'table') then
            npattern = channel.modulePatterns[moduleName] or npattern
        end
    end

    return (pattern:gsub('%^%%p', '%^'..npattern))
end

-- Let modules register commands
function MatrixServer:RegisterCommand(handlerName, pattern, handler, event)
    local events = self.events
    -- Default event is PRIVMSG
    if(not event) then
        event = 'PRIVMSG'
    end
    local env = {
        ivar2 = self,
        package = package,
    }
    setmetatable(env, {__index = _G })
    setfenv(handler, env)
    self:Log('info', 'Registering new pattern: %s, in command %s.', pattern, handlerName)

    if(not events[event][handlerName]) then
        events[event][handlerName] = {}
    end
    events[event][handlerName][pattern] = handler
end

function MatrixServer:UnregisterCommand(handlerName, pattern, event)
    local events = self.events
    -- Default event is PRIVMSG
    if(not event) then
        event = 'PRIVMSG'
    end
    events[event][handlerName][pattern] = nil
    self:Log('info', 'Clearing command with pattern: %s, in module %s.', pattern, handlerName)
end

function MatrixServer:DestinationLocale(destination)
	-- Get configured language for a destination, can be global or channel
	-- specific. Locale string should be a POSIX locale string, e.g.
	-- nn_NO, nb_NO, en_US,

	-- Modules can then opt into looking for this information and use it
	-- however it wants, for example by switching output language in its
	-- functions to another language than default
	--

	local default = 'en_US'
	local channel = self.config.channels[destination]

	if(type(channel) == 'table') then
		local dconf = channel.locale
		if(dconf) then
			return dconf
		end
	end

	local global = self.config.locale
	if(global) then
		return global
	end

	return default

end

Room.create = function(obj, conn)
    local room = {}
    setmetatable(room, Room)
    room.identifier = obj['room_id']
    room.server = 'matrix'
    room.fullname = nil
    room.conn = conn
    room.member_count = 0
    -- Cache users for presence/nicklist
    room.users = {}
    -- Cache the rooms power levels state
    room.power_levels = {users={}, users_default=0}
    room.visibility = 'public'
    room.join_rule = nil
    room.roomname = nil -- m.room.name
    room.aliases = nil -- aliases
    room.canonical_alias = nil

    -- We might not be a member yet
    local state_events = obj.state or {}
    for _, state in pairs(state_events) do
        if state['type'] == 'm.room.name' then
            local name = state['content']['name']
            if name ~= '' or name ~= json.null then
                room.name = name
                room.shortname = name
                room.fullname = name
            end
        end
    end
    if not room.name then
        for _, state in pairs(state_events) do
            if state['type'] == 'm.room.aliases' then
                local name = state['content']['aliases'][1] or ''
                room.shortname, room.server = name:match('(.+):(.+)')
                room.name = name
                room.fullname = name
            end
        end
    end
    if not room.name then
        room.name = room.identifier
    end
    room.visibility = obj.visibility
    if not obj['visibility'] then
        room.visibility = 'public'
    end

    -- Might be invited to room, check invite state
    local invite_state = obj.invite_state or {}
    for _, event in ipairs(invite_state.events or {}) do
        if event['type'] == 'm.room.name' then
            room.name = event.content.name
            room.roomname = event.content.name
        elseif event['type'] == 'm.room.join_rule' then
            room.join_rule = event.content.join_rule
        elseif event['type'] == 'm.room.member' then
            if event.state_key == conn.user_id then
                room.membership = 'invite'
                room.inviter = event.sender
                conn:Log('info', 'You have been invited to join room %s by %s.', room.identifier, room.inviter)
                room:addNick(room.inviter)
                if conn.config.join_on_invite then
                    conn:Join(room.identifier)
                end
            else
                if event.content and event.content.displayname then
                    room.users[event.sender] = event.content.displayname
                end
                if not room.name or not room.roomname then
                    room.name = room.users[room.inviter] or room.inviter
                    room.roomname = room.users[room.inviter] or room.inviter
                end
            end
        end
    end

    -- We might not be a member yet
    local state_events = obj.state or {}
    for _, state in ipairs(state_events) do
        if state['type'] == 'm.room.aliases' then
            local name = state.content.aliases[1]
            if name then
                room.name, _ = name:match('(.+):(.+)')
            end
        end
    end
    if not room.name then
        room.name = room.identifier
    end
    if not room.server then
        room.server = ''
    end

    room.visibility = obj.visibility
    if not obj['visibility'] then
        room.visibility = 'public'
    end


    return room
end

function Room:SetName(name)
    if not name or name == '' or name == json.null then
        return
    end
    -- override hierarchy
    if self.roomname then
        name = self.roomname
    elseif self.canonical_alias then
        name = self.canonical_alias
        --local short_name, _ = self.canonical_alias:match('(.+):(.+)')
        --if short_name then
        --    name = short_name
        --end
    elseif self.aliases then
        local alias = self.aliases[1]
        if alias then
            local _
            name, _ = alias:match('(.+):(.+)')
        end
    else
        -- NO names. Set dynamic name based on members
        local new = {}
        for id, nick in pairs(self.users) do
            -- Set the name to the other party
            if id ~= self.conn.user_id then
                new[#new+1] = nick
            end
        end
        name = table.concat(new, ',')
    end

    if not name or name == '' or name == json.null then
        return
    end

    if name ~= self.name then
        self.conn:Log('info', 'Updated name: %s to %s', self.name, name)
        self.conn.channels[name] = self.conn.channels[self.name]
        self.conn.channels[self.name] = nil
        self.name = name
    end
end

function Room:Topic(topic)
    self.conn:state(self.identifier, 'm.room.topic', {topic=topic})
end

function Room:Upload(url)
    self.conn:Upload(self.identifier, url)
end

function Room:Msg(msg)
    self.conn:_msg(self.identifier, msg)
end

function Room:emote(msg)
    self.conn:emote(self.identifier, msg)
end

function Room:SendTypingNotice()
    self.conn:SendTypingNotice(self.identifier)
end

function Room:destroy()
end

function Room:addNick(user_id, displayname)
    -- Sanitize displaynames a bit
    if not displayname
        or displayname == json.null
        or displayname == ''
        or displayname:match'%s*' then
        displayname = user_id:match('@(.*):.+')
    end
    if not self.users[user_id] then
        self.member_count = self.member_count + 1
    end

    if self.users[user_id] ~= displayname then
        self.users[user_id] = displayname
    end

    local channel = self.conn.channels[self.name]
    if channel and channel.nicks then
        channel.nicks[displayname] = user_id
    end

    return displayname
end

function Room:ParseMask(user_id)
    if type(user_id) == 'table' then return user_id end
    if type(user_id) == 'nil' then return nil end
    local source = {
        mask = user_id,
        nick = self.users[user_id],
    }
    source.ident, source.host = user_id:match'^@(.-):(.-)$'
    return source
end


function Room:GetNickGroup(user_id)
    -- TODO, cache
    local ngroup = 4
    local nprefix = ' '
    local nprefix_color = ''
    if self:GetPowerLevel(user_id) >= 100 then
        ngroup = 1
        nprefix = '@'
        nprefix_color = 'lightgreen'
    elseif self:GetPowerLevel(user_id) >= 50 then
        ngroup = 2
        nprefix = '+'
        nprefix_color = 'yellow'
    elseif self.conn.presence[user_id] then
        -- User has a presence, put him in group3
        ngroup = 3
    end
    return ngroup, nprefix, nprefix_color
end

function Room:GetPowerLevel(user_id)
    return tonumber(self.power_levels.users[user_id] or self.power_levels.users_default or 0)
end

function Room:ClearTyping()
    for user_id, nick in pairs(self.users) do
        local _, nprefix, nprefix_color = self:GetNickGroup(user_id)
        self:UpdateNick(user_id, 'prefix', nprefix)
        self:UpdateNick(user_id, 'prefix_color', nprefix_color)
    end
end

function Room:UpdatePresence(user_id, presence)
end

function Room:UpdateNick(user_id, key, val)
end

function Room:delNick(id)
    if self.users[id] then
        self.users[id] = nil
        -- TODO remove nick
        local channel = self.conn.channels[self.name]
        return true
    end

end

-- Parses a chunk of json meant for a room
function Room:ParseChunk(chunk, backlog, chunktype)
    if not backlog then
        backlog = false
    end

    local is_self = false

    local myself = self.conn.user_id

    -- Sender of chunk, used to be chunk.user_id, v2 uses chunk.sender
    local sender = chunk.sender or chunk.user_id
    -- Check if own message
    if sender == self.conn.user_id then
        is_self = true
    end

    local source = self:ParseMask(sender)

    if chunk['type'] == 'm.room.message' then
        local time_int = chunk['origin_server_ts']/1000
        local body
        local content = chunk['content']
        local nick = self.users[sender] or self:addNick(sender)
        if not content['msgtype'] then
            -- We don't support redactions
            return
        end
        if content['msgtype'] == 'm.text' then
            body = content['body']
            -- TODO
            -- Parse HTML here:
            -- content.format = 'org.matrix.custom.html'
            -- fontent.formatted_body...
            if not backlog and not is_self then
                self.conn:DispatchCommand('PRIVMSG', body, source, self.name)
            end
        elseif content['msgtype'] == 'm.image' then
            --local url = content['url']:gsub('mxc://',
            --    self.conn.url
            --    .. '_matrix/media/v1/download/')
            --body = content['body'] .. ' ' .. url
            body = ''
        elseif content['msgtype'] == 'm.notice' then
            body = content['body']
        elseif content['msgtype'] == 'm.emote' then
        else
            body = content['body']
            print 'Uknown content type'
            print(content)
        end
        --w.print_date_tags(self.buffer, time_int, tags(), data)
    elseif chunk['type'] == 'm.room.topic' then
        local title = chunk['content']['topic']
        if not title then
            title = ''
        end
        local nick = self.users[sender] or sender
    elseif chunk['type'] == 'm.room.name' then
        local name = chunk['content']['name']
        if name ~= '' or name ~= json.null then
            self.roomname = name
            self:SetName(name)
        end
    elseif chunk['type'] == 'm.room.member' then
        if chunk['content']['membership'] == 'join' then
            local nick = self:addNick(sender, chunk.content.displayname)
            local time_int = chunk['origin_server_ts']/1000
            -- Check if the chunk has prev_content or not
            -- if there is prev_content there wasn't a join but a nick change
            if chunk.prev_content
                    and chunk.prev_content.membership == 'join' then
                local oldnick = chunk.prev_content.displayname
                if oldnick == json.null then
                    oldnick = ''
                else
                    if oldnick == nick then
                        -- Maybe they changed their avatar or something else
                        -- that we don't care about
                        return
                    end
                    self:delNick(oldnick)
                end
                if chunktype == 'messages' then
                    --w.print_date_tags(self.buffer, time_int, tags(), data)
                end
            else
                if chunktype == 'messages' then
                    -- w.print_date_tags(self.buffer, time_int, tags(), data)
                end
            end
        elseif chunk['content']['membership'] == 'leave' then
            local nick = sender
            local prev = chunk['prev_content']
            if (prev and
                    prev.displayname and
                    prev.displayname ~= json.null) then
                nick = prev.displayname
            end
            if not backlog then
                self:delNick(nick)
            end
            if chunktype == 'messages' then
                if chunk.state_key == myself then
                    self.conn:DispatchCommand('KICK', 'Kicked '..tostring(myself), source, self.name)
                end
                --w.print_date_tags(self.buffer, time_int, tags(), data)
            end
        elseif chunk['content']['membership'] == 'invite' then
            if chunk.state_key == myself and
                (not backlog and chunktype=='messages') then
                if self.conn.config.join_on_invite then
                    self.conn:Join(self.identifier)
                end
            end
        end
    elseif chunk['type'] == 'm.room.create' then
        -- TODO: parse create events --
        --dbg({event='m.room.create',chunk=chunk})
    elseif chunk['type'] == 'm.room.power_levels' then
        for user_id, lvl in pairs(chunk.content.users) do
            -- TODO
            -- calculate changes here and generate message lines
            -- describing the change
        end
        self.power_levels = chunk.content
        for user_id, lvl in pairs(self.power_levels.users) do
            local _, nprefix, nprefix_color = self:GetNickGroup(user_id)
            self:UpdateNick(user_id, 'prefix', nprefix)
            self:UpdateNick(user_id, 'prefix_color', nprefix_color)
        end
    elseif chunk['type'] == 'm.room.join_rules' then
        -- TODO: parse join_rules events --
        self.join_rules = chunk.content
    elseif chunk['type'] == 'm.typing' then
        for _, id in pairs(chunk.content.user_ids) do
            self:UpdatePresence(id, 'typing')
        end
    elseif chunk['type'] == 'm.presence' then
    elseif chunk['type'] == 'm.room.aliases' then
        -- Use first alias, weechat doesn't really support multiple  aliases
        self.aliases = chunk.content.aliases
        self:SetName(chunk.content.aliases[1])
    elseif chunk['type'] == 'm.room.canonical_alias' then
        self.canonical_alias = chunk.content.alias
        self:SetName(self.canonical_alias)
    elseif chunk['type'] == 'm.receipt' then -- ignore
    else
        self.conn:Log('warn', 'unknown chunk of type: '..tostring(chunk['type']))
    end
end

function Room:Op(nick)
    for id, name in pairs(self.users) do
        if name == nick then
            -- patch the locally cached power levels
            self.power_levels.users[id] = 100
            self.conn:state(self.identifier, 'm.room.power_levels',
                self.power_levels)
            break
        end
    end
end

function Room:Voice(nick)
    for id, name in pairs(self.users) do
        if name == nick then
            -- patch the locally cached power levels
            self.power_levels.users[id] = 50
            self.conn:state(self.identifier, 'm.room.power_levels',
                self.power_levels)
            break
        end
    end
end

function Room:Devoice(nick)
    for id, name in pairs(self.users) do
        if name == nick then
            -- patch the locally cached power levels
            self.power_levels.users[id] = 0
            self.conn:state(self.identifier, 'm.room.power_levels',
                self.power_levels)
            break
        end
    end
end

function Room:Deop(nick)
    for id, name in pairs(self.users) do
        if name == nick then
            -- patch the locally cached power levels
            self.power_levels.users[id] = 0
            self.conn:state(self.identifier, 'm.room.power_levels',
                self.power_levels)
            break
        end
    end
end

function Room:Kick(nick, reason)
    for id, name in pairs(self.users) do
        if name == nick then
            local data = {
                membership = 'leave',
                reason = 'Kicked by '..self.conn.user_id
            }
            self.conn:set_membership(self.identifier, id, data)
            break
        end
    end
end

function Room:invite(id)
    self.conn:invite(self.identifier, id)
end

if reload then
    -- TODO implement conf/code reload
end

-- Attempt to create the cache folder.
lfs.mkdir('cache')

-- Load config and start the bot
if configFile then
    ivar2 = MatrixServer.create()
    queue:wrap(function()
        local ok, config = pcall(loadfile(configFile))
        if not ok then
            io.stderr:write("Unable to load config "..tostring(configFile)..'\n')
            os.exit(1)
        end
        -- Store the config file name in the config so it can be accessed later
        config.configFile = configFile
        ivar2:connect(config)
    end)
    while true do
        -- luacheck: ignore obj fd
        local ok, err, ctx, ecode, thread, obj, fd = queue:step()
        if not ok then
            ivar2:Log('error', 'Error in main loop: %s, %s, %s', err, ctx, ecode)
            ivar2:Log('error', debug.traceback(thread, err))
        end
    end
else
    MatrixServer:Log('error', 'No config file specified')
end
