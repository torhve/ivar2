local M = {}
local cqueues = require 'cqueues'

local irc_to_ansi_fg = {
    255, 0, 21, 2, 1, 52, 53, 166, 3, 48, 51, 50, 117, 206, 245, 252,
}

local irc_to_ansi_bg = {
    234, 16, 17, 22, 1, 53, 54, 178, 225, 34, 30, 31, 33, 198, 237, 255,
}

function M.irc_to_ansi(s)
    local out = {}
    local buf = {}
    local i = 1
    while i <= #s do
        local c = s:byte(i)
        if c == 3 then
            table.insert(out, table.concat(buf))
            buf = {}
            local digit = ''
            i = i + 1
            while i <= #s and s:byte(i) >= 48 and s:byte(i) <= 57 do
                digit = digit .. s:sub(i, i)
                i = i + 1
            end
            local fg = tonumber(digit) or 0
            if s:sub(i, i) == ',' then
                i = i + 1
                local bgd = ''
                while i <= #s and s:byte(i) >= 48 and s:byte(i) <= 57 do
                    bgd = bgd .. s:sub(i, i)
                    i = i + 1
                end
                local bg = tonumber(bgd) or 0
                table.insert(out, string.format('\27[38;5;%d;48;5;%dm', irc_to_ansi_fg[fg + 1], irc_to_ansi_bg[bg + 1]))
            else
                table.insert(out, string.format('\27[38;5;%dm', irc_to_ansi_fg[fg + 1]))
            end
        elseif c == 2 then
            table.insert(out, table.concat(buf))
            buf = {}
            table.insert(out, '\27[1m')
            i = i + 1
        elseif c == 31 then
            table.insert(out, table.concat(buf))
            buf = {}
            table.insert(out, '\27[4m')
            i = i + 1
        elseif c == 29 then
            table.insert(out, table.concat(buf))
            buf = {}
            table.insert(out, '\27[3m')
            i = i + 1
        elseif c == 18 then
            table.insert(out, table.concat(buf))
            buf = {}
            table.insert(out, '\27[7m')
            i = i + 1
        elseif c == 15 then
            table.insert(out, table.concat(buf))
            buf = {}
            table.insert(out, '\27[0m')
            i = i + 1
        else
            table.insert(buf, s:sub(i, i))
            i = i + 1
        end
    end
    table.insert(out, table.concat(buf))
    return table.concat(out)
end

function M.load_config(path)
    return dofile(path)
end

function M.mock_ivar2(opts)
    opts = opts or {}
    local util = require 'util'
    local mock = {
        config = { prefix = '!', nick = 'bot' },
        persist = {
            get = function() return nil end,
            set = function() end,
            delete = function() end,
            clear = function() end,
        },
        util = util,
        channels = {},
        Msg = function() end,
        Say = function() end,
        Reply = function() end,
    }
    for k, v in pairs(opts) do
        if type(v) == 'table' and type(mock[k]) == 'table' then
            for tk, tv in pairs(v) do mock[k][tk] = tv end
        else
            mock[k] = v
        end
    end
    return mock
end

function M.load_module(name, mock)
    mock = mock or M.mock_ivar2()
    local endings = { '.lua', '/init.lua', '.moon', '/init.moon' }

    local loader
    for _, ending in ipairs(endings) do
        local filepath = 'modules/' .. name .. ending
        local f = io.open(filepath)
        if f then
            f:close()
            if ending:match('.lua') then
                loader = loadfile(filepath)
            elseif ending:match('.moon') then
                local moonloader = require 'moonloader'
                loader = moonloader.load(filepath)
            end
            if loader then break end
        end
    end

    if not loader then error('Module not found: ' .. name) end

    local env = { ivar2 = mock, package = package }
    setmetatable(env, { __index = _G })
    setfenv(loader, env)
    return loader()
end

function M.capture_env(mock)
    local captures = { say = {}, reply = {}, network = {} }
    local env = setmetatable({}, { __index = _G })
    env.ivar2 = mock
    env.say = function(str, ...)
        table.insert(captures.say, select('#', ...) > 0 and string.format(str, ...) or str)
    end
    env.reply = function(str, ...)
        table.insert(captures.reply, select('#', ...) > 0 and string.format(str, ...) or str)
    end
    captures.env = env
    return captures
end

function M.run_loop(cq, timeout)
    local ok, err, _, thd = cq:loop(timeout)
    if not ok then
        if thd then err = debug.traceback(thd, err) end
        error(err, 2)
    end
end

function M.setup(module_name, config_path)
    local config
    if config_path then
        config = M.load_config(config_path)
    end
    local mock = M.mock_ivar2(config and { config = config } or nil)
    return M.context(module_name, mock)
end

function M.context(module_name, mock)
    local mod = M.load_module(module_name, mock)
    local cq = cqueues.new()
    return {
        mock = mock,
        mod = mod,
        queue = cq,
        invoke = function(self, message, opts)
            opts = opts or {}
            local prefix = self.mock.config.prefix or '!'
            local captures = M.capture_env(self.mock)
            setfenv(function() end, captures.env)

            local handlers = self.mod.PRIVMSG or {}
            local matched = 0
            for pattern, handler in pairs(handlers) do
                local key = pattern:gsub('%%p', prefix)
                if message:match(key) then
                    local callEnv = setmetatable({}, { __index = captures.env })
                    callEnv.say = captures.env.say
                    callEnv.reply = captures.env.reply
                    setfenv(handler, callEnv)
                    local captured = message:match(key)
                    handler(self.mock,
                        opts.source or { nick = 'tester', mask = 'tester!u@host' },
                        opts.dest or '#test',
                        captured or '')
                    matched = matched + 1
                end
            end

            if opts.timeout then
                M.run_loop(self.queue, opts.timeout)
            end
            return captures
        end,
    }
end

return M