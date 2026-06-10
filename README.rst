============================
ivar2 - DO-OH!
============================

Introduction
------------
ivar2 is an IRC/Matrix bot on speed, with a mentally unstable mind.
Partially because its written in Lua, which could make the most sane mind go unstable.
If that's not obscure enough for you, ivar2 also supports running `MoonScript <http://moonscript.org/>`_ modules.

Installation
------------------

The installation instructions are made for Debian Jessie, you might have to adapt yourself for other distributions. Some additional dependencies are required for some of the modules, like PostgreSQL for pgolds.lua. Persisting data can be done using either sqlite og Redis, naturally lua-redis and redis-server is required as a dependency if you want to use redis.

Instructions for containing Lua and all deps inside a single directory, almost like python virtualenv or npm.:

::

    # Install ``hererocks`` <https://github.com/mpeterv/hererocks/>, using pip or wget https://raw.githubusercontent.com/mpeterv/hererocks/latest/hererocks.py
    pip install hererocks
    # Install lua + deps in a directory called ivarenv
    hererocks -j 2.1 -r\^ ivarenv
    # Change dir to ivarenv
    cd ivarenv
    # Run Luarocks from ivarenv
    bin/luarocks install http
    bin/luarocks install lua-cjson
    bin/luarocks install lua-zlib
    bin/luarocks install lua-iconv
    bin/luarocks install luafilesystem
    bin/luarocks install lsqlite3
    bin/luarocks install luaexif # Requires libexif-dev
    # Optional
    bin/luarocks install --server=http://luarocks.org/dev cqueues-pgsql  PQ_INCDIR=/usr/include/postgresql # requires libpq-dev system package

    # Optional
    bin/luarocks install --server=http://luarocks.org/dev lredis


    # Now you have a self contained Lua environment with deps that you can run the bot.
    cd ivar2
    ivarenv/bin/lua ivar2.lua myconfig.lua


Alternate instructions for install Lua(JIT) + deps, trying to use some system packages:

::

    sudo apt-get install luarocks liblua5.1-iconv0 lua-zlib lua-cjson cmake libsqlite3-dev git libssl-dev m4 libexif-dev
    sudo luarocks install lsqlite3
    sudo luarocks install luabitop
    sudo luarocks install luarocks #newer version of luarocks to support git+https
    sudo luarocks install http
    sudo luarocks install luafilesystem
    sudo luarocks install feedparser
    # if you want to use LuaJIT instead of Lua
    sudo apt-get install luajit
    # if you want postgresql support
    sudo luarocks install --server=http://luarocks.org/dev cqueues-pgsql  PQ_INCDIR=/usr/include/postgresql # requires libpq-dev system package
    # if you want redis persist
    sudo luarocks install --server=http://luarocks.org/dev lredis
    sudo apt-get install redis-server


Decompress the required data files in cache directory.

Configuration File
------------------

Create a bot config sort of like this

**myconfig.lua**

