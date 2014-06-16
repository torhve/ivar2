-- Persist from 
-- https://github.com/clementfarabet/persist

local redis = require'redis' -- luarocks install lua-redis
local json = require 'cjson'
require'logging.console'
local log = logging.console()

-- Connect
function connect(opt)
   -- Namespace:
   opt = opt or {}
   local url = opt.url or 'localhost'
   local port = opt.port or 6379
   local namespace = opt.namespace
   if namespace then
      namespace = namespace .. ':'
   else
      namespace = ''
   end
   local verbose = opt.verbose or false
   local clear = opt.clear or false
   local cache = opt.cache or false

   -- Connect:
   local ok,client = pcall(function() return redis.connect(url,port) end)
   if not ok then
      log:error('persist> error connecting to redis @ ' .. url .. ':' .. port)
      log:error('persist> make sure you have a running redis server (redis-server)')
   end

   -- New persisting table:
   local persist = {}
   local __cached = {}
   setmetatable(persist, {
      __newindex = function(self,k,v)
         if k=="_" then log:info('persist> _ is a reserved keyword') return end
         if cache then __cached[k] = v end
         client = redis.connect(url,port)
         if v then
            v = json.encode(v)
            client:set(namespace..k,v)
            if verbose then
               log:info('persist> stored ' .. k)
            end
         else
            client:del(namespace..k)
            if verbose then
               log:info('persist> cleared ' .. k)
            end
         end
      end,
      __index = function(self,k)
         if k=="_" then return __cached end
         client = redis.connect(url,port)
         local v = client:get(namespace..k)
         v = v and json.decode(v)
         if verbose then
            log:info('persist> restored ' .. k)
         end
         return v
      end,
      __tostring = function(self)
         local keys = client:keys(namespace..'*')
         local n = #keys
         return '<persisting table @ redis://'..namespace..'*, #keys='..n..'>'
      end,
      keys = function(self)
         local keys = client:keys(namespace..'*')
         return keys
      end
   })

   -- Restore:
   if cache then
      local keys = client:keys(namespace..'*')
      for _,key in ipairs(keys) do
         local k = key:gsub('^'..namespace,'')
         __cached[k] = persist[k]
      end
   end

   -- Clear?
   if clear then
      local keys = client:keys(namespace..'*')
      local n = #keys
      for _,key in ipairs(keys) do
         local k = key:gsub('^'..namespace,'')
         client:del(namespace..k)
      end
      if verbose then
         log:info('persist> cleared ' .. n .. ' entries')
      end
   end

   -- Verbose:
   if verbose then
      -- N Keys:
      local keys = client:keys(namespace..'*')
      local n = #keys
      if n == 0 then
         log:info('persist> new session started @ ' .. url .. ':' .. port)
      else
         log:info('persist> restored session @ ' .. url .. ':' .. port)
         log:info('persist> restored ' .. n .. ' keys')
      end
   end

   -- Return the magic table
   return persist, client
end

-- Return connector
return connect
