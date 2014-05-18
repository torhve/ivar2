============================
ivar2 - DO-OH!
============================

Introduction
------------
ivar2 is an irc-bot on speed, with a mentally unstable mind.
Partially because its written in lua, which could make the most sane mind go unstable.

Installation
------------------

Install required dependencies

::

    sudo apt-get install luarocks libev-dev liblua5.1-logging liblua5.1-iconv0 liblua5.1-json cmake
    sudo luarocks install "https://github.com/brimworks/lua-ev/raw/master/rockspec/lua-ev-scm-1.rockspec"
    sudo luarocks install "https://github.com/Neopallium/nixio/raw/master/nixio-scm-0.rockspec"
    sudo luarocks install "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-scm-0.rockspec"
    sudo luarocks install "https://github.com/brimworks/lua-http-parser/raw/master/lua-http-parser-scm-0.rockspec"
    sudo luarocks install "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-http-scm-0.rockspec"
    sudo luarocks install "https://raw.githubusercontent.com/Neopallium/lua-handlers/master/lua-handler-http-scm-0.rockspec"
    sudo luarocks install lsqlite3
    sudo luarocks install luasocket
    sudo luarocks install luabitop
    wget https://github.com/haste/lua-idn/raw/master/idn.lua

Configuration File
------------------

Create a bot config sort of like this

**myconfig.lua**

::

    return {
        nick = 'ivar2,
        autoReconnect = true,
        ident = 'ivar2',
        uri = 'tcp://irc.efnet.no:6667/?laddr=my.host.name&lport=0',
        port = 6667,
        realname = 'ivar',
        owners = {
            'nick!ident@my.host.name'
        },
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
            },
        }
    }



Launch bot
----------

::

    lua ivar2.lua myconfig.lua

Modules
-------

THERES TONS!
