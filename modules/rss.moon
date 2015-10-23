-- Module for subscribing to RSS and announce to channels
feedparser = require 'feedparser' -- http://feedparser.luaforge.net/
{:simplehttp, :json, :urlEncode, :bold} = require'util'
html2unicode = require 'html'
sql = require'lsqlite3'

moduleName = 'rss'

get_db = ->
  db = sql.open 'cache/rss.sql'

  code = db\exec [[
    CREATE TABLE IF NOT EXISTS feed (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT,
      rssurl VARCHAR(1024) NOT NULL,
      url VARCHAR(1024),
      title VARCHAR(1024),
      author VARCHAR(1024),
      etag TEXT,
      lastmodified TEXT
    );

    CREATE TABLE IF NOT EXISTS item (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      feed_id INTEGER NOT NULL,
      guid VARCHAR(64),
      title VARCHAR(1024),
      author VARCHAR(1024),
      url VARCHAR(1024),
      feedurl VARCHAR(1024),
      pubDate TEXT,
      summary TEXT,
      content TEXT,
      FOREIGN KEY(feed_id) REFERENCES feed(id),
      UNIQUE (guid, feed_id)
    );

    CREATE TABLE IF NOT EXISTS subscription (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      destination varchar(100),
      feed_id INTEGER,
      last INTEGER DEFAULT 0,
      created_at timestamp DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(feed_id) REFERENCES feed(id)
    );
    ]]

  if code != sql.OK
    ivar2\Log 'error', "Error during opendb: #{db\errmsg!}"
    return nil

  return db

prepare = (db, stmt, ...) ->
  code = db\prepare stmt
  unless code
    ivar2\Log 'error', "Error with statement prepare: #{db\errmsg!}"
    return nil
  code\bind_values ...
  return code

-- Function that add functionality to extract specific information for specific sites
feedSpecific = (feedurl, link, title, summary, content) ->
  if feedurl\match 'https://comics.io/my/'

    title = summary\match '<h3>(.-)</h3>' or ''
    img, alt = summary\match '<img src="(.-)".- title="(.-)".-></p>'
    return "#{html2unicode title} #{img} #{html2unicode alt}"

  return "#{title} - #{link}"

announce = (id) ->
  db = get_db!
  stmt = prepare db, "SELECT DISTINCT feed.id, destination FROM feed JOIN subscription ON subscription.feed_id = feed.id WHERE feed.id = ?", id
  for row in stmt\rows!
    destination = row[2]

    highest = 0
    -- Check last value
    stmt = prepare db, "SELECT last FROM subscription WHERE feed_id = ? and destination = ?", id, destination
    stmt\step!
    value = stmt\get_values()[1]
    if value and value ~= '' and tonumber(value) and tonumber(value) > 0
      highest = value

    ivar2\Log 'debug', 'Got highest %s, %s, %s', id, destination, highest

    stmt = prepare db, "SELECT feed.id AS feed_id, item.id AS item_id, rssurl, pubDate, name, etag, item.url AS link, item.title, content, summary FROM feed JOIN item on item.feed_id = feed.id WHERE feed.id = ? AND item.id > ? ORDER BY item.id DESC LIMIT 100", id, highest
    out = {}
    for item in stmt\nrows!
      with item
        if .item_id > highest
          highest = .item_id
          table.insert out, "[#{bold .name}]: #{feedSpecific(.rssurl, .link, .title, .summary, .content)}"
    if #out > 0
      ivar2\Msg 'privmsg', destination, ivar2.nick, "RSS "..table.concat(out, ', ')
    -- Update last red
    ins = prepare db, 'UPDATE subscription SET last=? WHERE feed_id = ? and destination = ?', highest, id, destination
    code, err = ins\step!
    code, err = ins\finalize!
  db\close!

