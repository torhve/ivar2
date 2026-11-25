local pgsql = require "cqueues_pgsql"
local util = require'util'

-- Connection handle
local conn = false

-- Open connection to the postgresql database using DBI lib and ivar2 global config
local connect = function()
    conn = pgsql.connectdb("dbname=" .. tostring(ivar2.config.dbname) .. " user=" .. tostring(ivar2.config.dbuser) .. " password=" .. tostring(ivar2.config.dbpass) .. " host=" .. tostring(ivar2.config.dbhost) .. " port=" .. tostring(ivar2.config.dbport))
    if conn:status() ~= pgsql.CONNECTION_OK then
        ivar2:Log('error', "pgolds: Unable to connect to DB: %s", conn:errorMessage())
        return
    end
end

local res2rows = function(res)
  if not res:status() == 2 then
    error(res:errorMessage(), nil)
  end
  local rows = {}
  for i = 1, res:ntuples() do
    local row = {}
    for j = 1, res:nfields() do
      row[res:fname(j)] = res:getvalue(i, j)
    end
    rows[#rows + 1] = row
  end
  return rows
end

local openDb = function()
    if not conn then
        connect()
    end
    if conn:status() ~= pgsql.CONNECTION_OK then
        ivar2:Log('error', "Reconnecting to DB: %s", conn:errorMessage())
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
                date_trunc('second', time) as time,
                date_trunc('second', age(now(), date_trunc('second', time))) as age,
                nick
            FROM urls
            WHERE
                url LIKE $1
            AND
                channel = $2
            ORDER BY time ASC
    ]]

    -- Check for youtube ID
    local vid = extract_youtube_id(url)
    if vid ~= nil then
        url = '%youtube.com%v='..vid..'%'
    end
    url = url_to_pattern(url)

    local rows = res2rows(dbh:execParams(query, url, destination))

    local count = 0
    local nick
    local ago

    -- iterate over the returned data
    for _, row in ipairs(rows) do
        count = count + 1
        if count == 1 then
            ago = row.age
            nick = row.nick
        end
    end

    return nick, count, ago

end

-- save url to db
local dbLogUrl = function(dbh, source, destination, url, msg)
    local nick = source.nick

    ivar2:Log('info', string.format('pgolds: Inserting URL: <%s>, %s, %s, %s', url, nick, destination, msg))

    -- create a handle for an insert
    local res = dbh:execParams('INSERT INTO urls(nick,channel,url,message) values($1,$2,$3,$4)', nick, destination, url, msg)
    if res:status() ~= pgsql.PGRES_COMMAND_OK then
        ivar2:Log('error', "pgolds: %s", res:errorMessage())
    end
end

do
    -- Check if postgresql is configured
    if not ivar2.config.dbhost then
        ivar2:Log('warning', "pgolds: PostgreSQL not configured, disabling handler")
        return function() end
    end
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
