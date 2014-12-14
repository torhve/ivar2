# Dockerfile for ivar2
# VERSION   0.0.1

FROM ubuntu:14.04
MAINTAINER Tor Hveem <tor@hveem.no>
ENV REFRESHED_AT 2014-06-16

RUN    echo "deb-src http://archive.ubuntu.com/ubuntu trusty main" >> /etc/apt/sources.list
RUN    sed 's/main$/main universe/' -i /etc/apt/sources.list
RUN    apt-get update
RUN    apt-get upgrade -y
RUN    apt-get -y install gcc make
RUN    apt-get -y install libsqlite3-dev
RUN    apt-get -y install libssl-dev
RUN    apt-get -y install libev-dev
RUN    apt-get -y install luajit
RUN    apt-get -y install luarocks
RUN    apt-get -y install lua-sec
RUN    apt-get -y install lua-cjson
RUN    apt-get -y install lua-logging
RUN    apt-get -y install lua-iconv
RUN    apt-get -y install lua-dbi-postgresql
RUN    apt-get -y install redis-server
RUN    apt-get -y install git
RUN    apt-get -y install cmake

RUN    luarocks install --server=http://rocks.moonscript.org moonscript 
RUN    luarocks install --server=http://rocks.moonscript.org date
RUN    luarocks install --server=http://rocks.moonscript.org lsqlite3
RUN    luarocks install --server=http://rocks.moonscript.org luabitop
RUN    luarocks install --server=http://rocks.moonscript.org redis-lua
RUN    luarocks install "https://github.com/brimworks/lua-ev/raw/master/rockspec/lua-ev-scm-1.rockspec" LIBEV_INCDIR=/usr/include/ LIBEV_LIBDIR=/usr/lib/x86_64-linux-gnu/
RUN    luarocks install "http://github.com/Neopallium/nixio/raw/master/nixio-scm-0.rockspec"
RUN    luarocks install "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-scm-0.rockspec"
RUN    luarocks install "https://github.com/brimworks/lua-http-parser/raw/master/lua-http-parser-scm-0.rockspec"
RUN    luarocks install "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-http-scm-0.rockspec"

