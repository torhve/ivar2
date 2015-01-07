============================
ivar2 - DO-OH!
============================

Introduction
------------
ivar2 is an irc-bot on speed, with a mentally unstable mind.
Partially because its written in lua, which could make the most sane mind go unstable.

Installation
------------------

Either use the provided Dockerfile in scripts/Dockerfile or follow its command list to install all the required dependencies.

Build the Dockerfile:

::

    cd scripts
    docker build -t torhve/ivar2 .


Or install manually:

::

    sudo apt-get install luarocks libev-dev liblua5.1-iconv0 lua-cjson cmake
    sudo luarocks install "https://github.com/brimworks/lua-ev/raw/master/rockspec/lua-ev-scm-1.rockspec"
    sudo luarocks install "https://github.com/Neopallium/nixio/raw/master/nixio-scm-0.rockspec"
    sudo luarocks install "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-scm-0.rockspec"
    sudo luarocks install "https://github.com/brimworks/lua-http-parser/raw/master/lua-http-parser-scm-0.rockspec"
    sudo luarocks install "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-http-scm-0.rockspec"
    sudo luarocks install lsqlite3
    sudo luarocks install luasocket
    sudo luarocks install luabitop


Uncompress the required data files in cache directory.

Configuration File
------------------

Create a bot config sort of like this

**myconfig.lua**

::

    return {
        nick = 'ivar2',
        autoReconnect = true,
        ident = 'ivar2',
        uri = 'tcp://irc.efnet.no:6667/',
        realname = 'ivar',
        owners = {
            'nick!ident@my.host.name'
        },
        commandPattern = "!",
        modules = {
            'admin',
            'autojoin',
            'lastfm',
            'spotify',
            'karma',
            'roll',
            'title',
            'tvrage',
            'urbandict',
            'substitute',
            'lua',
        },
        channels = {
            ['#ivar'] = {
                disabledModules = {
                    'olds'
               },
               commandPattern = '>',
               ignoredNicks = {'otherbot'},
               modulePatterns = {
                    lastfm = '#',
               },
            },
        }
    }



Launch bot
----------

::

    lua ivar2.lua myconfig.lua

or using Docker

::

    sudo docker run -i -t -v=/home/ivar2:/ivar2 -w=/ivar2 torhve/ivar2 lua ivar2.lua myconfig.lua


Modules
-------

THERES TONS!
