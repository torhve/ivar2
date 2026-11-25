local util = require("util")
local simplehttp = util.simplehttp
local json = util.json

local sessions = {}
local MAX_KEEP = 8 -- messages kept per session: system prompt + 7 recent (3-4 turns)
local MAX_RETRIES = 4
local BASE_DELAY = 2
local SYSTEM_PROMPT = "You are a human chatter on IRC, chatting in a channel with friends. Answer like a typical person on IRC: short, informal, one line only — no markdown, no lists, no greeting, no bot-sounding phrasing."

local function new_session()
	return { { role = "system", content = SYSTEM_PROMPT } }
end

local function session_key(nick, destination)
	return nick .. ":" .. tostring(destination or "")
end

local function get_session(key)
	if not sessions[key] then
		sessions[key] = new_session()
	end
	return sessions[key]
end

local function trim_session(session)
	while #session > MAX_KEEP do
		table.remove(session, 2) -- drop oldest conversation line, keep the system prompt
	end
end

local function respond(self, source, destination, text)
	self:Reply(destination, source, text)
end

local function fetch_with_retry(self, source, destination, skey, attempt_count)
	local session = get_session(skey)

	local payload = {
		model = ivar2.config.laiko_model,
		messages = session,
		chat_template_kwargs = { enable_thinking = true, reasoning_effort = "low" },
	}

	simplehttp({
		method = "POST",
		url = ivar2.config.laiko_api_url,
		data = json.encode(payload),
		headers = { ["Content-Type"] = "application/json" },
	}, function(response_body, url, response)
		if response and response.status_code == 200 then
			local response_data = json.decode(response_body)
			if response_data and response_data.choices and response_data.choices[1] and response_data.choices[1].message then
				local assistant_msg = response_data.choices[1].message.content
				local session = get_session(skey)
				table.insert(session, { role = "assistant", content = assistant_msg })
				trim_session(session)
				respond(self, source, destination, assistant_msg)
			else
				respond(self, source, destination, "Local AI returned a malformed response.")
			end
			elseif
				(response and (response.status_code == 429 or response.status_code == 503)) and attempt_count < MAX_RETRIES
			then
				local delay = BASE_DELAY * (2 ^ (attempt_count - 1))
				ivar2:Log("debug", "API is busy (%d), retrying in %ds", response.status_code, delay)
				self:Timer("_laiko_retry_" .. skey .. attempt_count, delay, function()
					fetch_with_retry(self, source, destination, skey, attempt_count + 1)
				end)
			elseif response and response.status_code >= 400 and response.status_code < 500 then
				local success, err_data = pcall(json.decode, response_body)
				local err_msg = success and err_data and err_data.error and err_data.error.message or "Bad Request"
				respond(self, source, destination, "Error: " .. err_msg)
				ivar2:Log("error", "API 400 response: %s", response_body)
			elseif response and (response.status_code == 429 or response.status_code == 503) then
				respond(self, source, destination, "API is busy, giving up.")
			else
				respond(
					self,
					source,
					destination,
					"Error: Failed to reach LLM API (Status: " .. tostring(response and response.status_code or "No response") .. ")."
				)
			end
		end)
end

local handler = function(self, source, destination, message)
	local nick = source.nick
	if not nick then
		return
	end

	local is_dm = destination == ivar2.config.nick
	local cmd_arg = nil

	if is_dm then
		-- Private message: strip the command prefix if present
		cmd_arg = message:match(ivar2.config.commandPattern .. "(.+)$") or message
	else
		-- Channel message: only answer if explicitly addressed to the bot
		local msg = message:match("^%s*(.-)%s*$")
		local prefix = ivar2.config.nick:lower() .. ":"
		if msg and msg:lower():sub(1, #prefix) == prefix then
			cmd_arg = msg:sub(#prefix + 1):match("^%s*(.-)%s*$")
		end
	end

	if not cmd_arg or #cmd_arg == 0 then
		return
	end

	local skey = session_key(nick, destination)

	-- Reset this conversation via !new command
	if cmd_arg == "new" then
		sessions[skey] = new_session()
		respond(self, source, destination, "Context reset.")
		return
	end

	-- One session per (user, conversation) — channel and DM stay separate
	local session = get_session(skey)
	table.insert(session, { role = "user", content = cmd_arg })
	trim_session(session)

	fetch_with_retry(self, source, destination, skey, 1)
end

return {
	PRIVMSG = {
		[".*"] = handler,
	},
}
