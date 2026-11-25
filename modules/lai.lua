-- local AI module: chat / URL summarization / image generation via a
-- llama-swap OpenAI-compatible API (Bearer auth, /v1/... paths).
-- Owns: !lai (chat w/ web-search tool calling + history), !summary (URL
-- summarize), !aimage (image generation/edit).

local util = require("util")
local simplehttp = util.simplehttp
local json = util.json
local htmltext = require("htmltext")
local base64 = require("base64")
local lfs = require("lfs")

local endpoint = ivar2.config.llmEndpoint or "http://localhost:8080"
local apikey = ivar2.config.llmApiKey
local chat_model = ivar2.config.llmModel or "gemma4-text"
local image_model = ivar2.config.imageModel or "qwen-image-turbo"
local IMAGES_DIR = "cache/images"
local TIMEOUT = 180

if not apikey then
	ivar2:Log("warn", "lai module: llmApiKey not set in config")
end

if not lfs.attributes(IMAGES_DIR) then
	lfs.mkdir(IMAGES_DIR)
end

local history = {}

local function headers()
	local h = { ["Content-Type"] = "application/json" }
	if apikey then
		h["Authorization"] = "Bearer " .. apikey
	end
	return h
end

-- DuckDuckGo web search: fetch HTML page, extract result links
local function ddg_search(query, callback)
	local encoded = util.urlEncode(query)
	simplehttp("https://duckduckgo.com/?q=" .. encoded .. "&ia=web&caf=%E7%81%AB", function(data, _uri, _resp)
		if not data then
			return callback(nil)
		end

		local results = {}
		for href in string.gmatch(data, '<a[^>]+href="(/[^"]+)"') do
			if string.match(href, "^/") and not string.match(href, "^/abc") and not string.match(href, "^/[a-z]+") then
				local full_url = "https://duckduckgo.com" .. href
				local title_part = string.sub(href, 2)
				local dot_pos = string.find(title_part, ".")
				if dot_pos then
					title_part = string.sub(title_part, 1, dot_pos - 1)
				end
				local title_match = string.gsub(title_part, "%-", " ")
				table.insert(results, { url = full_url, title = title_match })
			end
		end

		if #results == 0 then
			return callback('No results found for "' .. query .. '".')
		end

		if #results > 3 then
			results = { results[1], results[2], results[3] }
		end

		local fetched = {}
		local remaining = #results
		for _, r in ipairs(results) do
			simplehttp({ url = r.url, timeout = 30 }, function(page_data)
				remaining = remaining - 1
				if page_data and #page_data > 0 then
					local text = htmltext.extract(page_data, { max_length = 1500, min_chunk_size = 15 })
					if #text > 0 then
						table.insert(fetched, r.title .. ": " .. text)
					end
				end
				if remaining == 0 then
					if #fetched == 0 then
						callback("Could not fetch any pages from search results.")
					else
						callback(table.concat(fetched, "\n\n"))
					end
				end
			end)
		end

		ivar2:Timer("ddg_fetch_timeout_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000)), 45, false, function()
			if remaining > 0 then
				remaining = 0
				if #fetched == 0 then
					callback("Timed out fetching search results.")
				else
					callback(table.concat(fetched, "\n\n"))
				end
			end
		end)
	end)
end

local function execute_web_search(args, callback)
	local query = args and args.query or ""
	if #query == 0 then
		return callback("Empty search query.")
	end
	ddg_search(query, callback)
end