.. code:: lua

    return {
        nick = 'ivar2',
        autoReconnect = true,
        ident = 'ivar2',
        uri = 'tcp://irc.efnet.no:6667/',
        password = false,
        realname = 'ivar',
        owners = {
            'nick!ident@my.host.name'
        },
        webserverhost = '::',
        webserverport = 9000,
        webserverprefix = 'https://my.web.proxy/', -- optional URL if bot is behind proxy
        commandPattern = "!",
        notice = false, -- Reply with PRIVMSG instead of NOTICE
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

    # Using Lua
    lua ivar2.lua myconfig.lua
    # Using LuaJIT (apt-get install luajit)
    luajit ivar2.lua myconfig.lua
    # If you want to try the Matrix adapter
    lua(jit) matrix.lua yourmatrixconfigfile.lua

    # Or install the provided systemd service
    sudo cp scripts/ivar2.service /etc/systemd/system/ivar2.service
    sudo systemctl daemon-reload
    sudo systemctl start ivar2



Modules
-------

So. Many. Useless. Modules!
And they are written in either Lua or MoonScript.

Writing modules
---------------

Example module that fetches some content over HTTP, parses JSON and returns some text when triggered:


.. code:: lua

    -- Util lib contains lots of helpful stuff for modules, like HTTP, JSON,
    -- IRC formatting, some utf8-helpers, etc.
    local util = require'util'
    local http = util.simplehttp
    local json = util.json

    -- Define function that will be ran when triggered by user input
    local handler = function(self, source, destination, input)
      -- self is ivar2 object, with all its methods
      -- source is table, containing sender info, like source.nick
      -- destination is string with target of the message, i.e. the channel the message was sent to
      -- input is optional Lua pattern capture match

      -- Fetch HTTP content and JSON decode it. No error handling needed here
      -- unless you want to inform the user of errors with HTTP or JSON etc.
      -- All module functions are called with pcall (protected call) to prevent
      -- crashes. Errors will result in error lines in the log.
      local result = json.decode((http'http://api.icndb.com/jokes/random'))

      -- Send the reply back to the destination where it came from using ivar2
      -- Privmsg function. You could also use say() or reply() available in this
      -- function environment as helpers
      self:Privmsg(destination, result.value.joke)
    end

    -- Modules returns a table with events, and Lua pattern with a corresponding
    -- function that will be called when the event text matches the pattern.
    return {
      -- PRIVMSG means incoming IRC message, from channel or query
      PRIVMSG = {
        ['!chuck'] = handler,
      },
    }


Example of module that is responding to HTTP:

.. code:: lua

    ivar2.webserver.regUrl('/test/html/(.*)', function(self, req, res)
       self:Log('error', 'testtestest')
       local channel = req.url:match('channel=(.+)%s*')
       local unescaped_channel = channel:gsub('%%23', '#')
       self:Privmsg(unescaped_channel, 'test')
       return [[
       <html>
           <head>
               <title> ivartest </title>
           </head>
           <body>
               <h1>
                   Test
               </h1>
           </body>
       </html>
       ]]
     end)

     ivar2.webserver.regUrl('/test/plain/(.*)', function(self, req, res)
        self:Log('error', 'testtestest')
        return 'ok', 200, {
          ['Content-Type'] = 'text/plain'
        }
      end)

Testing
-------

ivar2 provides a testing framework for unit-testing modules without running
the full bot. Two approaches are available: a CLI tool for quick ad-hoc
testing, and busted integration for repeatable test suites.

CLI Quick Test
~~~~~~~~~~~~~~

Test a module interactively by passing an IRC-like message string::

    # Sync module
    lua tools/test_module.lua ping '!ping'

    # Async module (requires --timeout for cqueues event loop)
    lua tools/test_module.lua stonks '!q NVDA' --timeout 5

    # List all patterns a module responds to
    lua tools/test_module.lua stonks --list

Options:

    --config <path>   Config file (default: config/ivartest.lua)
    --timeout <sec>   cqueues loop timeout for async modules (default: 0)
    --dest <channel>  Destination channel (default: #test)
    --nick <nick>     Source nick (default: tester)
    --list            List module patterns without invoking

Module Test Files
~~~~~~~~~~~~~~~~~

Write repeatable tests in ``spec/modules/<name>.lua`` (one file per module,
no ``_spec`` suffix). Use ``helper.setup()`` to create a context, then
``ctx:invoke()`` to fire handlers and capture output::

    local busted = require 'busted'
    local describe = busted.describe
    local it = busted.it
    local helper = require 'module_helper'

    describe('my module', function()
        local ctx = helper.setup('mymodule', 'config/ivartest.lua')

        it('responds to !cmd', function()
            local captures = ctx:invoke('!cmd arg')
            assert.is_true(#captures.say > 0)
        end)

        it('async handler with timeout', function()
            local captures = ctx:invoke('!async', { timeout = 5 })
            assert.is_true(#captures.say > 0)
        end)
    end)

Helper Reference
~~~~~~~~~~~~~~~~

Functions available in ``spec/module_helper.lua``:

    helper.setup(module_name, config_path)  -- returns context object
    ctx:invoke(message, opts)               -- invokes matching handlers
    helper.capture_env(mock)                -- low-level say/reply capture
    helper.irc_to_ansi(s)                   -- converts IRC codes to ANSI 256-color

The context object exposes:

    ctx.mock        -- the ivar2 mock object
    ctx.mod         -- loaded module table
    ctx.queue       -- cqueues event loop

The ``invoke()`` function returns a captures table with ``say[]`` and
``reply[]`` arrays. For async modules, pass ``{ timeout = N }`` to wait
for pending operations.

Running Tests
~~~~~~~~~~~~~

    # Full test suite
    busted

    # Single module test
    busted spec/modules/stonks.lua