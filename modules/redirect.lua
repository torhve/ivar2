--- Self hosted redirect service, the replacement for the dead xt.gg/x0 shortener.
-- Registers <webserverprefix>/+<code> and hands out those links through ivar2.shorten().
local trim = require'util'.trim

local ROUTE = '^/%+(%w+)$'
local TTL = 60*60*24*30 -- Redirects point at signed CDN links that die anyway.

local BASE = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890'
local RADIX = #BASE
local MODULUS = 56800235584 -- RADIX ^ 6
local MULT = 7919 -- Coprime with MODULUS, so counters never collide.
local ADD = 1234567891

local encode
do
	local digits = {}
	for i=1, RADIX do
		digits[i] = BASE:sub(i, i)
	end

	encode = function(n)
		local out = {}
		repeat
			local rest = n % RADIX
			table.insert(out, 1, digits[rest + 1])
			n = (n - rest) / RADIX
		until n == 0
		return table.concat(out)
	end
end

local function newcode(count)
	return encode((count * MULT + ADD) % MODULUS)
end

local function add(url)
	local persist = ivar2.persist
	local count = (persist['redirect:count'] or 0) + 1
	persist['redirect:count'] = count

	local code = newcode(count)
	persist['redirect:' .. code] = {url = url, t = os.time()}

	return code
end

-- Drop redirects nobody can use any more (their target URLs have expired).
local function prune()
	local persist = ivar2.persist
	if(type(persist.keys) ~= 'function') then return end

	local now = os.time()
	local stale = {}
	for _, key in ipairs(persist:keys()) do
		local code = key:match('redirect:(%w+)$')
		if(code and code ~= 'count') then
			local entry = persist[key]
			if(type(entry) ~= 'table' or not entry.t or now - entry.t > TTL) then
				table.insert(stale, key)
			end
		end
	end

	for _, key in ipairs(stale) do
		persist[key] = nil
	end

	if(#stale > 0) then
		ivar2:Log('info', 'Redirect: pruned %d expired redirects.', #stale)
	end
end

ivar2.shorten = function(url, callback)
	local prefix = ivar2.config and ivar2.config.webserverprefix

	if(not (prefix and ivar2.webserver and ivar2.persist)) then
		-- Nowhere to point at, hand back the original.
		return callback(url)
	end

	local short = ('%s/+%s'):format(prefix:gsub('/+$', ''), add(trim(url)))
	callback(short)
end

local function redirect(self, req, res)
	local code = (req.url or ''):match(ROUTE)
	if(not code) then
		return 'Nyet. I am four oh four', 404
	end

	local entry = ivar2.persist['redirect:' .. code]
	if(type(entry) ~= 'table' or not entry.url) then
		return 'Nyet. I am four oh four', 404
	end

	entry.hits = (entry.hits or 0) + 1
	ivar2.persist['redirect:' .. code] = entry

	return 'Redirecting…', 302, {location = entry.url}
end

if(ivar2.webserver) then
	prune()
	ivar2.webserver.regUrl(ROUTE, redirect)
end
