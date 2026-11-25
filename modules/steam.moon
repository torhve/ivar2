{:urlEncode, :json, :simplehttp} = require'util'

STEAM_API_KEY = ivar2.config.steamAPIKey
STEAM_API_URL = "https://api.steampowered.com"
DOTA_MAX_RESULTS = 5

urlparams = (tbl) ->
  out = {}
  for k, v in pairs(tbl)
    table.insert(out, urlEncode(k)..'='..urlEncode(v))
  table.concat(out, '&')

GetSteamResult = (endpoint, params={}, version = 1) ->
  params.key = STEAM_API_KEY
  url = "#{STEAM_API_URL}/#{endpoint}/v#{version}/?#{urlparams params}"
  data, url, res = simplehttp(url)
  if not data or not res or res.status_code ~= 200
    ivar2:Log "error", "steam: invalid HTTP for #{endpoint} (status #{res and res.status_code})"
    return nil
  json.decode(data)

GetMatchHistory = (steamID) ->
    params =
        account_id: steamID
        matches_requested: tostring(DOTA_MAX_RESULTS)
    object = GetSteamResult "IDOTA2Match_570/GetMatchHistory", params
    if object.result.status == 15
      reply "The user has disabled the \"Expose Public Match Data\" option."
      return
    else if object.result.num_results == 0
      reply "No game matches were found for the #{type}: #{genericID}."
      return
    return object

'PRIVMSG':
  '^%psteam (.*)$': (source, destination, arg) =>
    data = GetSteamResult('ISteamUser/ResolveVanityURL', {vanityURL:arg})
    steamID = data.response.steamid
    unless steamID
      return say 'Not valid vanity URL'


    data = GetSteamResult "ISteamUser/GetPlayerSummaries", steamids: steamID, '0002'
    _, player = next data.response.players
    say json.encode(player)
    name = player.personaname
    -- 'https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?steamid=76561197965200144&key=896D786E7A4267C651559D0D6960CC19'

    data = GetMatchHistory(steamID)

    --say json.encode(data)