-- Chat with web-search tool calling, OpenAI /v1/chat/completions
local function llm_chat(source, destination, query, do_search)
	if not apikey then
		return ivar2:Reply(destination, source, "Local AI is not configured (missing llmApiKey).")
	end

	local messages = history[destination] or {}
	messages[#messages + 1] = { role = "user", content = query }
	history[destination] = messages

	local tools = nil
	if do_search then
		tools = { {
			type = "function",
			["function"] = {
				name = "web_search",
				description = "Search the web for current information about a topic. " ..
					"Use when you need up-to-date facts, recent events, or information you might not know.",
				parameters = {
					type = "object",
					properties = {
						query = {
							type = "string",
							description = "The search query",
						},
					},
					required = { "query" },
				},
			},
		} }
	end

	local got_reply = false

	local send_chat
	local handle_response

	send_chat = function(msgs, t)
		local pdata = { model = chat_model, messages = msgs, stream = false }
		if t then pdata.tools = t end
		simplehttp({
			url = endpoint .. "/v1/chat/completions",
			method = "POST",
			data = json.encode(pdata),
			headers = headers(),
			timeout = TIMEOUT,
		}, function(data)
			handle_response(data, msgs, t)
		end)
	end

	handle_response = function(data, msgs, t)
		if got_reply then return end

		if not data then
			got_reply = true
			return ivar2:Reply(destination, source, "Error: Could not reach the local AI service. Is it running?")
		end

		ivar2:Log("debug", "Local AI response: %s", data:sub(1, 500))

		local status, decoded = pcall(json.decode, data)
		if not status or not decoded then
			got_reply = true
			ivar2:Log("debug", "Invalid JSON from local AI: %s", data:sub(1, 500))
			return ivar2:Reply(destination, source, "Error: The local AI returned invalid JSON.")
		end

		if decoded.error then
			got_reply = true
			local msg = type(decoded.error) == "string" and decoded.error or (decoded.error.message or "Unknown error")
			return ivar2:Reply(destination, source, "Local AI Error: " .. msg)
		end

		local choice = decoded.choices and decoded.choices[1]
		local msg = choice and choice.message
		if not msg then
			got_reply = true
			return ivar2:Reply(destination, source, "Error: Empty response from the local AI.")
		end

		if msg.tool_calls and #msg.tool_calls > 0 then
			got_reply = false
			table.insert(msgs, msg)

			local tool_results = {}
			local pending = #msg.tool_calls
			for _, tc in ipairs(msg.tool_calls) do
				local fname = tc["function"] and tc["function"].name
				local fargs_raw = tc["function"] and tc["function"].arguments or "{}"
				if fargs_raw == nil then fargs_raw = "{}" end

				local fargs
				if type(fargs_raw) == "table" then
					fargs = fargs_raw
				else
					local fargs_ok, decoded_args = pcall(json.decode, fargs_raw)
					fargs = (fargs_ok and type(decoded_args) == "table") and decoded_args or { query = "" }
				end

				if fname == "web_search" then
					execute_web_search(fargs, function(result)
						table.insert(tool_results, { role = "tool", tool_call_id = tc.id or "missing", content = result })
						pending = pending - 1
						if pending == 0 then
							for _, tr in ipairs(tool_results) do
								table.insert(msgs, tr)
							end
							send_chat(msgs, t)
						end
					end)
				else
					ivar2:Log("warn", "Unknown tool: %s", tostring(fname))
					pending = pending - 1
					if pending == 0 then
						for _, tr in ipairs(tool_results) do
							table.insert(msgs, tr)
						end
						send_chat(msgs, t)
					end
				end
			end

			ivar2:Timer("lai_tool_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000)), 60, false, function()
				if pending > 0 then
					pending = 0
					for _, tr in ipairs(tool_results) do
						table.insert(msgs, tr)
					end
					if #tool_results == 0 then
						table.insert(msgs, { role = "tool", tool_call_id = "missing", content = "Tool execution timed out." })
					end
					send_chat(msgs, t)
				end
			end)
		else
			got_reply = true
			table.insert(msgs, msg)
			history[destination] = msgs

			if #msgs > 10 then
				local trimmed = {}
				for i = #msgs - 9, #msgs do
					trimmed[#trimmed + 1] = msgs[i]
				end
				history[destination] = trimmed
			end

			local resp_text = util.trim(msg.content or "")
			if #resp_text > 0 then
				ivar2:Reply(destination, source, resp_text)
			else
				ivar2:Reply(destination, source, "Local AI returned an empty response.")
			end
		end
	end

	send_chat(history[destination], tools)

	ivar2:Timer("lai_fallback_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000)),
		TIMEOUT + 10, false, function()
		if not got_reply then
			got_reply = true
			ivar2:Log("debug", "Local AI request timed out after %ds", TIMEOUT)
			ivar2:Reply(destination, source, "Error: Local AI did not respond within " .. TIMEOUT .. " seconds.")
		end
	end)
end

--!summary / !lai <url>: fetch a page, extract text, summarize
local function llm_url(source, destination, url)
	if not url or not url:match("^https?://") then
		return ivar2:Reply(destination, source, "Error: Invalid URL. Expected http:// or https://.")
	end
	if not apikey then
		return ivar2:Reply(destination, source, "Local AI is not configured (missing llmApiKey).")
	end

	ivar2:Reply(destination, source, "Fetching and summarizing...")

	local got_reply = false

	ivar2:Timer("lai_url_fallback_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000)),
		TIMEOUT + 10, false, function()
		if not got_reply then
			got_reply = true
			ivar2:Reply(destination, source, "Error: Request timed out.")
		end
	end)

	simplehttp({ url = url, timeout = 30 }, function(page_data)
		if got_reply then return end
		if not page_data or #page_data == 0 then
			got_reply = true
			return ivar2:Reply(destination, source, "Error: Could not fetch that URL.")
		end

		local text = htmltext.extract(page_data, { max_length = 3000, min_chunk_size = 15 })
		if #text == 0 then
			got_reply = true
			return ivar2:Reply(destination, source, "Error: No extractable text found on that page.")
		end

		local msgs = { { role = "user", content = "Summarize this concisely (under 400 chars).\n\n" .. text } }
		local pdata = { model = chat_model, messages = msgs, stream = false }
		simplehttp({
			url = endpoint .. "/v1/chat/completions",
			method = "POST",
			data = json.encode(pdata),
			headers = headers(),
			timeout = TIMEOUT,
		}, function(data)
			if got_reply then return end
			if not data then
				got_reply = true
				return ivar2:Reply(destination, source, "Error: Could not reach the local AI service.")
			end

			local status, decoded = pcall(json.decode, data)
			if not status or not decoded then
				got_reply = true
				return ivar2:Reply(destination, source, "Error: The local AI returned invalid JSON.")
			end

			if decoded.error then
				got_reply = true
				local msg = type(decoded.error) == "string" and decoded.error or (decoded.error.message or "Unknown error")
				return ivar2:Reply(destination, source, "Local AI Error: " .. msg)
			end

			local choice = decoded.choices and decoded.choices[1]
			local msg = choice and choice.message
			if not msg then
				got_reply = true
				return ivar2:Reply(destination, source, "Error: Empty response from the local AI.")
			end

			got_reply = true
			local resp_text = util.trim(msg.content or "")
			if #resp_text > 0 then
				ivar2:Reply(destination, source, resp_text)
			else
				ivar2:Reply(destination, source, "Local AI returned an empty response.")
			end
		end)
	end)
end

local function ask_last_local(source, destination, _a)
	local msgs = history[destination]
	if not msgs or #msgs <= 1 then
		return ivar2:Say(destination, "No local AI history yet!")
	end
	for i = #msgs, 1, -1 do
		if msgs[i].role == "user" then
			return llm_chat(source, destination, msgs[i].content, true)
		end
	end
	return ivar2:Say(destination, "No previous questions found in local AI history.")
end

local function summary(source, destination, target)
	local target_url = target
	if target_url and target_url:match("^https?://") then
		return llm_url(source, destination, target_url)
	end

	local msgs = history[destination]
	if not msgs or #msgs <= 1 then
		return ivar2:Say(destination, "I don't have enough history to summarize!")
	end
	for i = #msgs, 1, -1 do
		local c = msgs[i] and msgs[i].content
		if c and c:match("^https?://") then
			return llm_url(source, destination, c)
		end
	end
	return ivar2:Say(destination, "No URL to summarize in local AI history yet!")
end

-- Image generation / edit
local function random_id()
	return tostring(math.random(100000, 999999))
end

local function save_image(b64data)
	local ok, decoded = pcall(base64.decode, b64data)
	if not ok then
		return "failed to decode the generated image."
	end

	local ts = os.time()
	local filename = string.format("%s-%s.png", tostring(ts), random_id())
	local filepath = string.format("%s/%s", IMAGES_DIR, filename)

	local f = io.open(filepath, "wb")
	if not f then
		return "failed to save the generated image."
	end
	f:write(decoded)
	f:close()

	local prefix = ivar2.config.webserverprefix or ""
	return string.format("%s/image/file/%s", prefix, filename)
end

local function generate_image(self, source, destination, prompt, imgdata)
	local done = false

	local payload
	if imgdata then
		payload = {
			model = image_model,
			image = imgdata,
			prompt = prompt,
			size = "2048x2048",
			strength = 0.6,
		}
	else
		payload = {
			model = image_model,
			prompt = prompt,
			size = "2048x2048",
			n = 1,
		}
	end

	local url = imgdata and endpoint .. "/v1/images/edits" or endpoint .. "/v1/images/generations"

	ivar2:Timer("lai_imagegen_timeout_" .. tostring(os.time()) .. "_" .. random_id(), TIMEOUT, false, function()
		if not done then
			done = true
			ivar2:Reply(destination, source, "service busy, try later.")
		end
	end)

	simplehttp({
		method = "POST",
		url = url,
		data = json.encode(payload),
		headers = headers(),
		timeout = TIMEOUT,
	}, function(data, _uri, response)
		if done then return end

		if not data then
			done = true
			return ivar2:Reply(destination, source, "could not reach the image service.")
		end

		local status = response and response.status_code

		if status == 401 then
			done = true
			return ivar2:Reply(destination, source, "authentication failed.")
		end

		if status == 400 then
			done = true
			local ok, err = pcall(json.decode, data)
			local msg = ok and err and (err.error and err.error.message or err.message or "Bad request") or "Bad request"
			return ivar2:Reply(destination, source, "API error: %s", msg)
		end

		if status == 500 then
			done = true
			return ivar2:Reply(destination, source, "generation failed, try again.")
		end

		if status ~= 200 then
			done = true
			return ivar2:Reply(destination, source, "unexpected response from the image service (status %d).", status or -1)
		end

		local ok, result = pcall(json.decode, data)
		if not ok or not result or not result.data or not result.data[1] or not result.data[1].b64_json then
			done = true
			return ivar2:Reply(destination, source, "invalid response from the image service.")
		end

		done = true
		ivar2:Msg("privmsg", destination, source, save_image(result.data[1].b64_json))
	end)
end

return {
	PRIVMSG = {
		["^%plai%s+(.+)$"] = function(self, source, destination, arg)
			arg = arg:gsub("^%s+", ""):gsub("%s+$", "")
			if arg:match("^https?://") then
				return llm_url(source, destination, arg)
			end
			return llm_chat(source, destination, arg, true)
		end,
		["^%plai$"] = function(self, source, destination)
			return ask_last_local(source, destination)
		end,
		["^%psummary%s+(.+)$"] = function(self, source, destination, arg)
			return summary(source, destination, arg)
		end,
		["^%psummary$"] = function(self, source, destination, _arg)
			return summary(source, destination, nil)
		end,
		["^%paimage (.+)$"] = function(self, source, destination, arg)
			arg = arg:gsub("^%s+", ""):gsub("%s+$", "")
			if #arg == 0 then
				return ivar2:Reply(destination, source, "please provide a prompt for image generation.")
			end

			if not apikey then
				return ivar2:Reply(destination, source, "image generation is not configured.")
			end

			local url = arg:match("https?://[^%s]+")
			if not url then
				return generate_image(self, source, destination, arg, nil)
			end

			local prompt = arg:gsub("https?://[^%s]+", ""):gsub("^%s+", ""):gsub("%s+$", "")
			if #prompt == 0 then
				return ivar2:Reply(destination, source, "please provide a prompt along with the image URL.")
			end

			ivar2:Say(destination, "downloading image from %s...", url)

			simplehttp({
				url = url,
				timeout = 30,
			}, function(imgdata)
				if not imgdata or #imgdata == 0 then
					return ivar2:Reply(destination, source, "could not download the image from that URL.")
				end

				local encoded = base64.encode(imgdata)
				generate_image(self, source, destination, prompt, encoded)
			end)
		end,
	},
}
