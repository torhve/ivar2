-- Watch the Hugging Face hub for new repos from an author, and for changes to
-- specific tracked repos. Uses the public hub API, not the HTML pages:
--   https://huggingface.co/api/models?author=Qwen&sort=createdAt&direction=-1&limit=N
--   https://huggingface.co/api/models/Qwen/Qwen3-4B
local util = require("util")
local simplehttp = util.simplehttp
local json = util.json

local moduleName = "huggingface"
local store = ivar2.persist
local conf = ivar2.config[moduleName] or {}

-- Every line this module says starts with the same tag, it is what people scan for
-- this is the hugging face emoji
local tag = "[\240\159\164\151]"

local authors = conf.authors or { "Qwen" }
local limit = conf.limit or 25
local interval = conf.interval or 900
local maxAnnounce = conf.maxAnnounce or 5
local reportCount = conf.reportCount or 3
local watchDatasets = conf.datasets or false
-- Announce only repos matching one of these case insensitive patterns, "!hf only qwen"
local onlyPatterns = conf.only or nil
-- Only explicitly tracked repos get update pings, an authors list would spam them
local announceUpdates = conf.announceUpdates ~= false

local seenKey = moduleName .. ":seen"
local chanKey = moduleName .. ":channels"
local repoKey = moduleName .. ":repos"
local onlyKey = moduleName .. ":only"
local authorKey = moduleName .. ":authors"

local listurl = "https://huggingface.co/api/%s?author=%s&sort=createdAt&direction=-1&limit=%d"
	.. "&expand%%5B%%5D=createdAt&expand%%5B%%5D=lastModified&expand%%5B%%5D=downloads&expand%%5B%%5D=likes"
	.. "&expand%%5B%%5D=pipeline_tag&expand%%5B%%5D=tags&expand%%5B%%5D=private&expand%%5B%%5D=disabled"
local repourl = "https://huggingface.co/api/%s/%s"
local searchurl = "https://huggingface.co/api/models?search=%s&sort=createdAt&direction=-1&limit=%d"

-- say() is only defined on the handler function the dispatcher matched, so every
-- helper here talks through ivar2:Msg and gets the tag added in one place
local emit = function(destination, source, fmt, ...)
	if select("#", ...) > 0 then
		fmt = string.format(fmt, ...)
	end
	return ivar2:Msg("privmsg", destination, source, tag .. " " .. fmt)
end

local date = function(stamp)
	return (stamp or ""):match("^(%d%d%d%d%-%d%d%-%d%d)") or "undated"
end

