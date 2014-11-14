-- simple key value store on top of sqlite3
-- adapted from redis persist by clementfarabet by Tor Hveem

local sql = require'lsqlite3'
local json = require 'cjson'
require'logging.console'
local log = logging.console()

-- Connect
function open(opt)
   -- Namespace:
   opt = opt or {}
   local path = opt.path or 'keyvaluestore.sqlite3'
   local namespace = opt.namespace
   if namespace then
      namespace = namespace .. ':'
   else
      namespace = ''
   end
   local verbose = opt.verbose or false
   local clear = opt.clear or false
   local cache = opt.cache or false

   local function openDb()
       log:info('persist> opening sqlite db @ ' .. path )
       db = sql.open(path)
       db:exec([[
           CREATE TABLE IF NOT EXISTS kv (
               key text,
               value text,
               UNIQUE (key) ON CONFLICT REPLACE
           );
       ]])
       return db
   end

   local function listKeys()
       local keys = {}
       local stmt = db:prepare('SELECT key FROM kv WHERE key LIKE ?')
       local code = stmt:bind_values(namespace..'%')
       for row in stmt:rows() do
            table.insert(keys, row[1])
       end
       stmt:finalize()
       return keys
   end


   -- Connect:
   local ok, db = pcall(function() return openDb() end)
   if not ok then
      log:error('persist> error opening sqlite db @ ' .. path )
   end

   -- New persisting table:
   local persist = {}
   local __cached = {}
   setmetatable(persist, {
      __newindex = function(self,k,v)
         if k=="_" then log:info('persist> _ is a reserved keyword') return end
         if cache then __cached[k] = v end
         if v then
            v = json.encode(v)
            local insStmt = db:prepare("INSERT INTO kv (key, value) VALUES(?, ?)")
            local code = insStmt:bind_values(namespace..k, v)
            code = insStmt:step()
            code = insStmt:finalize()
            if verbose then
               log:info('persist> stored ' .. k)
            end
         else
            local delStmt = db:prepare("DELETE FROM kv WHERE key = ?)")
            local code = delStmt:bind_values(namespace..k)
            code = insStmt:step()
            code = insStmt:finalize()
            if verbose then
               log:info('persist> cleared ' .. k)
            end
         end
      end,
      __index = function(self,k)
         if k=="_" then return __cached end
         local stmt = db:prepare('SELECT value FROM kv WHERE key = ?')
         local code = stmt:bind_values(namespace..k)
         local code = stmt:step()
         local v
         if code == sql.DONE then
             v = nil
         elseif code == sql.ROW then
             v = stmt:get_value(0)
         end
         local code = stmt:finalize()
         v = v and json.decode(v)
         if verbose then
            log:info('persist> restored ' .. k)
         end
         return v
      end,
      __tostring = function(self)
         local keys = listKeys()
         local n = #keys
         return '<persisting table @ sqlite3://'..namespace..'*, #keys='..n..'>'
      end,
      keys = function(self)
         local keys = listKeys()
         return keys
      end
   })

   -- Restore:
   if cache then
      local keys = listKeys()
      for _,key in ipairs(keys) do
         local k = key:gsub('^'..namespace,'')
         __cached[k] = persist[k]
      end
   end

   -- Clear?
   if clear then
      local keys = listKeys()
      local n = #keys
      for _,key in ipairs(keys) do
         local delStmt = db:prepare("DELETE FROM kv WHERE key = ?)")
         local code = delStmt:bind_values(key)
         code = insStmt:step()
         code = insStmt:finalize()
      end
      if verbose then
         log:info('persist> cleared ' .. n .. ' entries')
      end
   end

   -- Verbose:
   if verbose then
      -- N Keys:
      local keys = listKeys()
      local n = #keys
      if n == 0 then
         log:info('persist> new session started @ ' .. path)
      else
         log:info('persist> restored session @ ' .. path)
         log:info('persist> restored ' .. n .. ' keys')
      end
   end

   -- Return the magic table
   return persist, db
end

-- Return openor
return open
