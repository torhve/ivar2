URL_GAMES  = "https://worldcup26.ir/get/games"
URL_TEAMS  = "https://worldcup26.ir/get/teams"
URL_STADIUMS = "https://worldcup26.ir/get/stadiums"

-- Default timezone mapping - can be overridden by configuration
DEFAULT_REGION_OFFSET = {Eastern: 7, Central: 8, Western: 10}

-- ISO2 country code fixes
ISO2_FIX = {["SCO"]: "SC", ["ENG"]: "GB", ["KSA"]: "SA", ["COD"]: "CD"}

-- Timezone configuration
TIMEZONE_CONFIG = {
  default_timezone: "Oslo",
  region_offsets: DEFAULT_REGION_OFFSET
}

teams_cache = nil
stadiums_cache = nil
live_state = {}
poll_timer = nil
last_modified = {}

http_get = (url, callback) ->
  opts = {url: url}
  if last_modified[url]
    opts.headers = {"If-Modified-Since": last_modified[url]}
  ivar2.util.simplehttp opts, (data, uri, response) ->
    if response and response.status_code == 304
      return
    if response and response.status_code >= 200 and response.status_code < 300
      if response and response.headers
        lm = response.headers["last-modified"]
        if lm
          last_modified[url] = lm
      callback data

pad2 = (n) ->
  string.format('%02d', n)

extract_last_scorer = (scorers_str) ->
  if scorers_str == "null" or not scorers_str
    return nil
  s = scorers_str\gsub('\226\128[\156\157]', '"')
  last = nil
  for name in s\gmatch('"([^"]+)"') do
    last = name
  return last

iso2_flag = (iso2) ->
  fixed = ISO2_FIX[iso2] or iso2
  if #fixed != 2
    return ""
  c1 = string.byte(fixed, 1)
  c2 = string.byte(fixed, 2)
  b1 = 0xA6 + (c1 - 0x41)
  b2 = 0xA6 + (c2 - 0x41)
  string.char(0xF0, 0x9F, 0x87, b1) .. string.char(0xF0, 0x9F, 0x87, b2)

-- Generic timezone conversion function
convert_timezone = (local_date_str, stadium_id, target_timezone = "Oslo") ->
  -- Parse date and time components
  date_part, hour_str, min_str = string.match(local_date_str, "(%d+/%d+/%d+) (%d+):(%d+)")
  if not date_part
    return local_date_str, local_date_str

  m, d, y = string.match(date_part, "(%d+)/(%d+)/(%d+)")
  m = tonumber(m)
  d = tonumber(d)
  y = tonumber(y)
  h = tonumber(hour_str)
  mn = tonumber(min_str)

  -- Get timezone offset
  offset = 0
  stadium_region = nil
  if stadiums_cache
    for s in *stadiums_cache
      if tonumber(s.id) == tonumber(stadium_id)
        offset = TIMEZONE_CONFIG.region_offsets[s.region] or 0
        stadium_region = s.region
        break

  -- Adjust for DST during June World Cup (US/Canada observe DST, Qatar/Mexico do not)
  if m >= 3 and m <= 11 and stadium_region
    if stadium_region == "Eastern"
      offset = offset - 1
    elseif stadium_region == "Central"
      offset = offset - 1
    elseif stadium_region == "Western"
      offset = offset - 1

  -- Apply offset to hours
  h = h + offset

  -- Handle date rollover
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

  -- Return formatted date and time
  return "#{pad2(m)}/#{pad2(d)}/#{y}", "#{string.format('%02d', h)}:#{string.format('%02d', mn)}"



fetch_teams = (callback) ->
  http_get URL_TEAMS, (json) ->
    teams_cache = ivar2.util.json.decode(json).teams
    callback()

fetch_stadiums = (callback) ->
  http_get URL_STADIUMS, (json) ->
    stadiums_cache = ivar2.util.json.decode(json).stadiums
    callback()

lookup_flag = (team_id) ->
  if not teams_cache
    return "", "TBD"
  for t in *teams_cache
    if tonumber(t.id) == team_id
      return iso2_flag(t.iso2), t.fifa_code
  "", "TBD"

lookup_stadium = (stadium_id) ->
  if not stadiums_cache
    return "TBD"
  for s in *stadiums_cache
    if tonumber(s.id) == tonumber(stadium_id)
      return s.name_en or "TBD"
  "TBD"

