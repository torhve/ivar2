URL_GAMES  = "https://worldcup26.ir/get/games"
URL_TEAMS  = "https://worldcup26.ir/get/teams"
URL_STADIUMS = "https://worldcup26.ir/get/stadiums"

REGION_OFFSET = {Eastern: 7, Central: 8, Western: 10}

ISO2_FIX = {["SCO"]: "SC", ["ENG"]: "GB", ["KSA"]: "SA", ["COD"]: "CD"}

teams_cache = nil
stadiums_cache = nil
live_state = {}
poll_timer = nil

pad2 = (n) ->
  string.format('%02d', n)

iso2_flag = (iso2) ->
  fixed = ISO2_FIX[iso2] or iso2
  if #fixed != 2
    return ""
  c1 = string.byte(fixed, 1)
  c2 = string.byte(fixed, 2)
  b1 = 0xA6 + (c1 - 0x41)
  b2 = 0xA6 + (c2 - 0x41)
  string.char(0xF0, 0x9F, 0x87, b1) .. string.char(0xF0, 0x9F, 0x87, b2)

convert_to_oslo = (local_date_str, stadium_id) ->
  date_part, hour_str, min_str = string.match(local_date_str, "(%d+/%d+/%d+) (%d+):(%d+)")
  if not date_part
    return local_date_str, local_date_str
  m, d, y = string.match(date_part, "(%d+)/(%d+)/(%d+)")
  m = tonumber(m)
  d = tonumber(d)
  y = tonumber(y)
  h = tonumber(hour_str)
  mn = tonumber(min_str)
  offset = 0
  if stadiums_cache
    for s in *stadiums_cache
      if tonumber(s.id) == tonumber(stadium_id)
        offset = REGION_OFFSET[s.region] or 0
        break
  h = h + offset
  if h >= 24
    h = h - 24
    d = d + 1
    days_in_month = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    if d > days_in_month[m]
      d = 1
      m = m + 1
      if m > 12
        m = 1
        y = y + 1
  return "#{pad2(m)}/#{pad2(d)}/#{y}", "#{string.format('%02d', h)}:#{string.format('%02d', mn)}"

fetch_teams = (callback) ->
  ivar2.util.simplehttp URL_TEAMS, (json) ->
    teams_cache = ivar2.util.json.decode(json).teams
    callback()

fetch_stadiums = (callback) ->
  ivar2.util.simplehttp URL_STADIUMS, (json) ->
    stadiums_cache = ivar2.util.json.decode(json).stadiums
    callback()

lookup_flag = (team_id) ->
  if not teams_cache
    return "", "TBD"
  for t in *teams_cache
    if tonumber(t.id) == team_id
      return iso2_flag(t.iso2), t.fifa_code
  "", "TBD"

format_match = (g) ->
  home_score = tonumber(g.home_score) or 0
  away_score = tonumber(g.away_score) or 0
  home_flag, home_code = lookup_flag(tonumber(g.home_team_id))
  away_flag, away_code = lookup_flag(tonumber(g.away_team_id))
  _, oslo_time = convert_to_oslo(g.local_date, g.stadium_id)
  "#{home_flag} #{home_code} - #{away_code} #{away_flag} [#{home_score}-#{away_score}] #{oslo_time}"

