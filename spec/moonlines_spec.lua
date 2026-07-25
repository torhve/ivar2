local busted = require'busted'
local describe = busted.describe
local it = busted.it

describe('moonlines', function()
  local moonlines
  local moon

  before_each(function()
    package.loaded['moonlines'] = nil
    moonlines = require 'moonlines'
    moon = require 'moonscript'
  end)

  describe('loadfile', function()
    it('loads a .moon file and captures metadata', function()
      local func = moonlines.loadfile(moon, 'spec/fixtures/error_module.moon')
      assert.is_not_nil(func)
      assert.is_function(func)
    end)

    it('returns nil for non-existent file', function()
      local func, err = moonlines.loadfile(moon, 'nonexistent.moon')
      assert.is_nil(func)
      assert.is_not_nil(err)
    end)
  end)

  describe('rewrite_error', function()
    it('rewrites error line numbers from lua to moon', function()
      moonlines.loadfile(moon, 'spec/fixtures/error_module.moon')

      local msg = 'spec/fixtures/error_module.moon:10: runtime boom'
      local rewritten = moonlines.rewrite_error(msg)
      assert.truthy(rewritten:match('%(lua:10%)'))
    end)

    it('rewrites multiple line references in a traceback', function()
      moonlines.loadfile(moon, 'spec/fixtures/error_module.moon')

      local tb = [[spec/fixtures/error_module.moon:10: error message
stack traceback:
	spec/fixtures/error_module.moon:10: in function <spec/fixtures/error_module.moon:9>]]
      local rewritten = moonlines.rewrite_error(tb)
      assert.truthy(rewritten:match('spec/fixtures/error_module.moon:%d+ %(lua:10%)'))
    end)

    it('preserves angle brackets in traceback paths', function()
      moonlines.loadfile(moon, 'spec/fixtures/error_module.moon')

      local tb = 'spec/fixtures/error_module.moon:10: in function <spec/fixtures/error_module.moon:9>'
      local rewritten = moonlines.rewrite_error(tb)
      assert.truthy(rewritten:find('<.*>'))
      assert.truthy(rewritten:find('lua:9'))
    end)

    it('passes through non-moon errors unchanged', function()
      local msg = '/path/to/file.lua:42: some error'
      local rewritten = moonlines.rewrite_error(msg)
      assert.are_equal(msg, rewritten)
    end)

    it('passes through unknown .moon files unchanged', function()
      local msg = 'unknown.moon:5: some error'
      local rewritten = moonlines.rewrite_error(msg)
      assert.are_equal(msg, rewritten)
    end)
  end)

  describe('pcall', function()
    it('returns success for non-erroring function', function()
      local ok, result = moonlines.pcall(function() return 'hello' end)
      assert.is_true(ok)
      assert.are_equal('hello', result)
    end)

    it('rewrites errors from moonscript handlers', function()
      local func = moonlines.loadfile(moon, 'spec/fixtures/error_module.moon')
      local env = {}
      setmetatable(env, {__index = _G})
      setfenv(func, env)
      local mod = func()

      local handler = mod.PRIVMSG['!more']
      setfenv(handler, env)

      local ok, err = moonlines.pcall(handler, nil, nil, nil, nil)
      assert.is_false(ok)
      assert.truthy(err:match('%(lua:%d+%)'))
    end)

    it('rewrites errors from nested handlers', function()
      local func = moonlines.loadfile(moon, 'spec/fixtures/error_module.moon')
      local env = {}
      setmetatable(env, {__index = _G})
      setfenv(func, env)
      local mod = func()

      local handler = mod.PRIVMSG['!nested']
      setfenv(handler, env)

      local ok, err = moonlines.pcall(handler, nil, nil, nil, nil)
      assert.is_false(ok)
      assert.truthy(err:match('%(lua:%d+%)'))
    end)
  end)
end)
