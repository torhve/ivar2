cqueues = require 'cqueues'
dns = require'cqueues.dns'
packet = require'cqueues.dns.packet'
record = require'cqueues.dns.record'
errno = require'cqueues.errno'
socket = require'cqueues.socket'
context = require'openssl.ssl.context'
monotime = cqueues.monotime
http_tls = require'http.tls'
pkey = require'openssl.pkey'
auxlib = require"openssl.auxlib"
util = require'util'
{:simplehttp, :bold, :split, :green, :red, :simplehttp, :json, :urlEncode} = require'util'

cache = {}

HasValue = (table, value) ->
  if(type(table) ~= 'table') then return
  for _, v in next, table
    if(v == value) then return true

Good = ->
  "#{green '🔒'} TLS #{green 'ok'}"

Bad = ->
  "#{red '🔓 '} #{red 'Bad'} TLS"

Query = (host, types='AAAA,A', timeout=15) ->
  out = {}

  for type in *split(types, ',')
    answer = dns.query(host, type, 'IN', timeout)

    for rec in answer\grep{section:packet.section.ANSWER}
      out[#out+1] = tostring(rec)

  return out

{
  PRIVMSG: {
    '^%pttls (.*)$': (source, destination, arg) =>
      host = arg\match'^%s*(.-)[:%s].*$' or arg
      port = arg\match'^.*[: ](.*)%s*$' or 443
      port = tonumber(port) or 0
      if port <= 0 or port > 65535
        return reply "Think you're clever?"
      hosts = Query(host)
      if #hosts == 0
        -- assume IP
        hosts = {host}
      found = false
      for ip in *hosts
        sock = socket.connect{host:ip, :port, verify:false, tls_sendname:host}
        ok, sock, err = pcall -> sock\connect 5
        if not ok
          return say "Error connecting to #{ip}:#{port} : #{sock}"
        if ip\match':'
          ip = '[' .. ip .. ']'
        if not sock
          reply "Error #{err} connecting to #{ip}:#{port} : #{errno.strerror err}"
        else
          ctx = http_tls.new_client_context()
          --ctx = context.new('SSL3', false)
          --ctx\setOptions(context.OP_NO_COMPRESSION+contextopenssl_ctx.OP_SINGLE_ECDH_USE)
          --ctx\setEphemeralKey(pkey.new{ type = "EC", curve = "prime256v1" }
          ok, tls, err = pcall -> sock\starttls 5
          if not ok
            return say "TLS negotiation error : #{tls}"
          if tls
            ssl = tls\checktls!
            if sock
              sock\close!
            cipher = ssl\getCipherInfo!
            if http_tls.banned_ciphers[cipher.name]
              return say "Banned cipher: #{cipher.name} when negotiating TLS #{ip}:#{port}"
            cert = ssl\getPeerCertificate!
            before, after = cert\getLifetime!
            cn = tostring cert\getSubject!
            san = cert\getSubjectAlt!
            validhosts = {cn\match'CN=(.*)'}
            for type, sanhost in auxlib.pairs(san)
              table.insert(validhosts, sanhost)
            -- cheat and parse text
            text = cert\text!
            @Log 'debug', text
            expires = text\match('Not After : (.-)%s*Sub')
            verdict = Good!
            reason = ''
            -- Check for wildcard
            for _, host in ipairs(validhosts)
              if host\match '^*.'
                -- replace the wildcard with a valid lua pattern
                host = host\gsub '^%*', '%w'
            foundValidHost = false
            for validhost in *validhosts
              -- use match to match wildcards
              if host\match(validhost)
                foundValidHost = true
                break
            if not foundValidHost
              verdict = Bad!
              reason = "Hostname #{host} not in list #{table.concat validhosts, ', '}"
            if after < os.time!
              verdict = Bad!
              reason ..= " #{red 'Expired'} cert!"

            say "#{verdict} #{reason} #{ip}:#{port}. Expires #{expires} Cipher: #{cipher.bits} bits #{cipher.name}."
          else
            reply "Error #{err} when negotiating TLS #{ip}:#{port} : #{err}"
          found = true
        if found
          break
    '^%pconnect (.*)[:%s]([0-9]+)$': (source, destination, host, port) =>
      port = tonumber port
      if port < 0 or port > 65535
        return reply "Think you're clever?"
      hosts = Query(host)
      if #hosts == 0
        -- assume IP
        hosts = {host}
      for ip in *hosts
        sock = socket.connect(ip, port)
        ok, sock, err = pcall -> sock\connect 5
        if not ok
          return say "Error connecting to #{ip}:#{port} : #{sock}"
        if ok and sock
          sock\close!
        if ip\match':'
          ip = '[' .. ip .. ']'
        if not sock
          reply "Error #{err} connecting to #{ip}:#{port} : #{errno.strerror err}"
        else
          say "Yup, could connect to #{ip}:#{port}"
          break
    '^%pdns (.*)$': (source, destination, arg) =>
      args = split arg, ' '
      argc = #args
      host = args[1]
      types = 'AAAA,A'
      if argc == 2
        types = args[1]
        host = args[2]

      out = Query(host, types)

      if #out == 0
        say "No answers"
      say table.concat(out, ' ')

    '^%pipv6 stats$': (source, destination) =>
      @Send "WHO #{destination}"
    '^%pipv6 stats (.*)$': (source, destination, dest) =>
      @Send "WHO #{dest}"
    '^%phttp (.*)$': (source, destination, arg) =>
      args = split arg, ' '
      argc = #args
      url = args[1]
      field = ''
      if argc == 2
        field = args[1]
        url = args[2]
      unless url\match '^http'
        url = 'http://' .. url
      before = monotime!
      data, uri, response = simplehttp(url)
      after = monotime!
      ms = (after-before)*100
      unless data
        reply 'Error: '..tostring(uri)
      unless response
        reply data..uri
      status = response.status_code
      headers = {}
      if argc == 1
        for k, v in pairs response.headers
          headers[#headers+1] = "#{k}:#{v}"
        table.sort(headers)
        headers = table.concat(headers, ', ')
        say string.format "Time: %d ms HTTP v#{response.version} #{headers}", ms
      elseif argc == 2
        field = field\lower!
        value = response.headers[field]
        if field == 'version'
          value = response.version

        say "#{field} : #{value or 'Header not found'}"
    '^%pwhereis (.*)$': (source, destination, arg) =>
      -- Download from http://dev.maxmind.com/geoip/geoip2/geolite2/
      geodb = (require "mmdb").open("cache/GeoLite2-City.mmdb")
      -- if space, use first
      if arg\match'(.-) .*'
        arg = arg\match'(.-) .*'
      p = (obj) ->
        out = {}
        if obj.city and obj.city.names and obj.city.names.en
          out[#out+1] = obj.city.names.en
        if obj.subdivisions and obj.subdivisions[1] and obj.subdivisions[1].names and obj.subdivisions[1].names.en
          out[#out+1] = obj.subdivisions[1].names.en
        if obj.country and obj.country.names and obj.country.names.en
          out[#out+1] = obj.country.names.en
        say table.concat(out, ', ')
      if arg\match '%d+%.%d+%.%d+%.%d+'
        obj = geodb\search_ipv4 arg
        p obj
      elseif arg\match ':'
        obj = geodb\search_ipv6 arg
        p obj
      else
        reply 'Needs valid IPv4'


  }
  ['352']: {
    (source, destination, input) =>
      --:efnet.port80.se 352 xt #jensaskaret xt 2a02:cc41:100f::1 efnet.port80.se xt H :0 Tor H.
      unless cache[destination]
        cache[destination] = {}

      nick = input.nick
      host = input.host
      --if @channels[destination]
      cache[destination][nick] = host

  }
  ['315']: {
    (source, destination, input) =>
      -- nondeterministic order.. hey ho here we go
      -- TODO use condition?
      cqueues.sleep(2)
      ipv4 = 0
      ipv6 = 0
      cloak = 0
      for nick, host in pairs(cache[destination])
        if host\match ':'
          ipv6 += 1
        elseif host\match '/' -- freenode cloak
          cloak += 1
        elseif host\match '%d+%.%d+%.%d+%.%d+'
          ipv4 += 1
        else
          timeout = 360
          ok, packet, err = pcall(dns.query, host, 'AAAA', 'IN', timeout)
          if not ok
            print 'pack', ok, packet, err
            print(debug.traceback())
          elseif not packet
            print 'no packet for host', host
            ipv4 += 1
          elseif packet\count() >= 2 -- 1 for question and atleast 1 for answer
            ipv6 = ipv6 + 1
          else
            ipv4 = ipv4 + 1
      -- Empty cache
      cache[destination] = nil
      percent = math.floor(100*ipv6/(ipv4+ipv6+cloak))
      out = "IP stats: #{bold percent}% IPv6. #{ipv6} IPv6 clients. #{ipv4} IPv4 clients. "
      if cloak > 0
        out = out .. "#{cloak} cloaked hosts."
      say out
  }
}
