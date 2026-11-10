local module_helper = require 'module_helper'
local cjson = require 'cjson'
local real_util = require 'util'

-- The module emits through ivar2:Say so nested helpers work, so the spec captures Say
local said

-- plain substring search on bytes, Lua 5.1 plain find trips over multibyte needles
local findIn = function(haystack, needle)
	if(haystack:find(needle, 1, true)) then return true end
	local needleBytes = {needle:byte(1, -1)}
	local hayBytes = {haystack:byte(1, -1)}
	for i = 1, #hayBytes - #needleBytes + 1 do
		local match = true
		for j = 1, #needleBytes do
			if(hayBytes[i + j - 1] ~= needleBytes[j]) then
				match = false
				break
			end
		end
		if(match) then return true end
	end
	return nil
end

local expect = function(msg, ...)
	for _, needle in ipairs({...}) do
		assert.is_not_nil(findIn((msg or ''), needle),
			'expected <' .. needle .. '> in <' .. tostring(msg) .. '>')
	end
end

local last = function()
	local entry = said[#said]
	return entry and entry.msg
end

-- Same bytes as the tag in the module, hugging face emoji in brackets
local tag = '[\240\159\164\151]'

local repo = function(id, created, updated, tags)
	return {
		id = id,
		modelId = id,
		createdAt = created .. 'T00:00:00.000Z',
		lastModified = updated .. 'T00:00:00.000Z',
		downloads = 1000,
		likes = 10,
		pipeline_tag = 'text-generation',
		tags = tags or {'transformers'},
	}
end

describe('huggingface module', function()
	local context, sent, state

	before_each(function()
		said = {}
		state = {
			byAuthor = {Qwen = {repo('Qwen/Alpha', '2026-01-01', '2026-01-02')}},
			search = {},
			repos = {},
		}

		package.loaded['util'] = {
			json = cjson,
			urlEncode = function(s) return s:gsub('/', '%%2F') end,
			simplehttp = function(req)
				local url = req.url
				local ok = {status_code = 200, headers = {}}

				local author = url:match('api/models%?author=([^&]+)')
				if(author) then
					if(author == 'nobody') then return '[]', url, ok end
					return cjson.encode(state.byAuthor[author] or {}), url, ok
				end

				local query = url:match('api/models%?search=([^&]+)')
				if(query) then
					-- the hub matches on words, so mimic it with the last path segment
					local needle = query:gsub('%%2F', '/'):match('/([^/]+)$') or query
					local out = {}
					for _, r in ipairs(state.search) do
						if(r.id:find(needle, 1, true)) then out[#out + 1] = r end
					end
					return cjson.encode(out), url, ok
				end

				local repoId = url:match('api/models/([%w%.%-%_]+/[%w%.%-%_]+)')
				if(repoId) then
					if(state.repos[repoId]) then return cjson.encode(state.repos[repoId]), url, ok end
					return '{"error":"Not found"}', url, {status_code = 404, headers = {}}
				end

				return nil, url, {status_code = 500, headers = {}}
			end,
		}

		local mock_bot = module_helper.mock_ivar2({
			config = {
				prefix = '!',
				nick = 'ivar2',
				huggingface = {authors = {'Qwen'}, interval = 60, channels = {'#lart'}},
			},
			nick = 'ivar2',
		})

		-- ivar2.persist is redis backed: every read hands back a fresh copy, so a helper
		-- that mutates one without storing it again is a no-op. The fake must do the same.
		local deepCopy
		deepCopy = function(value)
			if(type(value) ~= 'table') then return value end
			local out = {}
			for key, item in pairs(value) do out[key] = deepCopy(item) end
			return out
		end
		local stored = {}
		mock_bot.persist = setmetatable({}, {
			__index = function(_, key) return deepCopy(stored[key]) end,
			__newindex = function(_, key, value) stored[key] = deepCopy(value) end,
		})

		said, sent = {}, {}
		-- announcements send with ivar2.nick as the source, replies send with the source table
		mock_bot.Msg = function(self, t, destination, source, text)
			local entry = {destination = destination, msg = text}
			if(type(source) == 'string') then
				table.insert(sent, entry)
			else
				table.insert(said, entry)
			end
		end
		mock_bot.Log = function() end

		context = module_helper.context('huggingface', mock_bot)
	end)

	after_each(function()
		package.loaded['util'] = real_util
	end)

	it('answers to both !hf and !huggingface', function()
		for _, trigger in ipairs({'hf', 'huggingface'}) do
			assert.is_not_nil(context.mod.PRIVMSG['^' .. '%p' .. trigger .. '$'], trigger)
			assert.is_not_nil(context.mod.PRIVMSG['^' .. '%p' .. trigger .. ' (.+)$'], trigger)
		end
	end)

	it('sets up a polling timer when loaded', function()
		assert.is_not_nil(context.mock._timer_cb)
	end)

	it('tags everything it says', function()
		context:invoke('!hf help')
		expect(last(), tag, '!hf polls and lists the newest')
		assert.are_equal(1, #said)
		assert.are_equal(tag, last():sub(1, #tag))
	end)

	it('!hf polls and reports the newest, staying quiet on the first run', function()
		context:invoke('!hf')
		expect(last(), tag, 'Qwen/Alpha (2026-01-01)')
		assert.are_equal(0, #sent)
	end)

	it('announces a repo it has not seen before', function()
		context:invoke('!hf')
		state.byAuthor.Qwen = {
			repo('Qwen/Alpha', '2026-01-01', '2026-01-02'),
			repo('Qwen/Beta', '2026-01-03', '2026-01-03'),
		}
		sent = {}
		context:invoke('!hf')

		assert.are_equal(1, #sent)
		expect(sent[1].msg, tag, 'new model', 'Qwen/Beta', 'text-generation 1000 dl 10 like', '2026-01-03',
			'https://huggingface.co/Qwen/Beta')
		assert.are_equal('#lart', sent[1].destination)
		expect(last(), tag, '1 new, 0 updated')
	end)

	it('names the base model of a quant or a fine tune', function()
		context:invoke('!hf')
		state.byAuthor.Qwen = {
			repo('Qwen/Alpha', '2026-01-01', '2026-01-02'),
			repo('unsloth/Alpha-GPTQ-Int4', '2026-01-04', '2026-01-04',
				{'gptq', 'base_model:Qwen/Alpha', 'base_model:quantized:Qwen/Alpha'}),
		}
		sent = {}
		context:invoke('!hf unsloth') -- read only lookup must not mark anything as seen
		context:invoke('!hf')

		assert.are_equal(1, #sent)
		expect(sent[1].msg, 'unsloth/Alpha-GPTQ-Int4', 'of Qwen/Alpha')
	end)

	it('!hf only <pattern> hides what does not match', function()
		context:invoke('!hf only qwen')
		expect(last(), tag, 'announcing repos matching qwen')

		state.byAuthor.Qwen = {
			repo('Qwen/Alpha', '2026-01-01', '2026-01-02'),
			repo('nobody/Noise', '2026-01-05', '2026-01-05'),
		}
		sent = {}
		context:invoke('!hf')
		assert.are_equal(0, #sent)

		context:invoke('!hf list')
		expect(last(), 'filter qwen')

		context:invoke('!hf only all')
		expect(last(), tag, 'announcing everything from Qwen')
	end)

	it('looks up one author or one repo', function()
		context:invoke('!hf nobody')
		expect(last(), tag, 'nothing found for nobody')

		state.repos['Meta/Llama-Test'] = repo('Meta/Llama-Test', '2026-02-01', '2026-02-09')
		context:invoke('!hf Meta/Llama-Test')
		expect(last(), tag, 'model', 'Meta/Llama-Test', 'new 2026-02-01', 'pushed 2026-02-09', '1000 dl')

		context:invoke('!hf Meta/DoesNotExist')
		expect(last(), tag, 'no such repo')
	end)

	it('!hf deriv finds repos that name a base model', function()
		state.search = {
			repo('unsloth/Alpha-GPTQ-Int4', '2026-01-04', '2026-01-04', {'base_model:quantized:Qwen/Alpha'}),
			repo('someone/Alpha-finetune', '2026-01-06', '2026-01-06', {'base_model:finetune:Qwen/Alpha'}),
			repo('other/Unrelated', '2026-01-07', '2026-01-07', {'transformers'}),
		}
		context:invoke('!hf deriv Qwen/Alpha')
		expect(last(), tag, '2 repos built on Qwen/Alpha', 'unsloth/Alpha-GPTQ-Int4', 'someone/Alpha-finetune')
		assert.is_nil(findIn(last(), 'Unrelated'))
	end)

	it('tracks a repo and pings when it is updated', function()
		state.repos['Qwen/Alpha'] = repo('Qwen/Alpha', '2026-01-01', '2026-01-02')
		context:invoke('!hf track Qwen/Alpha')
		expect(last(), tag, 'tracking Qwen/Alpha')

		context:invoke('!hf list')
		expect(last(), 'repos Qwen/Alpha', 'announcing here no')

		context:invoke('!hf list', {dest = '#lart'})
		expect(last(), 'announcing here yes')

		context:invoke('!hf') -- first poll seeds it
		assert.are_equal(0, #sent)

		state.repos['Qwen/Alpha'] = repo('Qwen/Alpha', '2026-01-01', '2026-01-20')
		sent = {}
		context:invoke('!hf')
		assert.are_equal(1, #sent)
		expect(sent[1].msg, tag, 'updated model', 'Qwen/Alpha', '2026-01-20', 'https://huggingface.co/Qwen/Alpha')

		context:invoke('!hf untrack Qwen/Alpha')
		expect(last(), tag, 'stopped tracking Qwen/Alpha')
		assert.are_equal(0, #context.mock.persist['huggingface:repos'])
	end)

	it('watches a whole org with !hf track <org>', function()
		context:invoke('!hf') -- seed the config author first
		state.byAuthor.unsloth = {repo('unsloth/Alpha-GGUF', '2026-01-05', '2026-01-05')}

		context:invoke('!hf track unsloth')
		expect(last(), tag, 'watching unsloth', '1 existing repos seeded')
		assert.is_not_nil(context.mock.persist['huggingface:seen']['unsloth/Alpha-GGUF'])

		context:invoke('!hf list')
		expect(last(), tag, 'authors Qwen/unsloth')

		state.byAuthor.unsloth = {
			repo('unsloth/Alpha-GGUF', '2026-01-05', '2026-01-05'),
			repo('unsloth/Beta-GGUF', '2026-01-10', '2026-01-10'),
		}
		sent = {}
		context:invoke('!hf')
		assert.are_equal(1, #sent)
		expect(sent[1].msg, tag, 'new model', 'unsloth/Beta-GGUF')

		context:invoke('!hf untrack unsloth')
		expect(last(), tag, 'stopped watching unsloth')

		context:invoke('!hf track Qwen')
		expect(last(), tag, 'Qwen is already in the config')
		context:invoke('!hf untrack Qwen')
		expect(last(), tag, 'Qwen comes from the config')
	end)

	it('turns channel announcements on and off with !hf on/off', function()
		context:invoke('!hf') -- seed
		context:invoke('!hf on', {dest = '#other'})
		expect(last(), tag, 'announcing new Qwen repos here')

		state.byAuthor.Qwen = {
			repo('Qwen/Alpha', '2026-01-01', '2026-01-02'),
			repo('Qwen/Gamma', '2026-01-08', '2026-01-08'),
		}
		sent = {}
		context:invoke('!hf')
		assert.are_equal(2, #sent)

		context:invoke('!hf off', {dest = '#other'})
		expect(last(), tag, 'stopped announcing here')
		context:invoke('!hf off', {dest = '#other'})
		expect(last(), tag, 'was not listening here')
	end)
end)
