{:simplehttp, :json, :bold} = require'util'
pgsql = require'cqueues_pgsql'

conn = false

connect = () ->
	conn = pgsql.connectdb("dbname=" .. tostring(ivar2.config.dbname) .. " user=" .. tostring(ivar2.config.dbuser) .. " password=" .. tostring(ivar2.config.dbpass) .. " host=" .. tostring(ivar2.config.dbhost) .. " port=" .. tostring(ivar2.config.dbport))
	if conn\status! ~= pgsql.CONNECTION_OK then
		ivar2:Log('error', "Unable to connect to DB: %s", conn:errorMessage())

dbh = ->
	connect! unless conn

	if conn\status! != pgsql.CONNECTION_OK
		log\error conn\errorMessage
		connect!

	success, err = conn\exec('SELECT NOW()')
	unless success
		log\error "SQL Connection :#{err}"
		connect!

	return conn

res2rows = (res) ->
	if not res\status! == 2 then error(res\errorMessage(), nil)
	rows = {}

	for i=1, res\ntuples()
		row = {}
		for j=1, res\nfields!
			row[res\fname(j)] = res\getvalue(i, j)
		rows[#rows+1] = row
	return rows

PRIVMSG:
	'^%prandomtube$': (source, destination) =>
		query = [[
			SELECT
				date_trunc('second', time) as time,
				date_trunc('second', age(now(), date_trunc('second', time))) as age,
				nick,
				url
			FROM urls
			WHERE
				channel = $1
			AND
				(url ILIKE '%youtube.com%' OR url ILIKE '%youtu.be%')
			ORDER BY RANDOM()
			LIMIT 1
		]]
		rows = res2rows(dbh!\execParams(query, destination))
		if #rows == 1
			url = rows[1].url
			nick = rows[1].nick
			age = rows[1].age
			say "%s by %s, %s ago", url, nick, age

