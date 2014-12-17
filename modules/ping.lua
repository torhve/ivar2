local os = require 'os'
return {
    PRIVMSG = { 
        ['^%pping$'] = function(self, source, destination, input)
            say('pong! %s', os.date('%Y-%m-%d %H:%M:%S'))
        end,
    },
}