-- Channels from config plus whatever was opted in with "!hf on"
local channels = function()
	local out, seen = {}, {}
	for _, list in ipairs({ conf.channels or {}, store[chanKey] or {} }) do
		for _, chan in ipairs(list) do
			if type(chan) == "string" and not seen[chan] then
				seen[chan] = true
				out[#out + 1] = chan
			end
		end
	end
	return out
end

local saveChannels = function(list)
	store[chanKey] = list
end

-- Repos from config plus whatever was added with "!hf track <org>/<repo>"
local trackedRepos = function()
	local out, seen = {}, {}
	for _, list in ipairs({ conf.repos or {}, store[repoKey] or {} }) do
		for _, repo in ipairs(list) do
			if type(repo) == "string" and repo:match("^[%w%.%-%_]+/[%w%.%-%_]+$") and not seen[repo] then
				seen[repo] = true
				out[#out + 1] = repo
			end
		end
	end
	return out
end

local isRepoTracked = function(repo)
	for _, tracked in ipairs(trackedRepos()) do
		if tracked:lower() == repo:lower() then
			return true
		end
	end
	return false
end

local isListening = function(destination)
	for _, chan in ipairs(channels()) do
		if chan:lower() == destination:lower() then
			return true
		end
	end
	return false
end

local fetchJson = function(url)
	local data, _, response = simplehttp({ url = url, headers = { Accept = "application/json" } })
	if not data then
		return ivar2:Log("error", "%s: no data from %s", moduleName, url)
	end
	if response and response.status_code and response.status_code ~= 200 then
		return ivar2:Log("error", "%s: HTTP %s from %s", moduleName, tostring(response.status_code), url)
	end
	local ok, decoded = pcall(json.decode, data)
	if not ok or type(decoded) ~= "table" then
		return ivar2:Log("error", "%s: bad json from %s: %s", moduleName, url, tostring(decoded))
	end
	return decoded
end

local normalize = function(m, kind)
	if type(m) ~= "table" or type(m.id) ~= "string" or m.private or m.disabled then
		return nil
	end
	return {
		kind = kind,
		id = m.id,
		createdAt = m.createdAt or "",
		lastModified = m.lastModified or "",
		downloads = m.downloads,
		likes = m.likes,
		pipeline = m.pipeline_tag,
	}
end

-- Quants and fine tunes name their parent in the tags, base_model:quantized:Qwen/Qwen3.5-4B
-- The list endpoint has tags, the repo endpoint has cardData, no extra request needed
local baseModelOf = function(m)
	local fallback
	for _, t in ipairs(m.tags or {}) do
		if type(t) == "string" then
			local quantized = t:match("^base_model:quantized:(.+)$")
			if quantized then
				return quantized
			end
			if not fallback then
				fallback = t:match("^base_model:(.+)$")
			end
		end
	end
	if not fallback and type(m.cardData) == "table" and type(m.cardData.base_model) == "string" then
		fallback = m.cardData.base_model
	end
	if not fallback then
		return nil
	end
	return (fallback:gsub("^finetune:", ""):gsub("^quantized:", ""))
end

local kinds = function()
	local out = { "models" }
	if watchDatasets then
		out[#out + 1] = "datasets"
	end
	return out
end

local collectAuthor = function(author)
	local out = {}
	for _, kind in ipairs(kinds()) do
		local models = fetchJson(listurl:format(kind, author, limit))
		if models then
			for _, m in ipairs(models) do
				local model = normalize(m, kind)
				if model then
					model.base = baseModelOf(m)
					out[#out + 1] = model
				end
			end
		end
	end
	return out
end

-- Model first, dataset second: the hub does not say which one a repo is
local collectRepo = function(repo)
	for _, kind in ipairs(kinds()) do
		local raw = fetchJson(repourl:format(kind, repo))
		local model = normalize(raw, kind)
		if model then
			model.base = baseModelOf(raw)
			return model
		end
	end
	return nil
end

local announce = function(m, updated)
	local info = {}
	if m.pipeline then
		info[#info + 1] = m.pipeline
	end
	if m.downloads then
		info[#info + 1] = string.format("%d dl", m.downloads)
	end
	if m.likes then
		info[#info + 1] = string.format("%d like", m.likes)
	end
	if m.base and m.base ~= m.id then
		info[#info + 1] = "of " .. m.base
	end
	-- The sorted by createdAt listing omits lastModified, the repo endpoint has it
	local when = (m.lastModified ~= "" and m.lastModified) or m.createdAt
	return string.format(
		"%s %s %s \2%s\2  %s  %s https://huggingface.co/%s",
		tag,
		updated and "updated" or "new",
		(m.kind == "datasets") and "dataset" or "model",
		m.id,
		table.concat(info, " "),
		date(when),
		m.id
	)
end

local sayAnnounce = function(m, updated)
	for _, chan in ipairs(channels()) do
		ivar2:Msg("privmsg", chan, ivar2.nick, announce(m, updated))
	end
end

-- "!hf only <pattern>" narrows what gets announced, everything is still remembered as seen
local only = function()
	return store[onlyKey] or onlyPatterns or {}
end

local matchesOnly = function(m)
	local list = only()
	if #list == 0 then
		return true
	end
	for _, pattern in ipairs(list) do
		pattern = pattern:lower()
		if m.id:lower():match(pattern) then
			return true
		end
		if m.base and m.base:lower():match(pattern) then
			return true
		end
	end
	return false
end

-- Orgs from config plus whatever was added with "!hf track <org>"
local watchedAuthors = function()
	local out, seen = {}, {}
	for _, list in ipairs({ authors, store[authorKey] or {} }) do
		for _, author in ipairs(list) do
			if type(author) == "string" and not seen[author:lower()] then
				seen[author:lower()] = true
				out[#out + 1] = author
			end
		end
	end
	return out
end

local isTrackedAuthor = function(author)
	for _, stored in ipairs(store[authorKey] or {}) do
		if stored:lower() == author:lower() then
			return true
		end
	end
	return false
end

local isConfigAuthor = function(author)
	for _, configured in ipairs(authors) do
		if configured:lower() == author:lower() then
			return true
		end
	end
	return false
end

local authorExists = function(author)
	for _, kind in ipairs(kinds()) do
		local models = fetchJson(listurl:format(kind, author, 1))
		if models and #models > 0 then
			return true
		end
	end
	return false
end
local poll = function()
	local models = {}
	local tracked, trackedList = {}, trackedRepos()
	for _, repo in ipairs(trackedList) do
		tracked[repo] = true
	end

	for _, author in ipairs(watchedAuthors()) do
		for _, model in ipairs(collectAuthor(author)) do
			models[#models + 1] = model
		end
	end
	for _, repo in ipairs(trackedList) do
		local model = collectRepo(repo)
		if model then
			models[#models + 1] = model
		end
	end

	-- A tracked repo is usually also in an author listing, keep one entry with the richest fields
	local unique, byId = {}, {}
	for _, model in ipairs(models) do
		local known = byId[model.id]
		if not known then
			byId[model.id] = model
			unique[#unique + 1] = model
		else
			if model.lastModified > known.lastModified then
				known.lastModified = model.lastModified
			end
			if not known.base and model.base then
				known.base = model.base
			end
			if not known.pipeline and model.pipeline then
				known.pipeline = model.pipeline
			end
		end
	end
	models = unique

	-- Nothing came back, assume API trouble and leave the stored state alone
	if #models == 0 then
		return nil
	end

	local seen = store[seenKey]
	if not seen then
		-- First run: learn what already exists instead of flooding the channel
		seen = {}
		for _, m in ipairs(models) do
			seen[m.id] = m.lastModified
		end
		store[seenKey] = seen
		ivar2:Log("info", "%s: seeded %d known repos.", moduleName, #models)
		return models, {}, {}
	end

	local fresh, changed = {}, {}
	for _, m in ipairs(models) do
		if not seen[m.id] then
			fresh[#fresh + 1] = m
		elseif announceUpdates and tracked[m.id] and seen[m.id] ~= "" and seen[m.id] ~= m.lastModified then
			changed[#changed + 1] = m
		end
		seen[m.id] = m.lastModified
	end
	store[seenKey] = seen

	table.sort(fresh, function(a, b)
		return a.createdAt < b.createdAt
	end)
	local loud = {}
	for _, m in ipairs(fresh) do
		if matchesOnly(m) then
			loud[#loud + 1] = m
		end
	end
	if #loud > 0 then
		for _, chan in ipairs(channels()) do
			for i, m in ipairs(loud) do
				if i <= maxAnnounce then
					ivar2:Msg("privmsg", chan, ivar2.nick, announce(m, false))
				else
					ivar2:Msg("privmsg", chan, ivar2.nick, string.format("%s ... and %d more", tag, #loud - maxAnnounce))
					break
				end
			end
		end
	end

	table.sort(changed, function(a, b)
		return a.lastModified < b.lastModified
	end)
	for _, m in ipairs(changed) do
		if matchesOnly(m) then
			sayAnnounce(m, true)
		end
	end

	return models, loud, changed
end

-- Timer started at load time, same style as modules/rss.moon
ivar2:Timer(moduleName, interval, interval, poll)

local report = function(destination, source, models, label, note)
	table.sort(models, function(a, b)
		return a.createdAt > b.createdAt
	end)
	local out = {}
	for i = 1, math.min(reportCount, #models) do
		local m = models[i]
		out[#out + 1] = string.format("%s (%s)", m.id, date(m.createdAt))
	end
	if #out == 0 then
		return emit(destination, source, "%s: nothing found for %s.", source.nick, label)
	end
	return emit(destination, source, "%s: %s%s", source.nick, table.concat(out, ", "), note or "")
end

local repoReport = function(destination, source, model)
	if not model then
		return emit(destination, source, "%s: no such repo.", source.nick)
	end
	local info = {}
	if model.pipeline then
		info[#info + 1] = model.pipeline
	end
	if model.downloads then
		info[#info + 1] = string.format("%d dl", model.downloads)
	end
	if model.likes then
		info[#info + 1] = string.format("%d like", model.likes)
	end
	if model.base and model.base ~= model.id then
		info[#info + 1] = "of " .. model.base
	end
	return emit(
		destination,
		source,
		"%s: %s \2%s\2  new %s  pushed %s  %s  https://huggingface.co/%s",
		source.nick,
		(model.kind == "datasets") and "dataset" or "model",
		model.id,
		date(model.createdAt),
		date(model.lastModified),
		table.concat(info, " "),
		model.id
	)
end

-- "!hf" polls now and reports the newest repos of the configured authors
local command = function(self, source, destination)
	local models, fresh, changed = poll()
	if not models then
		return emit(destination, source, "%s: the hub api gave nothing.", source.nick)
	end
	local note = ""
	if #fresh > 0 or #changed > 0 then
		note = string.format("  %d new, %d updated", #fresh, #changed)
	end
	return report(destination, source, models, table.concat(watchedAuthors(), "/"), note)
end

-- "!hf <query>" is a read only lookup, it does not touch the polling state
local lookup = function(self, source, destination, query)
	if query:match("^[%w%.%-%_]+/[%w%.%-%_]+$") then
		return repoReport(destination, source, collectRepo(query))
	end
	local models = collectAuthor(query)
	if #models == 0 then
		return emit(destination, source, "%s: nothing found for %s.", source.nick, query)
	end
	return report(destination, source, models, query)
end

local enable = function(self, source, destination)
	if isListening(destination) then
		return emit(destination, source, "%s: already listening here.", source.nick)
	end
	local list = store[chanKey] or {}
	list[#list + 1] = destination
	saveChannels(list)
	return emit(
		destination,
		source,
		"%s: announcing new %s repos here.",
		source.nick,
		table.concat(watchedAuthors(), "/")
	)
end

local disable = function(self, source, destination)
	local out, removed = {}, false
	for _, chan in ipairs(store[chanKey] or {}) do
		if chan:lower() == destination:lower() then
			removed = true
		else
			out[#out + 1] = chan
		end
	end
	saveChannels(out)
	if removed then
		return emit(destination, source, "%s: stopped announcing here.", source.nick)
	end
	return emit(destination, source, "%s: was not listening here.", source.nick)
end

-- "!hf track unsloth" watches a whole org, "!hf track unsloth/Qwen3-4B" watches one repo
local track = function(self, source, destination, target)
	if target:match("^[%w%.%-%_]+/[%w%.%-%_]+$") then
		if isRepoTracked(target) then
			return emit(destination, source, "%s: already tracking %s.", source.nick, target)
		end
		if not collectRepo(target) then
			return emit(destination, source, "%s: %s is not a model or dataset I can see.", source.nick, target)
		end
		local list = store[repoKey] or {}
		list[#list + 1] = target
		store[repoKey] = list
		return emit(destination, source, "%s: tracking %s, updates announced here.", source.nick, target)
	end

	if not target:match("^[%w%.%-%_]+$") then
		return emit(destination, source, "%s: !hf track unsloth or !hf track unsloth/Qwen3-4B", source.nick)
	end
	if isTrackedAuthor(target) then
		return emit(destination, source, "%s: already watching %s.", source.nick, target)
	end
	if isConfigAuthor(target) then
		return emit(destination, source, "%s: %s is already in the config, watching it.", source.nick, target)
	end
	if not authorExists(target) then
		return emit(destination, source, "%s: no models or datasets from %s.", source.nick, target)
	end

	local list = store[authorKey] or {}
	list[#list + 1] = target
	store[authorKey] = list

	-- Learn what that org already has first, otherwise the next poll dumps twenty lines
	local known, seeded = collectAuthor(target), 0
	local seen = store[seenKey]
	if seen then
		for _, m in ipairs(known) do
			if not seen[m.id] then
				seen[m.id] = m.lastModified
				seeded = seeded + 1
			end
		end
		store[seenKey] = seen
	end
	return emit(
		destination,
		source,
		"%s: watching %s, %d existing repos seeded, new ones announced here.",
		source.nick,
		target,
		seeded
	)
end

local untrack = function(self, source, destination, target)
	local key, noun = repoKey, "tracking"
	if not target:match("^[%w%.%-%_]+/[%w%.%-%_]+$") then
		if isConfigAuthor(target) then
			return emit(destination, source, "%s: %s comes from the config, remove it there.", source.nick, target)
		end
		key, noun = authorKey, "watching"
	end
	local out, removed = {}, false
	for _, entry in ipairs(store[key] or {}) do
		if entry:lower() == target:lower() then
			removed = true
		else
			out[#out + 1] = entry
		end
	end
	store[key] = out
	if removed then
		return emit(destination, source, "%s: stopped %s %s.", source.nick, noun, target)
	end
	return emit(destination, source, "%s: was not %s %s.", source.nick, noun, target)
end

local listing = function(self, source, destination)
	-- Which channels are opted in is not repeated here, other channels should not learn about it
	local repos = trackedRepos()
	return emit(
		destination,
		source,
		"%s: authors %s  repos %s  announcing here %s  filter %s",
		source.nick,
		table.concat(watchedAuthors(), "/"),
		#repos > 0 and table.concat(repos, ", ") or "none",
		isListening(destination) and "yes" or "no",
		#only() > 0 and table.concat(only(), ", ") or "off"
	)
end

-- "!hf only <pattern>" trims a noisy author, "!hf only all" undoes it
local onlyCommand = function(self, source, destination, rest)
	if rest == "" then
		local list = only()
		return emit(
			destination,
			source,
			"%s: announcing %s.",
			source.nick,
			#list > 0 and table.concat(list, ", ") or "everything"
		)
	end
	if rest == "all" then
		store[onlyKey] = nil
		return emit(
			destination,
			source,
			"%s: announcing everything from %s.",
			source.nick,
			table.concat(watchedAuthors(), "/")
		)
	end
	store[onlyKey] = { rest }
	return emit(destination, source, "%s: announcing repos matching %s.", source.nick, rest)
end

-- "!hf deriv Qwen/Qwen3.5-4B" finds the quants and fine tunes built on a repo
local derivatives = function(self, source, destination, repo)
	if not repo:match("^[%w%.%-%_]+/[%w%.%-%_]+$") then
		return emit(destination, source, "%s: needs a repo, !hf deriv Qwen/Qwen3-4B", source.nick)
	end
	local found = fetchJson(searchurl:format(util.urlEncode(repo), limit))
	if not found then
		return emit(destination, source, "%s: the hub api gave nothing.", source.nick)
	end

	local out = {}
	for _, entry in ipairs(found) do
		local model = normalize(entry, "models")
		if model then
			model.base = baseModelOf(entry)
			if model.base and model.base:lower() == repo:lower() then
				out[#out + 1] = model
			end
		end
	end
	if #out == 0 then
		return emit(destination, source, "%s: no repos name %s as their base model.", source.nick, repo)
	end

	table.sort(out, function(a, b)
		return a.createdAt > b.createdAt
	end)
	local names = {}
	for i = 1, math.min(reportCount, #out) do
		names[i] = string.format("%s (%s)", out[i].id, date(out[i].createdAt))
	end
	return emit(destination, source, "%s: %d repos built on %s  %s", source.nick, #out, repo, table.concat(names, ", "))
end

local reset = function(self, source, destination)
	store[seenKey] = nil
	return emit(destination, source, "%s: state cleared, next poll re-seeds.", source.nick)
end

local help = function(self, source, destination)
	return emit(
		destination,
		source,
		"%s: !hf polls and lists the newest. !hf <author> | !hf <org>/<repo> | !hf deriv <repo>. "
			.. "!hf on|off here, !hf track|untrack <org> or <org>/<repo>, !hf only <pattern>, !hf list, !hf reset.",
		source.nick
	)
end

local subcommands = {
	["on"] = enable,
	["off"] = disable,
	["list"] = listing,
	["reset"] = reset,
	["help"] = help,
	["only"] = onlyCommand,
	["deriv"] = derivatives,
	["quants"] = derivatives,
}

-- Both spellings, "!hf" is the one people will actually type
local handlers = {}
for _, trigger in ipairs({ "hf", "huggingface" }) do
	handlers["^" .. "%p" .. trigger .. "$"] = command
	handlers["^" .. "%p" .. trigger .. " (.+)$"] = function(self, source, destination, arg)
		local sub, rest = arg:match("^(%S+)%s*(.*)$")
		if sub == "track" or sub == "untrack" then
			if rest == "" then
				return emit(destination, source, "%s: !hf %s <org>/<repo>", source.nick, sub)
			end
			if sub == "track" then
				return track(self, source, destination, rest)
			end
			return untrack(self, source, destination, rest)
		end
		local handler = subcommands[sub]
		if handler then
			return handler(self, source, destination, rest)
		end
		return lookup(self, source, destination, arg)
	end
end

return {
	PRIVMSG = handlers,
}
