local simplehttp = require'simplehttp'
local json = require'cjson'
local html2unicode = require'html'
local base64 = require 'base64'
local sql = require'lsqlite3'

local access_token
local key = ivar2.config.twitterApiKey
local secret = ivar2.config.twitterApiSecret

if(not ivar2.timers) then ivar2.timers = {} end

local function openDb()
    -- Create a new DB if non existant using the current network in the file path
    local dbfilename = string.format("cache/twitter.%s.db", ivar2.network)
    local db = sql.open(dbfilename)
    db:exec([[
        CREATE TABLE IF NOT EXISTS twitter (
            screen_name text,
            destination text,
            UNIQUE (screen_name, destination) ON CONFLICT REPLACE
        );
    ]])
    db:exec([[
        CREATE TABLE IF NOT EXISTS last (
            screen_name text UNIQUE,
            since_id text
        );
    ]])
    return db
end

local function outputTweet(say, source, destination, info)
    local name = info.user.name
    local screen_name = html2unicode(info.user.screen_name)
    local tweet
    if info.retweeted_status then
        local rter = info.retweeted_status.user.screen_name
        tweet = 'RT @'..rter..': '..html2unicode(info.retweeted_status.text)
    else
        tweet = html2unicode(info.text)
    end
    
    -- replace newlines with spaces
    tweet = tweet:gsub('\n', ' ')

    local out = {}
    if(name == screen_name) then
        table.insert(out, string.format('\002%s\002:', name))
    else
        table.insert(out, string.format('\002%s\002 @%s:', name, screen_name))
    end

    table.insert(out, tweet)
    if(say ~= nil) then
        say(table.concat(out, ' '))
    else
        ivar2:Msg('privmsg', destination, source, table.concat(out, ' '))
    end
end

local function getStatus(say, source, destination, tid)
    simplehttp({
        url = string.format('https://api.twitter.com/1.1/statuses/show/%s.json', tid),
        headers = {
            ['Authorization'] = string.format("Bearer %s", access_token)
        },
    },
    function(data)
        local info = json.decode(data)
        outputTweet(say, source, destination, info)
    end
    )
end

local function tRateLimitStatus(self, source, destination)
    simplehttp({
        url = string.format('https://api.twitter.com/1.1/application/rate_limit_status.json?resources=statuses'),
        headers = {
            ['Authorization'] = string.format("Bearer %s", access_token)
        },
    },
    function(data)
        local info = json.decode(data)
        local resource = info.resources.statuses['/statuses/user_timeline']
        self:Msg('privmsg', destination, source, '\002timeline\002: Remaining %s, Limit %s, Reset %s', resource.remaining, resource.limit, resource.reset)
    end
    )
end

local function tFollowing(self, source, destination)
    if(destination == self.config.nick) then
        destination = source.nick
    end
    local db = openDb()
    local stmt = db:prepare('SELECT screen_name FROM twitter WHERE destination=?')
    stmt:bind_values(destination)
    local out = {}
    for row in stmt:rows() do
        table.insert(out, row[1])
    end
    db:close()
    if #out > 0 then 
        self:Msg('privmsg', destination, source, 'Following: %s', table.concat(out, ', '))
    else
        self:Msg('privmsg', destination, source, 'Not following.')
    end
end

local function saveSince(tweet)
    if tweet then
        local db = openDb()
        local insStmt = db:prepare("UPDATE last SET since_id = ? WHERE screen_name = ?")
        local code = insStmt:bind_values(tweet.id_str, tweet.user.screen_name)
        code = insStmt:step()
        code = insStmt:finalize()
        db:close()
    end
end


local function tPoll(self)
    local db = openDb()
    for row in db:nrows('SELECT DISTINCT twitter.screen_name, since_id FROM twitter JOIN last ON twitter.screen_name=last.screen_name') do
        local url = string.format('https://api.twitter.com/1.1/statuses/user_timeline.json?exclude_replies=true&screen_name=%s', row.screen_name)
        if tonumber(row.since_id) > 0 then
            url = url .. string.format('&since_id=%s', row.since_id)
        else
            local initial_count = 1
            url = url .. string.format('&count=%s', initial_count)
        end
        simplehttp({
                url,
                headers = {
                    ['Authorization'] = string.format("Bearer %s", access_token)
                },
            },
            function(data)
                local info = json.decode(data)
                local tweet = info[1]
                if tweet then 
                    saveSince(tweet)

                    local destinations = {}
                    local stmt = openDb():prepare('SELECT destination FROM twitter WHERE screen_name=?')
                    local code = stmt:bind_values(tweet.user.screen_name)
                    for row in stmt:nrows() do
                        table.insert(destinations, row.destination)
                    end

                    for _,tweet in pairs(info) do
                        for _, destination in pairs(destinations) do
                            outputTweet(nil, nil, destination, tweet)
                        end
                    end
                end
            end
        )
        
    end
    db:close()
end

