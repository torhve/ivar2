-- this module piggybacks on the ircsnap web server - uses the same cache directory and letting that module serve images

local util = require("util")
local simplehttp = util.simplehttp
local json = util.json
local base64 = require("base64")
local lfs = require("lfs")

local endpoint = ivar2.config.openaiEndpoint or "http://localhost:8090"
local apikey = ivar2.config.openaiApiKey

if not apikey then
	ivar2:Log("warn", "imagegen: openaiApiKey not set in config")
end

local TIMEOUT = 180
local IMAGES_DIR = "cache/images"

if not lfs.attributes(IMAGES_DIR) then
	lfs.mkdir(IMAGES_DIR)
end

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
			model = "z-image-turbo",
			image = imgdata,
			prompt = prompt,
			size = "512x512",
			strength = 0.6,
		}
	else
		payload = {
			model = "z-image-turbo",
			prompt = prompt,
			size = "512x512",
			n = 1,
		}
	end

	local url = imgdata and endpoint .. "/v1/images/edits" or endpoint .. "/v1/images/generations"

	ivar2:Timer("imagegen_timeout_" .. tostring(os.time()) .. "_" .. random_id(), TIMEOUT, false, function()
		if not done then
			done = true
			reply("service busy, try later.")
		end
	end)

	simplehttp({
		method = "POST",
		url = url,
		data = json.encode(payload),
		headers = {
			["Authorization"] = "Bearer " .. apikey,
			["Content-Type"] = "application/json",
		},
		timeout = TIMEOUT,
	}, function(data, _uri, response)
		if done then
			return
		end

		if not data then
			done = true
			return reply("could not reach the image service.")
		end

		local status = response and response.status_code

		if status == 401 then
			done = true
			return reply("authentication failed.")
		end

		if status == 400 then
			done = true
			local ok, err = pcall(json.decode, data)
			local msg = ok and err and (err.error and err.error.message or err.message or "Bad request") or "Bad request"
			return reply("API error: %s", msg)
		end

		if status == 500 then
			done = true
			return reply("generation failed, try again.")
		end

		if status ~= 200 then
			done = true
			return reply("unexpected response from the image service (status %d).", status or -1)
		end

		local ok, result = pcall(json.decode, data)
		if not ok or not result or not result.data or not result.data[1] or not result.data[1].b64_json then
			done = true
			return reply("invalid response from the image service.")
		end

		done = true
		self:Msg("privmsg", destination, source, save_image(result.data[1].b64_json))
	end)
end

return {
	PRIVMSG = {
		["^%paimage (.+)$"] = function(self, source, destination, arg)
			arg = arg:gsub("^%s+", ""):gsub("%s+$", "")
			if #arg == 0 then
				return reply("please provide a prompt for image generation.")
			end

			if not apikey then
				return reply("image generation is not configured.")
			end

			local url = arg:match("https?://[^%s]+")
			if not url then
				generate_image(self, source, destination, arg, nil)
				return
			end

			local prompt = arg:gsub("https?://[^%s]+", ""):gsub("^%s+", ""):gsub("%s+$", "")
			if #prompt == 0 then
				return reply("please provide a prompt along with the image URL.")
			end

			say("downloading image from %s...", url)

			simplehttp({
				url = url,
				timeout = 30,
			}, function(imgdata)
				if not imgdata or #imgdata == 0 then
					return reply("could not download the image from that URL.")
				end

				local encoded = base64.encode(imgdata)
				generate_image(self, source, destination, prompt, encoded)
			end)
		end,
	},
}