next_match_for = (team_id, callback) ->
  http_get URL_GAMES, (json) ->
    data = ivar2.util.json.decode(json)
    matches = {}
    for g in *data.games
      home = tonumber(g.home_team_id)
      away = tonumber(g.away_team_id)
      if home == 0 or away == 0
        continue
      if home == team_id or away == team_id
        if g.time_elapsed == "notstarted" and g.finished ~= "TRUE"
          matches[#matches + 1] = g
    if #matches == 0
      callback nil
      return
    table.sort(matches, (a, b) ->
      a.local_date < b.local_date
    )
    callback matches[1]

format_match = (g) ->
  home_score = tonumber(g.home_score) or 0
  away_score = tonumber(g.away_score) or 0
  home_flag, home_code = lookup_flag(tonumber(g.home_team_id))
  away_flag, away_code = lookup_flag(tonumber(g.away_team_id))
  _, time = convert_timezone(g.local_date, g.stadium_id)
  "#{home_flag} #{home_code} - #{away_code} #{away_flag} [#{home_score}-#{away_score}] #{time}"

format_match_started = (g) ->
  home_score = tonumber(g.home_score) or 0
  away_score = tonumber(g.away_score) or 0
  home_flag, home_code = lookup_flag(tonumber(g.home_team_id))
  away_flag, away_code = lookup_flag(tonumber(g.away_team_id))
  _, time = convert_timezone(g.local_date, g.stadium_id)
  venue = lookup_stadium(g.stadium_id)
  stage = if g.matchday ~= "" then "Group #{g.group}, Matchday #{g.matchday}" else g.group
  "#{home_flag} #{home_code} - #{away_code} #{away_flag} [#{home_score}-#{away_score}] #{time} | #{venue} | #{stage}"

get_oslo_datetime = ->
  cest = os.date("!*t", os.time() + 7200)
  "#{pad2(cest.month)}/#{pad2(cest.day)}/#{cest.year}", "#{pad2(cest.hour)}:#{pad2(cest.min)}"

relative_time = (match_date, match_time) ->
  now_date, now_time = get_oslo_datetime!
  mm, dd, yy = string.match(match_date, "(%d+)/(%d+)/(%d+)")
  mh, mn = string.match(match_time, "(%d+):(%d+)")
  nm, nd, ny = string.match(now_date, "(%d+)/(%d+)/(%d+)")
  nh, nmn = string.match(now_time, "(%d+):(%d+)")
  match_ts = os.time {year: tonumber(yy), month: tonumber(mm), day: tonumber(dd), hour: tonumber(mh), min: tonumber(mn), sec: 0}
  now_ts = os.time {year: tonumber(ny), month: tonumber(nm), day: tonumber(nd), hour: tonumber(nh), min: tonumber(nmn), sec: 0}
  diff = match_ts - now_ts
  days = math.floor(diff / 86400)
  if days == 0
    "today at #{match_time}"
  elseif days == 1
    "tomorrow at #{match_time}"
  else
    "in #{days} days at #{match_time}"

format_next_match = (g, fifa_code) ->
  hs = tonumber(g.home_score) or 0
  as_ = tonumber(g.away_score) or 0
  home_flag, home_code = lookup_flag(tonumber(g.home_team_id))
  away_flag, away_code = lookup_flag(tonumber(g.away_team_id))
  venue = lookup_stadium(g.stadium_id)
  match_date, match_time = convert_timezone(g.local_date, g.stadium_id)
  stage = if g.matchday ~= "" then "Group #{g.group}, Matchday #{g.matchday}" else g.group
  match_part = "#{home_flag} #{home_code} - #{away_code} #{away_flag} [#{hs}-#{as_}]"
  "next match for #{fifa_code}: #{match_part} | #{relative_time match_date, match_time} | #{venue} | #{stage}"

show_matches = (date_str, callback) ->
  http_get URL_GAMES, (json) ->
    data = ivar2.util.json.decode(json)
    out = {}
    for g in *data.games
      if tonumber(g.home_team_id) == 0
        continue
      date, _ = convert_timezone(g.local_date, g.stadium_id)
      if date == date_str
        out[#out + 1] = format_match(g)
    callback(table.concat(out, " · "))

get_oslo_date = ->
  cest = os.date("!*t", os.time() + 7200)
  "#{pad2(cest.month)}/#{pad2(cest.day)}/#{cest.year}"

ensure_caches = (callback) ->
  if teams_cache and stadiums_cache
    callback()
    return
  fetch_teams (() ->
    fetch_stadiums callback
  )

handle_wc_lookup = (iso2, captured) ->
  fixed = ISO2_FIX[iso2] or iso2
  ensure_caches (() ->
    team = nil
    for t in *teams_cache
      if t.iso2 == fixed
        team = t
        break
    if not team
      reply "Country code not found."
      return
    next_match_for tonumber(team.id), (g) ->
      if not g
        reply "#{team.fifa_code} has no upcoming matches."
        return
      msg = format_next_match(g, team.fifa_code)
      reply msg
  )
poll_games = ->
  if not teams_cache
    return
  http_get URL_GAMES, (json) ->
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
        if state.last_finished[mid]
          continue
        prev = state.last_scores[mid]
        if not prev and elapsed ~= "notstarted"
          ivar2\Say(ch, ivar2.config.nick, "🏁 Match started: #{format_match_started(g)}")
          state.last_scores[mid] = current
        else if prev and prev ~= current
          home_flag, home_code = lookup_flag(tonumber(g.home_team_id))
          away_flag, away_code = lookup_flag(tonumber(g.away_team_id))
          prev_home = tonumber(string.match(prev, "^(%d+)")) or 0
          prev_away = tonumber(string.match(prev, "-?(%d+)$")) or 0
          home_num = tonumber(string.match(current, "^(%d+)")) or 0
          away_num = tonumber(string.match(current, "-?(%d+)$")) or 0
          home_str = home_num > prev_home and ivar2.util.green(tostring(home_num)) or tostring(home_num)
          away_str = away_num > prev_away and ivar2.util.green(tostring(away_num)) or tostring(away_num)
          msg = "⚽ Goal! #{home_flag} #{home_code} - #{away_code} #{away_flag} [#{home_str}-#{away_str}]"
          if g.home_scorers ~= "null" and home_score > prev_home
            scorer = extract_last_scorer(g.home_scorers)
            if scorer
              msg = msg .. " (#{scorer})"
          if g.away_scorers ~= "null" and away_score > prev_away
            scorer = extract_last_scorer(g.away_scorers)
            if scorer
              msg = msg .. " (#{scorer})"
          ivar2\Say(ch, ivar2.config.nick, msg)
          state.last_scores[mid] = current
        else if prev and not (state.last_finished[mid] or false) and finished
          ivar2\Say(ch, ivar2.config.nick, "🏁 Match ended: #{format_match(g)}")
          state.last_finished[mid] = true

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
    http_get URL_GAMES, (json) ->
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
  ['^%pwc live on$']: (source, destination) =>
    if not live_state[destination]
      live_state[destination] = {enabled: false, last_scores: {}, last_finished: {}}
    ensure_caches ->
      http_get URL_GAMES, (json) ->
        data = ivar2.util.json.decode(json)
        for g in *data.games
          mid = g.id
          elapsed = g.time_elapsed
          finished = g.finished == "TRUE"
          if finished
            live_state[destination].last_finished[mid] = true
          elseif elapsed ~= "notstarted"
            home_score = tonumber(g.home_score) or 0
            away_score = tonumber(g.away_score) or 0
            live_state[destination].last_scores[mid] = "#{home_score}-#{away_score}"
        live_state[destination].enabled = true
        reply "Live tracking enabled for this channel."
        start_poll!
  ['^%pwc live off$']: (source, destination) =>
    if live_state[destination]
      live_state[destination].enabled = false
      live_state[destination].last_scores = {}
      live_state[destination].last_finished = {}
    reply "Live tracking disabled for this channel."
  ['^%pwc ([A-Z][A-Z])$']: (source, destination, captured) =>
    iso2 = string.match(captured, "([A-Z][A-Z])")
    fixed = ISO2_FIX[iso2] or iso2
    ensure_caches ->
      team = nil
      for t in *teams_cache
        if t.iso2 == fixed
          team = t
          break
      if not team
        reply "Country code not found."
        return
      next_match_for tonumber(team.id), (g) ->
        if not g
          reply "#{team.fifa_code} has no upcoming matches."
          return
        msg = format_next_match(g, team.fifa_code)
        reply msg