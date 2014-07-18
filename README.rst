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