poll = ->
  db = get_db!
  channels = {}
  for c,_ in pairs(ivar2.channels)
    channels[c] = true
  for row in db\rows "SELECT DISTINCT feed.id, rssurl, lastmodified, name, etag, destination FROM feed JOIN subscription ON subscription.feed_id = feed.id"
  -- Ignore feeds this particular instance of the bot does not subscribe to
    if not channels[row[6]]
      continue
    id = row[1]
    rssurl = row[2]
    lm = row[3]
    name = row[4]
    etag = row[5]
    headers = {}
    if lm and lm != '' then
      headers['If-Modified-Since'] = lm
    if etag and etag != '' then
      headers['If-None-Match'] = etag

    simplehttp {url:rssurl,headers:headers}, (data, url, response) ->
      -- Reopenn DB because of async
      sdb = get_db!

      lastModified = response.headers['Last-Modified']
      if not lastModified
        lastModified = response.headers['Date']

      -- Unmodified content
      if response.status_code == 304
        -- return from the simplehttp callback
        return

      feed, err = feedparser.parse data
      if err
        ivar2\Log 'error', "#{moduleName}: Error during parsing: <#{err}> data for feed: <#{name}> with URL <#{url}>"
      else
        title = feed.title
        author = feed.author
        url = feed.link

        -- Update feed with new values
        ins = sdb\prepare 'UPDATE feed SET title=?, author=?, url=?, lastmodified=? WHERE id=?'
        code, err = ins\bind_values title, author, url, lastModified, id
        code, err = ins\step!
        code, err = ins\finalize!

        out = {}
        for i, e in ipairs(feed.entries)
          -- Attempt to get a unique entry ID
          guid = e.guid
          if not guid then guid = e.id
          if not guid then guid = e.link
          if not guid
            ivar2\Log 'error', "#{moduleName}: No GUID when parsing entry: <#{e}> data for feed: <#{name}> with URL <#{url}>"
            break

          --if guid == last
          --  break
          ins = sdb\prepare [[
            INSERT OR IGNORE INTO
              item(feed_id, guid, title, author, url, pubDate, content, summary)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ]]
          if not ins then
            ivar2\Log 'error', "#{moduleName}: Error during inserting entry: <#{err}> feed: <#{name}> with URL <#{url}> and position: #{i}"
          else
            code = ins\bind_values id, guid, e.title, e.author, e.link, e.updated, e.content, e.summary
            code = ins\step!
            code = ins\finalize!
        announce(id)
      sdb\close!
  db\close!


subscribe = (source, destination, name, url) =>
  db = get_db!
  ins = db\prepare "INSERT INTO feed (name, rssurl) VALUES(?, ?)"
  code = ins\bind_values name, url
  code = ins\step!
  code = ins\finalize!
  ins = db\prepare "INSERT INTO subscription (feed_id, destination) VALUES(?, ?)"
  code = ins\bind_values db\last_insert_rowid!, destination
  code = ins\step!
  code = ins\finalize!
  db\close!
  reply "Ok. Subscribed to #{bold name}"
  poll!

unsubscribe = (source, destination, name) =>
  db = get_db!
  ins = db\prepare "DELETE FROM subscription WHERE feed_id IN (select id from feed where name = ?) and destination = ?"
  code = ins\bind_values name, destination
  code = ins\step!
  code = ins\finalize!
  total_changes = db\total_changes!
  db\close!
  if total_changes < 1
    reply "Wasn't subscribed. But, sure."
  else
    reply "Ok. Stopped caring about #{bold name}"

list = (source, destination) =>
  out = {}
  db = get_db!
  stmt = db\prepare("SELECT name FROM feed JOIN subscription ON feed.id = subscription.feed_id WHERE destination = ?")
  stmt\bind_values destination
  for row in stmt\rows!
    out[#out+1] = row[1]
  if #out > 0 then
    reply "Subscribed to: #{table.concat(out, ', ')}"
  else
    reply "Not subscribed to any feeds."

  db\close!

-- Start the subscribe poller
ivar2\Timer(moduleName, 60*5, 60*5, poll)

PRIVMSG:
  '^%prss latest (.*)': getLatest
  '^%prss subscribe (.-) (.*)': subscribe
  '^%prss unsubscribe (.*)': unsubscribe
  '^%prss list': list
  -- for debugging
  '^%prss poll': poll
