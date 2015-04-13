local DBI = require 'DBI'
local util = require'util'
require'logging.console'
local log = logging.console()

-- Connection handle
local conn = false


-- Open connection to the postgresql database using DBI lib and ivar2 global config
local connect = function()
    local dbh, err = DBI.Connect('PostgreSQL', ivar2.config.dbname, ivar2.config.dbuser, ivar2.config.dbpass, ivar2.config.dbhost, ivar2.config.dbport)
    if not dbh then
        log:error("Unable to connect to DB: %s", err)
        return
    end
    conn = dbh
end

local openDb = function()
    if not conn then
        connect()
    end

    -- Check if connection is alive
    local alive = conn:ping()
    if not alive then
        connect()
    end

    local success, err = DBI.Do(conn, 'SELECT NOW()')
    if not success then
        log:error("SQL Connection: %s", err)
        connect()
    end

    return conn
end

local function url_to_pattern(str)
    str = str:gsub('^https?://', 'http%%://')
    return str
end

local function extract_youtube_id(str)
    local patterns = {
        "https?://www%.youtube%.com/watch%?.*v=([%d%a_%-]+)",
        "https?://youtube%.com/watch%?.*v=([%d%a_%-]+)",
        "https?://youtu.be/([%d%a_%-]+)",
        "https?://youtube.com/v/([%d%a_%-]+)",
        "https?://www.youtube.com/v/([%d%a_%-]+)"
    }
    for _,pattern in ipairs(patterns) do
        local video_id = string.match(str, pattern)
        if video_id ~= nil and string.len(video_id) < 20 then
            return video_id
        end
    end
end

-- check for existing url
local checkOlds = function(dbh, source, destination, url)

    -- create a select handle
    local query = [[
            SELECT
                date_trunc('second', time),
                date_trunc('second', age(now(), date_trunc('second', time))),
                nick
            FROM urls
            WHERE
                url LIKE ?
            AND
                channel = ?
            ORDER BY time ASC
    ]]

    -- Check for youtube ID
    local vid = extract_youtube_id(url)
    if vid ~= nil then
        url = '%youtube.com%v='..vid..'%'
    end
    url = url_to_pattern(url)
    local sth = assert(dbh:prepare(query))

    -- execute select with a url bound to variable
    sth:execute(url, destination)

    -- get list of column names in the result set
    --local columns = sth:columns()

    local count = 0
    local nick
    local ago

    -- iterate over the returned data
    for row in sth:rows() do
        count = count + 1
        -- rows() with no arguments (or false) returns
        -- the data as a numerically indexed table
        -- passing it true returns a table indexed by
        -- column names
        if count == 1 then
            ago = row[2]
            nick = row[3]
            return nick, count, ago
        end
    end

    return nick, count, ago

end

-- save url to db
local dbLogUrl = function(dbh, source, destination, url, msg)
    local nick = source.nick

    log:info(string.format('Inserting URL into db. %s,%s, %s, %s', nick, destination, msg, url))

    -- check status of the connection
    -- local alive = dbh:ping()

    -- create a handle for an insert
    local insert = dbh:prepare('INSERT INTO urls(nick,channel,url,message) values(?,?,?,?)')

    -- execute the handle with bind parameters
    insert:execute(nick, destination, url, msg)

    -- commit the transaction
    dbh:commit()

    --local ok = dbh:close()
end

do
    return function(source, destination, queue, msg)
        local dbh = openDb()
        local nick, count, ago = checkOlds(dbh, source, destination, queue.url)
        dbLogUrl(dbh, source, destination, queue.url, msg)

        if not count then return end
        if count == 0 then return end

        -- Check if this module is disabled and just stop here if it is
        if not ivar2:IsModuleDisabled('olds', destination) then
            local prepend
            -- We don't need to highlight the first linker
            nick = util.nonickalertword(nick)
            if(count > 1) then
                prepend = string.format("Olds! %s times, first by %s %s", count, nick, ago)
            else
                prepend = string.format("Olds! Linked by %s %s ago", nick, ago)
            end

            if(queue.output) then
                queue.output = string.format("%s - %s", prepend, queue.output)
            else
                queue.output = prepend
            end
        end
	end
end

