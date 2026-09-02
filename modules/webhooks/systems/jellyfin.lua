-- Jellyfin webhook, configured with NO template: the server then posts the
-- full raw notification data table as JSON. We build the message here instead
-- of maintaining a handlebars template server-side.
--
-- Field names match Jellyfin's template variables (NotificationType, Name,
-- SeriesName, SeasonNumber00, IsLiveTv, DeviceName, ClientName, ...).

local util = require 'util'

-- Ticks are 100ns units. Convert to "H:MM:SS" / "MM:SS".
local function ticks_str(ticks)
	local t = tonumber(ticks)
	if not t or t < 0 then return nil end
	local secs = math.floor(t / 10000000)
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	if h > 0 then
		return string.format('%d:%02d:%02d', h, m, s)
	end
	return string.format('%d:%02d', m, s)
end

local function jellyfin_format(data)
	local t = data and data.NotificationType
	if not t then
		return nil
	end

	local user = data.NotificationUsername or data.Username or 'unknown'
	local name = data.Name or '-'
	local server = data.ServerName or 'Jellyfin'

	-- Helpers for common compound phrases
	local function ep_label()
		local s = tonumber(data.SeasonNumber00) or tonumber(data.SeasonNumber) or 0
		local e = tonumber(data.EpisodeNumber00) or tonumber(data.EpisodeNumber) or 0
		local series = data.SeriesName or name
		return string.format('%s S%02dE%02d %s', series, s, e, name)
	end
	local function device_client()
		local parts = {}
		if data.DeviceName then table.insert(parts, data.DeviceName) end
		if data.ClientName then table.insert(parts, data.ClientName) end
		return #parts > 0 and table.concat(parts, ' / ') or nil
	end

	if t == 'Generic' then
		return '[Jellyfin] ' .. name

	elseif t == 'ItemAdded' then
		local itype = data.ItemType
		local msg
		if itype == 'Season' then
			msg = (data.SeriesName or '') .. ' ' .. name
		elseif itype == 'Episode' then
			msg = ep_label()
		else
			local year = data.Year and string.format(' (%s)', data.Year) or ''
			msg = name .. year
		end
		return '[Jellyfin] ' .. util.green('＋') .. ' ' .. msg .. ' added to ' .. util.bold(server)

	elseif t == 'PlaybackStart' then
		local dc = device_client()
		local suffix = dc and ' on ' .. dc or ''
		if data.IsLiveTv then
			return '[Jellyfin] ' .. util.green('▶') .. ' ' .. user .. ' started live '
				.. util.bold(name) .. suffix
		end
		return '[Jellyfin] ' .. util.green('▶') .. ' ' .. user .. ' started '
			.. ep_label() .. suffix

	elseif t == 'PlaybackStop' then
		local dc = device_client()
		local suffix = dc and ' on ' .. dc or ''
		if data.IsLiveTv then
			return '[Jellyfin] ' .. util.red('■') .. ' ' .. user .. ' stopped live '
				.. util.bold(name) .. suffix
		end
		return '[Jellyfin] ' .. util.red('■') .. ' ' .. user .. ' stopped '
			.. ep_label() .. suffix

	elseif t == 'PlaybackProgress' then
		local pos = ticks_str(data.PlaybackPositionTicks)
		local dur = ticks_str(data.RunTimeTicks)
		local where = pos and (dur and (pos .. ' / ' .. dur) or pos) or nil
		local dc = device_client()
		local who = (dc and user .. ' on ' .. dc) or user
		if where then
			return '[Jellyfin] ' .. util.cyan('⏱') .. ' ' .. who .. ': ' .. where
		end
		return nil

	elseif t == 'PluginInstalling' then
		return '[Jellyfin] ' .. util.yellow('↓') .. ' installing plugin '
			.. util.bold(data.PluginName or '?') .. ' ' .. (data.PluginVersion or '')

	elseif t == 'PluginInstalled' then
		return '[Jellyfin] ' .. util.green('✓') .. ' plugin '
			.. util.bold(data.PluginName or '?') .. ' ' .. (data.PluginVersion or '')
			.. ' installed (restart may be required)'

	elseif t == 'PluginUninstalled' then
		return '[Jellyfin] ' .. util.red('✗') .. ' plugin '
			.. util.bold(data.PluginName or '?') .. ' ' .. (data.PluginVersion or '')
			.. ' uninstalled (restart may be required)'

	elseif t == 'PluginUpdated' then
		return '[Jellyfin] ' .. util.green('↑') .. ' plugin '
			.. util.bold(data.PluginName or '?') .. ' ' .. (data.PluginVersion or '')
			.. ' updated (restart may be required)'

	elseif t == 'PluginInstallationCancelled' then
		return '[Jellyfin] ' .. util.yellow('⊘') .. ' plugin '
			.. util.bold(data.PluginName or '?') .. ' ' .. (data.PluginVersion or '')
			.. ' installation cancelled'

	elseif t == 'PluginInstallationFailed' then
		local detail = data.ExceptionMessage and ' — ' .. data.ExceptionMessage or ''
		return '[Jellyfin] ' .. util.red('✗') .. ' plugin '
			.. util.bold(data.PluginName or '?') .. ' ' .. (data.PluginVersion or '')
			.. ' installation failed' .. detail

	elseif t == 'UserCreated' then
		return '[Jellyfin] ' .. util.green('＋') .. " user '" .. user .. "' created on "
			.. util.bold(server)

	elseif t == 'UserDeleted' then
		return '[Jellyfin] ' .. util.red('－') .. " user '" .. user .. "' deleted on "
			.. util.bold(server)

	elseif t == 'UserLockedOut' then
		return '[Jellyfin] ' .. util.orange('🔒') .. " user '" .. user
			.. "' locked out (too many failed attempts)"

	elseif t == 'UserPasswordChanged' then
		return '[Jellyfin] ' .. util.yellow('🔑') .. " password for user '" .. user .. "' changed"

	elseif t == 'AuthenticationFailure' then
		return '[Jellyfin] ' .. util.red('⛔') .. " auth failed for '" .. user .. "'"

	elseif t == 'AuthenticationSuccess' then
		local last = data.LastLoginDate and ' (last ' .. data.LastLoginDate .. ')' or ''
		return '[Jellyfin] ' .. util.green('✓') .. " '" .. user .. "' authenticated" .. last

	elseif t == 'TaskCompleted' then
		local status = data.ResultStatus or '?'
		local scolor = (status:lower() == 'success') and util.green or util.red
		return '[Jellyfin] ' .. util.cyan('⚙') .. " task '" .. (data.TaskName or '?')
			.. "' completed: " .. scolor(status)

	elseif t == 'SessionStart' then
		local dc = data.DeviceName
		local suffix = dc and ' on ' .. dc or ''
		return '[Jellyfin] ' .. util.teal('●') .. " session started for '" .. user .. "'" .. suffix

	elseif t == 'PendingRestart' then
		return '[Jellyfin] ' .. util.orange('↻') .. ' ' .. util.bold(server) .. ' requires a restart'

	else
		ivar2:Log('warn', 'webhooks> unknown jellyfin notification type: %s', t)
		return nil
	end
end

return jellyfin_format
