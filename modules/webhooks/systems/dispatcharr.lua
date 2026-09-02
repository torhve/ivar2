local util = require 'util'

local function bytes_human(n)
    if not n or n == 0 then return '-' end
    local num = tonumber(n)
    if num < 1024 then return tostring(num) .. ' B' end
    if num < 1048576 then return string.format('%.1f KB', num / 1024) end
    if num < 1073741824 then return string.format('%.1f MB', num / 1048576) end
    return string.format('%.1f GB', num / 1073741824)
end

local function detect_dispatcharr_event(json)
    if json.error_type then
        return 'channel_error'
    end
    if json.channel_name and json.runtime then
        return 'channel_stop'
    end
    if json.channel_name and json.attempt then
        return 'channel_reconnect'
    end
    if json.channel_name and json.reason and json.duration then
        return 'channel_failover'
    end
    if json.channel_name and json.new_url then
        return 'stream_switch'
    end
    if json.recording_id and json.bytes_written then
        return 'recording_end'
    end
    if json.recording_id then
        return 'recording_start'
    end
    if json.source_name and json.programs then
        return 'epg_refresh'
    end
    if json.account_name and json.streams_created then
        return 'm3u_refresh'
    end
    if json.channel_name and json.client_ip and json.client_id and json.duration then
        return 'client_disconnect'
    end
    if json.channel_name and json.client_ip and json.client_id then
        return 'client_connect'
    end
    if json.content_name and json.content_uuid then
        return 'vod'
    end
    if json.user and json.reason and not json.channel_name then
        return 'login_failed'
    end
    if json.profile and json.reason and json.client_ip then
        return 'blocked'
    end
    if json.channel_name and json.stream_name then
        return 'channel_start'
    end
    return 'unknown'
end

local function dispatcharr_format(json)
    local event = detect_dispatcharr_event(json)

    if event == 'channel_start' then
        local channel = util.bold(json.channel_name or '-')
        local stream = json.stream_name or '-'
        local provider = json.provider_name or ''
        local profile = json.profile_used or ''
        local parts = { '[Dispatcharr]', util.green('▶'), channel .. ':' }
        table.insert(parts, stream)
        if provider ~= '' then table.insert(parts, '(' .. provider .. ')') end
        if profile ~= '' then table.insert(parts, util.teal(profile)) end
        return table.concat(parts, ' ')

    elseif event == 'channel_stop' then
        local channel = util.bold(json.channel_name or '-')
        local runtime = json.runtime or '?'
        local bytes = json.total_bytes and bytes_human(json.total_bytes) or '-'
        return '[Dispatcharr] ' .. util.red('■') .. ' ' .. channel .. ' stopped (' .. runtime .. 's, ' .. bytes .. ')'

    elseif event == 'channel_reconnect' then
        local channel = util.bold(json.channel_name or '-')
        local attempt = json.attempt or '?'
        local max = json.max_attempts or '?'
        local provider = json.provider_name or ''
        local extra = provider ~= '' and ' (' .. provider .. ')' or ''
        local msg = '[Dispatcharr] '
            .. util.yellow('↻')
            .. ' ' .. channel
            .. ' reconnected (' .. attempt .. '/' .. max .. ')'
            .. extra
        return msg

    elseif event == 'channel_error' then
        local channel = util.bold(json.channel_name or '-')
        local errtype = json.error_type or 'unknown'
        local errmsg = json.error_message or ''
        local detail = errmsg ~= '' and ' — ' .. errmsg or ''
        return '[Dispatcharr] ' .. util.bold(util.red('!')) .. ' ' .. channel .. ': ' .. util.red(errtype) .. detail

    elseif event == 'channel_failover' then
        local channel = util.bold(json.channel_name or '-')
        local reason = json.reason or '-'
        local dur = json.duration or '?'
        return '[Dispatcharr] ' .. util.orange('⚡') .. ' ' .. channel .. ' failover: ' .. reason .. ' (' .. dur .. 's)'

    elseif event == 'stream_switch' then
        return nil

    elseif event == 'recording_start' then
        local channel = util.bold(json.channel_name or '-')
        return '[Dispatcharr] ' .. util.teal('●') .. ' ' .. channel .. ' recording started'

    elseif event == 'recording_end' then
        local channel = util.bold(json.channel_name or '-')
        local interrupted = json.interrupted
        local bytes = json.bytes_written and bytes_human(json.bytes_written) or '-'
        local status = interrupted and util.red('interrupted') or util.green('complete')
        return '[Dispatcharr] ' .. util.teal('●') .. ' ' .. channel .. ' recording ' .. status .. ' (' .. bytes .. ')'

    elseif event == 'epg_refresh' then
        return nil

    elseif event == 'm3u_refresh' then
        return nil

    elseif event == 'client_connect' then
        local channel = util.bold(json.channel_name or '-')
        local ip = json.client_ip or '-'
        local user = json.username or ''
        local ua = json.user_agent or ''
        local parts = { '[Dispatcharr]', util.green('●'), channel .. ': connected from ' .. ip }
        if user ~= '' then table.insert(parts, '(' .. user .. ')') end
        if ua ~= '' then table.insert(parts, util.teal(ua)) end
        return table.concat(parts, ' ')

    elseif event == 'client_disconnect' then
        local channel = util.bold(json.channel_name or '-')
        local user = json.username or ''
        local dur = json.duration and string.format('%.0fs', json.duration) or '?'
        local bytes = json.bytes_sent and bytes_human(json.bytes_sent) or '-'
        local parts = { '[Dispatcharr]', util.red('●'), channel .. ': disconnected (' .. dur .. ', ' .. bytes .. ')' }
        if user ~= '' then table.insert(parts, 3, user .. ': ') end
        return table.concat(parts, ' ')

    elseif event == 'login_failed' then
        local user = json.user or 'unknown'
        local ip = json.client_ip or '-'
        local reason = json.reason or '-'
        return '[Dispatcharr] ' .. util.bold(util.red('!')) .. ' login failed: ' .. user .. '@' .. ip .. ' — ' .. reason

    elseif event == 'blocked' then
        local profile = json.profile or 'all'
        local ip = json.client_ip or '-'
        local reason = json.reason or '-'
        local btype = json.user and 'M3U' or 'EPG'
        local msg = '[Dispatcharr] '
            .. util.red('⛔')
            .. ' ' .. btype .. ' blocked: '
            .. profile .. ' from ' .. ip
            .. ' — ' .. reason
        return msg

    elseif event == 'vod' then
        local name = util.bold(json.content_name or '-')
        local user = json.username or ''
        local ip = json.client_ip or ''
        local who = (user ~= '' and user) or ip
        return '[Dispatcharr] ' .. util.cyan('◈') .. ' ' .. name .. ' (' .. who .. ')'

    else
        local keys = {}
        for k in pairs(json) do table.insert(keys, k) end
        ivar2:Log('warn', 'webhooks> unknown dispatcharr event, keys: %s', table.concat(keys, ', '))
        return nil
    end
end

return dispatcharr_format
