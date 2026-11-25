util = require "util"
simplehttp = util.simplehttp
json = util.json

key = ivar2.config.googleaiApiKey
nick = ivar2.config.nick
model = "gemini-2.5-flash"

unless key
    ivar2\Log "warn", "ai module: googleaiApiKey not set in config"

history = {}

sys_instruct_prefix = "Persona: You are #{nick}, a witty, slightly sarcastic IRC bot. "
sys_instruct_prefix ..= "Task: Answer concisely (under 400 chars). Use IRC formatting for emphasis, when needed : "
sys_instruct_prefix ..= "\\x02 for bold,\\x1f for underline, and \\x03 followed by 2 digits for color (e.g., \\x0304 for red). "
sys_instruct_prefix ..= "Always end formatting with the reset code (\\x0f). "
sys_instruct_prefix ..= "Constraint: If the query is nonsense, be snarky. Never use Markdown code blocks. Output raw text only."

unEscape = (input) ->
    luaString = input\gsub "\\x(%x%x)", (hex) ->
        string.char tonumber(hex, 16)
    luaString = luaString\gsub "\\u(%x%x%x%x)", (hex) ->
        string.char tonumber(hex, 16)
    luaString

-- Gemini chat
geminiChat = (source, destination, a, google_search=true, url_context=false) =>
    time_str = os.date "!%Y-%m-%dT%TZ"
    sys_instruct = "Context: The time is #{time_str} (Europe/Oslo). User is #{source.nick}. #{sys_instruct_prefix}"

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
                {text: a}
            }
        }
        system_instruction: {
            parts: {
                {text: sys_instruct}
            }
        }
    }

    if google_search or url_context
        pdata.tools = {}
        if google_search
            table.insert pdata.tools, {google_search: {}}
        if url_context
            table.insert pdata.tools, {url_context: {}}

    pdata_json = json.encode(pdata)
    url = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{key}"

    got_reply = false

    handle_response = (data) ->
        if got_reply
            return
        got_reply = true

        unless data
            return ivar2\Reply destination, source, "Error: Could not reach the API. The internet tubes might be clogged."

        ivar2\Log "debug", "Gemini response: #{data\sub 1, 1000}"

        status, decoded = pcall json.decode, data
        unless status and decoded
            ivar2\Log "debug", "Invalid JSON from API: #{data\sub 1, 500}"
            return ivar2\Reply destination, source, "Error: The API returned garbled nonsense (Invalid JSON)."

        if decoded.error
            err_msg = decoded.error.message or "Unknown error"
            ivar2\Log "debug", "Gemini API error: #{err_msg}"
            return ivar2\Reply destination, source, "API Error: #{err_msg}"

        unless decoded.candidates and decoded.candidates[1] and decoded.candidates[1].content
            if decoded.promptFeedback and decoded.promptFeedback.blockReason
                return ivar2\Reply destination, source, "Error: Blocked by safety settings (#{decoded.promptFeedback.blockReason})."
            return ivar2\Reply destination, source, "Error: The API returned an empty response. It might be confused."

        if decoded.candidates[1].finishReason and decoded.candidates[1].finishReason == "MAX_TOKENS"
            ivar2\Log "debug", "Gemini response truncated by MAX_TOKENS"

        out = {}
        for i, part in ipairs decoded.candidates[1].content.parts
            if part.text
                res = unEscape part.text
                res = util.trim res
                table.insert out, res

        ivar2\Reply destination, source, table.concat(out, " ")

    req_timeout = 120

    if google_search
        ivar2\Timer "ai_#{os.time!}_#{math.random(1000)}", 17, false, ->
            unless got_reply
                ivar2\Log "debug", "No reply from API, poking again without google search"
                pdata.tools = nil
                simplehttp {url: url, method: "POST", data: json.encode(pdata), headers: {[("content-type")]: "application/json"}, timeout: req_timeout}, handle_response

    simplehttp {url: url, method: "POST", data: pdata_json, headers: {[("content-type")]: "application/json"}, timeout: req_timeout}, handle_response

    ivar2\Timer "ai_fallback_#{os.time!}_#{math.random(1000)}", req_timeout + 10, false, ->
        unless got_reply
            got_reply = true
            ivar2\Log "debug", "Gemini API request timed out after #{req_timeout}s"
            ivar2\Reply destination, source, "Error: The API did not respond within #{req_timeout} seconds."

-- Dispatcher: Gemini for !ai
chat = (source, destination, a, google_search=true, url_context=false) =>
    geminiChat @, source, destination, a, google_search, url_context

askLast = (source, destination, _a) =>
    unless history[destination] and #history[destination] > 1
        return ivar2\Say destination, "I don't have enough history to look at yet!"

    lastEntry = history[destination][#history[destination] - 1]
    lastNick = lastEntry[1]
    lastLine = lastEntry[2]
    chat @, {nick: lastNick}, destination, lastLine

PRIVMSG: {
    "^%pai (.*)$": chat
    "^%pai$": askLast
    (source, destination, argument) =>
        command_prefix = ivar2.config.commandPattern or "!"
        max_lines = 5
        history[destination] or= {}
        unless argument\match "^" .. command_prefix
            table.insert history[destination], {source.nick, argument}
            if #history[destination] > max_lines
                table.remove history[destination], 1

}
