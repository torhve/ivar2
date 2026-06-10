package.path = table.concat({
    'libs/?.lua',
    'libs/?/init.lua',
    'spec/?.lua',
    '',
}, ';') .. package.path

package.cpath = table.concat({
    'libs/?.so',
    '',
}, ';') .. package.cpath

local cqueues = require 'cqueues'

local helper = require 'module_helper'

local function usage()
    print([[
Usage: lua tools/test_module.lua <module> <message> [options]

  <module>   Module name (e.g. stonks, ping, karma)
  <message>  Full IRC command string (e.g. "!q NVDA", "!stonks")

Options:
  --config <path>   Config file (default: config/ivartest.lua)
  --timeout <sec>   cqueues loop timeout for async (default: 0 = sync only)
  --dest <channel>  Destination channel (default: #test)
  --nick <nick>     Source nick (default: tester)
  --list            List module patterns without invoking]])
    os.exit(1)
end

local args = {}
local opts = {
    config = 'config/ivartest.lua',
    timeout = 0,
    dest = '#test',
    nick = 'tester',
    list = false,
}

for i = 1, #arg do
    local a = arg[i]
    if a == '--config' and arg[i+1] then
        opts.config = arg[i+1]; i = i + 1
    elseif a == '--timeout' and arg[i+1] then
        opts.timeout = tonumber(arg[i+1]); i = i + 1
    elseif a == '--dest' and arg[i+1] then
        opts.dest = arg[i+1]; i = i + 1
    elseif a == '--nick' and arg[i+1] then
        opts.nick = arg[i+1]; i = i + 1
    elseif a == '--list' then
        opts.list = true
    elseif a:sub(1, 2) == '--' then
        print('Unknown option: ' .. a)
        usage()
    else
        table.insert(args, a)
    end
end

if #args < 1 then
    usage()
end

local module_name = args[1]
local message = args[2]

local config = helper.load_config(opts.config)
local mock = helper.mock_ivar2({ config = config })
local mod = helper.load_module(module_name, mock)

local handlers = mod.PRIVMSG or {}

if opts.list then
    local prefix = mock.config.prefix or '!'
    print('Module: ' .. module_name)
    print('Event: PRIVMSG')
    print('Patterns:')
    for pattern, _ in pairs(handlers) do
        local key = pattern:gsub('%%p', prefix)
        print('  ' .. key)
    end
    os.exit(0)
end

if not message then
    print('No message provided. Use --list to see available patterns.')
    os.exit(1)
end

local prefix = mock.config.prefix or '!'
local captures = helper.capture_env(mock)
local matched = 0

for pattern, handler in pairs(handlers) do
    local key = pattern:gsub('%%p', prefix)
    if message:match(key) then
        local callEnv = setmetatable({}, { __index = captures.env })
        callEnv.say = captures.env.say
        callEnv.reply = captures.env.reply
        setfenv(handler, callEnv)
        local captured = message:match(key)
        print('Handler: ' .. pattern .. ' (matched as: ' .. key .. ')')
        print('Captured: ' .. tostring(captured or ''))

        handler(mock,
            { nick = opts.nick, mask = opts.nick .. '!u@host' },
            opts.dest,
            captured or '')
        matched = matched + 1
    end
end

if matched == 0 then
    print('No matching handler for: ' .. message)
    os.exit(1)
end

if opts.timeout > 0 then
    local cq = cqueues.new()
    helper.run_loop(cq, opts.timeout)
end

print('')
print('--- Output ---')
if #captures.say > 0 then
    for i, msg in ipairs(captures.say) do
        print('say[' .. i .. ']: ' .. helper.irc_to_ansi(msg))
    end
else
    print('say: (none)')
end

if #captures.reply > 0 then
    for i, msg in ipairs(captures.reply) do
        print('reply[' .. i .. ']: ' .. helper.irc_to_ansi(msg))
    end
else
    print('reply: (none)')
end