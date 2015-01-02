-- ivar2 IRC module
-- vim: set noexpandtab:

local function parse(line)
    local source, command, destination, argument
    if(line:sub(1, 1) ~= ':') then
        command, argument = line:match'^(%S+) :(.*)'
        if(command) then
            return command, argument, 'server'
        end
    elseif(line:sub(1, 1) == ':') then
        if(not source) then
            -- Parse 352 /who
            local tsource, tcommand, sourcenick, tdestination, user, host, server, nick, mode, hopcount, realname = line:match('^:(%S+) (%d%d%d) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (.-)$')
            if(tsource and tcommand == '352') then
                local argument = {}
                argument.mode = mode
                argument.user = user
                argument.server = server
                argument.nick = nick
                argument.hopcount = hopcount
                argument.realname = realname
                -- Return here. This command does not need further
                -- parsing or checking for ignore.
                return tcommand, argument, tsource, tdestination
            end
        end
        if(not source) then
            -- :<server> 000 <nick> <destination> :<argument>
            source, command, destination, argument = line:match('^:(%S+) (%d%d%d) %S+ ([^%d]+[^:]+) :(.*)')
        end
        if(not source) then
            -- :<server> 000 <nick> <int> :<argument>
            source, command, argument = line:match('^:(%S+) (%d%d%d) [^:]+ (%d+ :.+)')
            if(source) then argument = argument:gsub(':', '', 1) end
        end
        if(not source) then
            -- :<server> 000 <nick> <argument> :<argument>
            source, command, argument = line:match('^:(%S+) (%d%d%d) %S+ (.+) :.+$')
        end
        if(not source) then
            -- :<server> 000 <nick> :<argument>
            source, command, argument = line:match('^:(%S+) (%d%d%d) [^:]+ :(.*)')
        end
        if(not source) then
            -- :<server> 000 <nick> <argument>
            source, command, argument = line:match('^:(%S+) (%d%d%d) %S+ (.*)')
        end
        if(not source) then
            -- :<server> <command> <destination> :<argument>
            source, command, destination, argument = line:match('^:(%S+) (%u+) ([^:]+) :(.*)')
        end
        if(not source) then
            -- :<source> <command> <destination> <argument>
            source, command, destination, argument = line:match('^:(%S+) (%u+) (%S+) (.*)')
        end
        if(not source) then
            -- :<source> <command> :<destination>
            source, command, destination = line:match('^:(%S+) (%u+) :(.*)')
        end
        if(not source) then
            -- :<source> <command> <destination>
            source, command, destination = line:match('^:(%S+) (%u+) (.*)')
        end
        return command, argument, source, destination
    end
end

return {
    parse=parse,
}
