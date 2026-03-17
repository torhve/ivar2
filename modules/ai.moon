util = require 'util'
simplehttp = util.simplehttp
json = util.json
date = require 'date'
urlEncode = util.urlEncode

key = ivar2.config.googleaiApiKey
nick = ivar2.config.nick
model = "gemini-2.5-flash"

history = {}

unEscape = (input) ->
  -- Replace javascript escape codes with lua formatted strings safely
  luaString = input\gsub "\\x(%x%x)", (hex) ->
    string.char tonumber(hex, 16)
  luaString = luaString\gsub "\\u(%x%x%x%x)", (hex) ->
    string.char tonumber(hex, 16)
  luaString

chat = (source, destination, a, google_search=true) =>

  sys_instruct = "Persona: You are #{nick}, a witty, slightly sarcastic IRC bot. "
  sys_instruct ..= "Context: The time is #{os.date('!%Y-%m-%dT%TZ')} (Europe/Oslo). User is #{source.nick}. "
  sys_instruct ..= "Task: Answer concisely (under 400 chars). Use IRC formatting (\x02bold\x02, \x0304color\x03, \x1funderline\x1f) for emphasis. "
  sys_instruct ..= "Constraint: If the query is nonsense, be snarky. Never use Markdown code blocks or JSON escaping. Output raw text only."

  pdata = {
    safetySettings: {
      {category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_ONLY_HIGH"}
      {category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_ONLY_HIGH"}
      {category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_ONLY_HIGH"}
      {category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_ONLY_HIGH"}
      {category: "HARM_CATEGORY_CIVIC_INTEGRITY", threshold: "BLOCK_ONLY_HIGH"}
    }
    contents: {
      parts: {
        { text: a }
      }
    }
    system_instruction: {
      parts: {
        { text: sys_instruct }
      }
    }
  }

  if google_search
    pdata.tools = {
      { google_search: {} }
    }

  pdata_json = json.encode(pdata)
  url = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{key}"

  got_reply = false

  if google_search
    -- Added some randomness to the timer name to prevent collisions if multiple queries happen at once
    ivar2\Timer "ai_#{os.time!}_#{math.random(1000)}", 7, false, ->
      unless got_reply
        ivar2\Log 'debug', 'No reply from API, poking again without google search'
        chat(@, source, destination, a, false)

  simplehttp {url: url, method: 'POST', data: pdata_json, headers: {['content-type']: "application/json"}}, (data) ->
    got_reply = true

    -- 1. Check if the HTTP request failed entirely
    unless data
      return reply "Error: Could not reach the API. The internet tubes might be clogged."

    ivar2\Log 'debug', data

    -- 2. Safely decode JSON so invalid responses don't crash the bot
    status, decoded = pcall json.decode, data
    unless status and decoded
      return reply "Error: The API returned garbled nonsense (Invalid JSON)."

    -- 3. Check for API-level errors (e.g., Quota exceeded, bad request)
    if decoded.error
      err_msg = decoded.error.message or 'Unknown error'

      return reply "API Error: #{err_msg}"

    -- 4. Check if the model blocked the response or returned empty
    unless decoded.candidates and decoded.candidates[1] and decoded.candidates[1].content
      if decoded.promptFeedback and decoded.promptFeedback.blockReason
        return reply "Error: Blocked by safety settings (#{decoded.promptFeedback.blockReason})."

      return reply "Error: The API returned an empty response. It might be confused."

    out = {}
    for i, part in ipairs decoded.candidates[1].content.parts
      if part.text -- Sometimes parts can be function calls rather than text
        res = unEscape part.text
        res = util.trim res
        table.insert out, res

    reply table.concat(out, ' ')

askLast = (source, destination, a) =>
  -- Ensure we actually have history to prevent a crash
  unless history[destination] and #history[destination] > 1
    return ivar2\Say destination, "I don't have enough history to look at yet!"

  lastEntry = history[destination][#history[destination] - 1]
  lastNick = lastEntry[1]
  lastLine = lastEntry[2]
  chat(@, {nick: lastNick}, destination, lastLine)

summary = (source, destination, url) =>
  unless history[destination] and #history[destination] > 1
    return ivar2\Say destination, "I don't have enough history to summarize!"

  lastEntry = history[destination][#history[destination] - 1]
  lastLine = lastEntry[2]

  simplehttp lastLine, (data) ->
    unless data
      return ivar2\Say destination, "Error: Could not fetch that URL."

    -- Optional: truncate data so you don't blow out the API payload limit on huge pages
    truncated_data = data\sub 1, 15000
    prompt = "Summarize the following HTML document: \n\n" .. truncated_data

    chat(@, source, destination, prompt)

PRIVMSG: {
  '^%pai (.*)$': chat
  '^%pai$': askLast
  '^%psummary$': summary
  (source, destination, argument) =>
    max_lines = 5
    history[destination] or= {}
    table.insert history[destination], {source.nick, argument}
    if #history[destination] > max_lines
      table.remove history[destination], 1
}