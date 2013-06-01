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

sudo apt-get install luarocks libev-dev liblua5.1-logging liblua5.1-iconv0 liblua5.1-json cmake
sudo luarocks install "https://github.com/brimworks/lua-ev/raw/master/rockspec/lua-ev-scm-1.rockspec"
sudo luarocks install "https://github.com/Neopallium/nixio/raw/master/nixio-scm-0.rockspec"
sudo luarocks install "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-scm-0.rockspec"
sudo luarocks install "https://github.com/brimworks/lua-http-parser/raw/master/lua-http-parser-scm-0.rockspec"
sudo luarocks install "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-http-scm-0.rockspec"
sudo luarocks install lsqlite3
wget https://github.com/haste/lua-idn/raw/master/idn.lua

Configuration File
------------------

Create a bot launcher
vim bot.lua


Modules
-------

THERES TONS!

Version History
---------------
Wha-at?