show_matches = (date_str, callback) ->
  ivar2.util.simplehttp URL_GAMES, (json) ->
    data = ivar2.util.json.decode(json)
    out = {}
    for g in *data.games
      if tonumber(g.home_team_id) == 0
        continue
      oslo_date, _ = convert_to_oslo(g.local_date, g.stadium_id)
      if oslo_date == date_str
        out[#out + 1] = format_match(g)
    callback(table.concat(out, " · "))

get_oslo_date = ->
  utc = os.time()
  local_ts = os.time(os.date("*t", utc))
  cest_offset = (utc - local_ts) + 7200
  t = os.date("*t", utc + cest_offset)
  "#{pad2(t.month)}/#{pad2(t.day)}/#{t.year}"

ensure_caches = (callback) ->
  if teams_cache and stadiums_cache
    callback()
    return
  fetch_teams (() ->
    fetch_stadiums callback
  )

poll_games = ->
  ivar2.util.simplehttp URL_GAMES, (json) ->
    data = ivar2.util.json.decode(json)
    for g in *data.games
      mid = g.id
      home_score = tonumber(g.home_score) or 0
      away_score = tonumber(g.away_score) or 0
      current = "#{home_score}-#{away_score}"
      finished = g.finished == "TRUE"
      elapsed = g.time_elapsed
      for ch, state in pairs(live_state)
        if not state.enabled
          continue
        prev = state.last_scores[mid]
        if not prev and elapsed ~= "notstarted"
          ivar2\Say(ch, ivar2.config.nick, format_match(g))
          state.last_scores[mid] = current
        else if prev and prev ~= current
          home_flag, home_code = lookup_flag(tonumber(g.home_team_id))
          away_flag, away_code = lookup_flag(tonumber(g.away_team_id))
          msg = "⚽ Goal! #{home_flag} #{home_code} - #{away_code} #{away_flag} [#{current}]"
          prev_home = tonumber(string.match(prev, "^(%d+)")) or 0
          prev_away = tonumber(string.match(prev, "-?(%d+)$")) or 0
          if g.home_scorers ~= "null" and home_score > prev_home
            scorers = ivar2.util.split(g.home_scorers, ",")
            last_scorer = scorers[#scorers]
            scorer = string.match(last_scorer, "^%s*(.-)%s*$") or last_scorer
            msg = msg .. " (#{scorer})"
          if g.away_scorers ~= "null" and away_score > prev_away
            scorers = ivar2.util.split(g.away_scorers, ",")
            last_scorer = scorers[#scorers]
            scorer = string.match(last_scorer, "^%s*(.-)%s*$") or last_scorer
            msg = msg .. " (#{scorer})"
          ivar2\Say(ch, ivar2.config.nick, msg)
          state.last_scores[mid] = current
        else if prev and not (state.last_finished[mid] or false) and finished
          ivar2\Say(ch, ivar2.config.nick, "🏁 Match ended: #{format_match(g)}")
          state.last_scores[mid] = nil
          state.last_finished[mid] = true
        else if not prev and elapsed ~= "notstarted"
          state.last_scores[mid] = current

start_poll = ->
  if poll_timer
    return
  poll_timer = ivar2\Timer("wc_live", 30, 30, (loop, timer, revents) ->
    active = false
    for ch, st in pairs(live_state)
      if st.enabled
        active = true
        break
    if not active
      poll_timer\stop!
      poll_timer = nil
      return
    poll_games()
  )

PRIVMSG:
  ['^%pwc today$']: (source, destination) ->
    ensure_caches (() ->
      date = get_oslo_date!
      show_matches date, (out) ->
        if #out < 1
          reply "No matches today."
        else
          say out
    )
  ['^%pwc tomorrow$']: (source, destination) ->
    today = get_oslo_date!
    m, d, y = string.match(today, "(%d+)/(%d+)/(%d+)")
    d = tonumber(d) + 1
    days_in_month = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    if d > days_in_month[tonumber(m)]
      d = 1
      m = tonumber(m) + 1
      if m > 12
        m = 1
        y = tonumber(y) + 1
    tomorrow = "#{m}/#{d}/#{y}"
    ensure_caches (() ->
      show_matches tomorrow, (out) ->
        if #out < 1
          reply "No matches tomorrow."
        else
          say out
    )
  ['^%pwc$']: (source, destination) ->
    ivar2.util.simplehttp URL_GAMES, (json) ->
      data = ivar2.util.json.decode(json)
      out = {}
      for g in *data.games
        if tonumber(g.home_team_id) == 0
          continue
        if g.time_elapsed ~= "notstarted" and g.finished ~= "TRUE"
          out[#out + 1] = format_match(g)
      if #out < 1
        reply "No matches currently being played."
      else
        say table.concat(out, " · ")
  ['^%pwc live on$']: (source, destination) ->
    if not live_state[destination]
      live_state[destination] = {enabled: false, last_scores: {}, last_finished: {}}
    live_state[destination].enabled = true
    reply "Live tracking enabled for this channel."
    start_poll()
  ['^%pwc live off$']: (source, destination) ->
    if live_state[destination]
      live_state[destination].enabled = false
      live_state[destination].last_scores = {}
      live_state[destination].last_finished = {}
    reply "Live tracking disabled for this channel."