local function tFollow(self, source, destination, screen_name)
    if(destination == self.config.nick) then
        destination = source.nick
    end
    local db = openDb()
    local insStmt = db:prepare("INSERT INTO twitter (screen_name, destination) VALUES(?, ?)")
    local code = insStmt:bind_values(screen_name, destination)
    code = insStmt:step()
    code = insStmt:finalize()
    local insStmt = db:prepare("INSERT INTO last (screen_name, since_id) VALUES(?, ?)")
    local code = insStmt:bind_values(screen_name, '0')
    code = insStmt:step()
    code = insStmt:finalize()
    db:close()
    self:Msg('privmsg', destination, source, 'Now following \002%s\002', screen_name)
end

local function tunFollow(self, source, destination, screen_name)
    if(destination == self.config.nick) then
        destination = source.nick
    end
    local db = openDb()
    --[[local insStmt = db:prepare("DELETE FROM last WHERE screen_name = ?")
    if insStmt then
        local code = insStmt:bind_values(screen_name)
        code = insStmt:step()
        code = insStmt:finalize()
    end
    --]]
    local insStmt = db:prepare("DELETE FROM twitter WHERE screen_name = ? AND destination = ?")
    if insStmt then
        local code = insStmt:bind_values(screen_name, destination)
        code = insStmt:step()
        code = insStmt:finalize()
    end
    db:close()
    self:Msg('privmsg', destination, source, 'Stopped following \002%s\002', screen_name)
end

local function getLatestStatuses(say, source, destination, screen_name, count)
    if not count then
        count = 1
    else
        count = tonumber(count)
    end
    simplehttp({
            url = string.format('https://api.twitter.com/1.1/statuses/user_timeline.json?exclude_replies=true&screen_name=%s', screen_name),
            headers = {
                ['Authorization'] = string.format("Bearer %s", access_token)
            },
        },
        function(data)
            local info = json.decode(data)
            outputTweet(say, source, destination, info[count])
        end
    )
end


local function getToken()
    local tokenurl = "https://api.twitter.com/oauth2/token"
    simplehttp({
            url = tokenurl,
            method = 'POST',
            headers = {
                ['Content-Type'] = 'application/x-www-form-urlencoded;charset=UTF-8',
                ['Authorization'] = string.format( "Basic %s", base64.encode(
                            string.format( "%s:%s",
                                ivar2.config.twitterApiKey,
                                ivar2.config.twitterApiSecret
                            )
                        )
                    )
            },
            data = 'grant_type=client_credentials',
        },
        function(data)
            local info = json.decode(data)
            -- Save access token for further use
            access_token = info.access_token
        end
    )
    return true
end

-- get initial token
getToken()

local id = 'twitterUpdater'
local runningTimer = ivar2.timers[id]

-- stop any running timer
if(runningTimer) then
    -- cancel existing timer
    runningTimer:stop(ivar2.Loop)
end

local duration = 60
-- start new poller
local timer = ev.Timer.new(
    function(loop, timer, revents)
        tPoll()
    end,
    5,
    duration
)
ivar2.timers[id] = timer
timer:start(ivar2.Loop)


return {
    PRIVMSG = {
        ['^%ptwitter (%d+)%s*$'] = function(self, source, destination, tid)
            getStatus(say, source, destination, tid)
        end,
        ['^%ptweet (%d+)%s*$'] = function(self, source, destination, tid)
            getStatus(say, source, destination, tid)
        end,
        ['^%ptwitter ([a-zA-Z0-9_]+)%s*$'] = function(self, source, destination, screen_name)
            getLatestStatuses(say, source, destination, screen_name)
        end,
        ['^%ptweet ([a-zA-Z0-9_]+)%s*$'] = function(self, source, destination, screen_name)
            getLatestStatuses(say, source, destination, screen_name)
        end,
        ['^%ptwitter ([a-zA-Z0-9_]+) (%d+)%s*$'] = function(self, source, destination, screen_name, count)
            getLatestStatuses(say, source, destination, screen_name, count)
        end,
        ['^%ptweet ([a-zA-Z0-9_]+) (%d+)$'] = function(self, source, destination, screen_name, count)
            getLatestStatuses(say, source, destination, screen_name, count)
        end,
        ['^%ptfollow ([a-zA-Z0-9_]+)%s*$'] = function(self, source, destination, screen_name)
            tFollow(self, source, destination, screen_name)
            --tPoll(self, source, destination)
        end,
        ['^%ptunfollow ([a-zA-Z0-9_]+)%s*$'] = function(self, source, destination, screen_name)
            tunFollow(self, source, destination, screen_name)
        end,
        ['^%ptpoll$'] = function(self, source, destination)
            tPoll(self, source, destination)
        end,
        ['^%ptrlstatus$'] = function(self, source, destination)
            tRateLimitStatus(self, source, destination)
        end,
        ['^%pfollowing$'] = function(self, source, destination)
            tFollowing(self, source, destination)
        end,
    },
}
