local split = function(str, pattern)
	local out = {}
	str:gsub('[^' .. pattern ..']+', function(match)
		table.insert(out, match)
	end)

	return out
end

local shell = function(cmd)
	local out, h
	h = assert(io.popen(cmd, "r"))
	out = h:read"*all"
	out = out:gsub("\n$", ""):gsub("\n", ", "):gsub("\t", "| "):gsub("\r", "")
	h:close()

	return out
end

local readGitLog = function()
	local cl = shell'git log --date=relative --pretty=format:"%x1e%ar%x1f%s%x1f" --name-only'
	local logs = split(cl, '\030')
	for i=1, #logs do
		local entry = logs[i]
		local relTime, logEntry, files = entry:match('([^\031]+)\031([^\031]+)\031(.*)')
		files = split(files:sub(3, -4), ',')
		logs[i] = {time = relTime, log = logEntry, files = files}
	end

	return logs
end

local getModuleString = function(files)
	local touched = {}
	for k,v in ipairs(files) do
		local name = v:gsub('modules/', ''):gsub('%.lua', ''):gsub('ircbot', 'core'):gsub('ivar2', 'core')
		table.insert(touched, name)
	end

	return ivar2.util.bold('[' .. table.concat(touched, ',') .. ']')
end

return {
	PRIVMSG = {
		['^%pchangelog%s*(.*)$'] = function(self, source, destination, num)
			local cl = readGitLog()
			if(#num > 0) then
				local total = #cl
				local entry = cl[tonumber(num)]
				if(entry) then
					say('(%d/%d) %s %s | %s', tonumber(num), total, getModuleString(entry.files), entry.time, entry.log)
				end
			else
				local total = #cl
				local entry = cl[1]
				say('(%d/%d) %s %s | %s', 1, total, getModuleString(entry.files), entry.time, entry.log)
			end
		end
	}
}
