local busted = require'busted'
local describe = busted.describe
local it = busted.it
describe("test moonscript loader lib", function()
  it("should load and report errors correctly", function()
    local moonloader = require 'moonloader'
    local fname = 'modules/moontest.moon'
    local file, err, getTrace, rewriteMessage = moonloader.load(fname)
    local pattern, moduleFun = next(file()['PRIVMSG'])
    local ok, err = pcall(moduleFun)
    if not ok then
      --print ('error', err)
      ---print(debug.traceback(getTrace(fname, err)))
      local info = debug.getinfo(moduleFun)
      info.msg = err
      info.traceback = debug.traceback('', 1)
      for k, v in pairs(getTrace(fname, info)) do
        print (k, v)
      end
    end
  end)
end)
